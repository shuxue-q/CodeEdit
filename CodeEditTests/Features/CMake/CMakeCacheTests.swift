//
//  CMakeCacheTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/17/26.
//

import XCTest
@testable import CodeEdit

final class CMakeCacheTests: XCTestCase {
    private var root: URL!

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    func testMissingCacheIsNotConfigured() throws {
        let directories = try makeDirectories()
        XCTAssertFalse(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testMatchingCacheIsConfigured() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: directories.source.path,
            cacheDirectory: directories.build.path,
            in: directories.build
        )
        XCTAssertTrue(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testTrailingSlashAndCommentsDoNotBreakIdentity() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: directories.source.path + "/",
            cacheDirectory: directories.build.path + "/",
            in: directories.build,
            extra: """
            //Path to the source
            # ignored
            """
        )
        XCTAssertTrue(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testForeignHomeDirectoryIsNotConfigured() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: "/Users/other/Supersonic Transport/panair",
            cacheDirectory: "/Users/other/Supersonic Transport/panair/build",
            in: directories.build
        )
        XCTAssertFalse(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testMismatchedCacheFileDirectoryIsNotConfigured() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: directories.source.path,
            cacheDirectory: "/tmp/other-build",
            in: directories.build
        )
        XCTAssertFalse(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testMalformedCacheIsNotConfigured() throws {
        let directories = try makeDirectories()
        try FileManager.default.createDirectory(at: directories.build, withIntermediateDirectories: true)
        try "CMAKE_CACHEFILE_DIR".write(
            to: directories.build.appending(path: "CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertFalse(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testHomeMatchWithoutCacheFileDirectoryIsConfigured() throws {
        let directories = try makeDirectories()
        try writeCache(home: directories.source.path, cacheDirectory: nil, in: directories.build)
        XCTAssertTrue(CMakeCache.isConfigured(
            sourceDirectory: directories.source,
            buildDirectory: directories.build
        ))
    }

    func testInvalidateRemovesConfigurationKeepsArtifacts() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: directories.source.path,
            cacheDirectory: directories.build.path,
            in: directories.build
        )
        let cmakeFiles = directories.build.appending(path: "CMakeFiles")
        try FileManager.default.createDirectory(at: cmakeFiles, withIntermediateDirectories: true)
        try "stale".write(to: cmakeFiles.appending(path: "VerifyGlobs.cmake"), atomically: true, encoding: .utf8)
        try "[]".write(
            to: directories.build.appending(path: "compile_commands.json"),
            atomically: true,
            encoding: .utf8
        )
        try "keep".write(to: directories.build.appending(path: "libkeep.a"), atomically: true, encoding: .utf8)

        CMakeCache.invalidateConfiguration(at: directories.build)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.build.appending(path: "CMakeCache.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cmakeFiles.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directories.build.appending(path: "compile_commands.json").path)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: directories.build.appending(path: "libkeep.a").path))
    }

    func testStandaloneCompilationDatabaseIsUsable() throws {
        let directories = try makeDirectories()
        try FileManager.default.createDirectory(at: directories.build, withIntermediateDirectories: true)
        try "[]".write(
            to: directories.build.appending(path: "compile_commands.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(CMakeCache.isUsableCompilationDatabase(
            in: directories.build,
            sourceDirectory: directories.source
        ))
    }

    func testCompilationDatabaseNextToForeignCacheIsNotUsable() throws {
        let directories = try makeDirectories()
        try writeCache(
            home: "/Users/other/Supersonic Transport/panair",
            cacheDirectory: "/Users/other/Supersonic Transport/panair/build",
            in: directories.build
        )
        try "[]".write(
            to: directories.build.appending(path: "compile_commands.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertFalse(CMakeCache.isUsableCompilationDatabase(
            in: directories.build,
            sourceDirectory: directories.source
        ))
    }

    func testSamePathResolvesSymlinks() {
        let tmp = URL(filePath: "/tmp")
        XCTAssertTrue(CMakeCache.samePath("/tmp", tmp))
        XCTAssertTrue(CMakeCache.samePath("/private/tmp", tmp))
        XCTAssertTrue(CMakeCache.samePath("/tmp/", tmp))
    }

    private func makeDirectories() throws -> (source: URL, build: URL) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("src", isDirectory: true)
        let build = root.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        return (source, build)
    }

    private func writeCache(
        home: String,
        cacheDirectory: String?,
        in buildDirectory: URL,
        extra: String = ""
    ) throws {
        var contents = extra
        if !contents.isEmpty { contents.append("\n") }
        contents.append("CMAKE_HOME_DIRECTORY:INTERNAL=\(home)\n")
        if let cacheDirectory {
            contents.append("CMAKE_CACHEFILE_DIR:INTERNAL=\(cacheDirectory)\n")
        }
        try contents.write(
            to: buildDirectory.appending(path: "CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
