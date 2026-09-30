//
//  CMakeToolchainDetector.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// A compiler found on the system.
struct DetectedCompiler: Identifiable, Hashable, Sendable {
    enum Family: String, Sendable {
        case appleClang = "Apple Clang"
        case clang = "Clang"
        case gcc = "GCC"
        case unknown = "Compiler"
    }

    let path: String
    let family: Family
    let version: String?
    /// The vendor prefix reported by the compiler, such as "Homebrew".
    let vendor: String?

    var id: String { path }

    /// A short name such as "Apple Clang 17.0.0" or "Homebrew Clang 19.1.7".
    var title: String {
        let name = [vendor, family.rawValue].compactMap { $0 }.joined(separator: " ")
        return [name, version].compactMap { $0 }.joined(separator: " ")
    }
}

/// A build tool found on the system.
struct DetectedTool: Hashable, Sendable {
    let path: String
    let version: String?
}

/// The result of scanning the system for a CMake toolchain.
struct CMakeToolchainScan: Equatable, Sendable {
    var cCompilers: [DetectedCompiler] = []
    var cxxCompilers: [DetectedCompiler] = []
    var cmake: DetectedTool?
    /// Generators whose build tool was found.
    var availableGenerators: Set<CMakeGenerator> = []
}

/// Locates compilers, CMake, and generator build tools. Performs file-system checks and runs
/// `--version`; call it off the main actor. It has no UI dependencies.
enum CMakeToolchainDetector {
    /// Directories scanned in addition to the user's `PATH`, in priority order.
    static let standardDirectories = [
        "/usr/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/homebrew/opt/llvm/bin",
        "/usr/local/opt/llvm/bin"
    ]

    /// Extra locations checked for CMake when it is not on any scanned path.
    static let cmakeFallbacks = ["/Applications/CMake.app/Contents/bin/cmake"]

    private static let cCompilerPattern = #"^(cc|clang|gcc)(-[0-9]+(\.[0-9]+)*)?$"#
    private static let cxxCompilerPattern = #"^(c\+\+|clang\+\+|g\+\+)(-[0-9]+(\.[0-9]+)*)?$"#

    /// Scans the system.
    /// - Parameter environment: The environment whose `PATH` is searched, normally the user's
    ///   login shell environment.
    static func scan(environment: [String: String]) -> CMakeToolchainScan {
        let directories = searchDirectories(path: environment["PATH"])
        var scan = CMakeToolchainScan()
        scan.cCompilers = compilers(matching: cCompilerPattern, in: directories)
        scan.cxxCompilers = compilers(matching: cxxCompilerPattern, in: directories)
        if let cmake = firstExecutable(named: "cmake", in: directories) ?? cmakeFallbacks.first(where: isExecutable) {
            scan.cmake = DetectedTool(path: cmake, version: run(cmake, ["--version"]).flatMap(parseCMakeVersion))
        }
        for generator in CMakeGenerator.allCases
        where firstExecutable(named: generator.buildTool, in: directories) != nil {
            scan.availableGenerators.insert(generator)
        }
        return scan
    }

    /// The `PATH` entries followed by the standard directories, without duplicates.
    static func searchDirectories(path: String?) -> [String] {
        var seen: Set<String> = []
        let pathEntries = (path ?? "").split(separator: ":").map(String.init)
        return (pathEntries + standardDirectories).filter { directory in
            guard directory.hasPrefix("/") else { return false }
            let normalized = URL(filePath: directory).standardizedFileURL.path
            return seen.insert(normalized).inserted
        }
    }

    // MARK: - Compilers

    private static func compilers(matching pattern: String, in directories: [String]) -> [DetectedCompiler] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var candidates: [String] = []
        var seenTargets: Set<String> = []
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            let matching = names.sorted().filter {
                regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
            }
            for name in matching {
                let path = URL(filePath: directory).appending(path: name).path
                // Symlinked aliases (for example Homebrew's `gcc-14` and `gcc`) show once.
                let target = URL(filePath: path).resolvingSymlinksInPath().path
                guard isExecutable(path), seenTargets.insert(target).inserted else { continue }
                candidates.append(path)
            }
        }
        // `--version` goes through xcrun for the /usr/bin shims, which can take a moment.
        var results = [DetectedCompiler?](repeating: nil, count: candidates.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let path = candidates[index]
            let output = run(path, ["--version"])
            let compiler = output.map { parseCompilerVersion($0, path: path) }
            lock.lock()
            results[index] = compiler
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    /// Identifies a compiler from its `--version` output.
    static func parseCompilerVersion(_ output: String, path: String) -> DetectedCompiler {
        let firstLine = output.split(separator: "\n").first.map(String.init) ?? ""
        if let match = firstLine.firstMatch(of: #/^Apple (?:LLVM|clang) version ([0-9][0-9.]*)/#) {
            return DetectedCompiler(path: path, family: .appleClang, version: String(match.1), vendor: nil)
        }
        if let match = firstLine.firstMatch(of: #/^(?:(.+?) )?clang version ([0-9][0-9.]*)/#) {
            return DetectedCompiler(
                path: path,
                family: .clang,
                version: String(match.2),
                vendor: match.1.map(String.init)
            )
        }
        // GCC prints "<name> (<package>) <version>", for example "gcc-14 (Homebrew GCC 14.2.0) 14.2.0".
        if firstLine.contains("GCC") || firstLine.hasPrefix("gcc") || firstLine.hasPrefix("g++"),
           let match = firstLine.firstMatch(of: #/\) ([0-9]+(?:\.[0-9]+)+)/#) {
            let vendor = firstLine.contains("Homebrew GCC") ? "Homebrew" : nil
            return DetectedCompiler(path: path, family: .gcc, version: String(match.1), vendor: vendor)
        }
        return DetectedCompiler(path: path, family: .unknown, version: nil, vendor: nil)
    }

    /// Extracts the version from `cmake --version` output ("cmake version 3.31.2").
    static func parseCMakeVersion(_ output: String) -> String? {
        output.firstMatch(of: #/cmake version ([0-9][0-9A-Za-z.\-]*)/#).map { String($0.1) }
    }

    // MARK: - Helpers

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private static func firstExecutable(named name: String, in directories: [String]) -> String? {
        directories.lazy
            .map { URL(filePath: $0).appending(path: name).path }
            .first(where: isExecutable)
    }

    /// Runs a tool and returns its combined output, or `nil` if it fails to start, exits
    /// with an error, or takes longer than `timeout`.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Read before waiting so a full pipe cannot block the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
