//
//  LldbDapLocator.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

/// Locates the `lldb-dap` executable on the user's system.
///
/// CodeEdit does not ship or install a debug adapter; the binary is expected to
/// come from Xcode's toolchain or a user-installed LLVM. Detection mirrors
/// ``LanguageServerDetector``: it searches the user's login shell `PATH` first,
/// then falls back to `xcrun`.
enum LldbDapLocator {
    /// Returns the URL of the `lldb-dap` executable, or `nil` if it cannot be found.
    ///
    /// This spawns the user's login shell and may take a moment. Do not call on
    /// the main thread.
    static func locate() -> URL? {
        if let path = LanguageServerDetector.locateExecutables(["lldb-dap"])["lldb-dap"],
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return locateViaXcrun()
    }

    /// Asks Xcode's toolchain for the location of `lldb-dap`.
    private static func locateViaXcrun() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "lldb-dap"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting so a full pipe buffer cannot deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
