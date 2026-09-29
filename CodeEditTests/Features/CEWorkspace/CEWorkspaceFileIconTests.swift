//
//  CEWorkspaceFileIconTests.swift
//  CodeEditTests
//
//  Created by Kimi on 9/21/26.
//

@testable import CodeEdit
import Testing
import AppKit

@Suite
struct CEWorkspaceFileIconTests {

    private func file(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/fake/dir/\(name)"))
    }

    @Test(arguments: ["CMakeLists.txt", "FindFoo.cmake", "toolchain.cmake"])
    func cmakeIcons(name: String) {
        #expect(file(name).systemImage == "cmake")
    }

    @Test(arguments: ["main.cpp", "main.cc", "main.cxx"])
    func cppIcons(name: String) {
        #expect(file(name).systemImage == "cpp")
    }

    @Test(arguments: ["main.c"])
    func cIcons(name: String) {
        #expect(file(name).systemImage == "c")
    }

    @Test(arguments: ["header.h"])
    func cheaderIcons(name: String) {
        #expect(file(name).systemImage == "cheader")
    }

    @Test(arguments: ["header.hpp", "header.hh", "header.hxx"])
    func hppIcons(name: String) {
        #expect(file(name).systemImage == "hpp")
    }

    @Test(arguments: ["Makefile", "makefile", "GNUmakefile", "rules.mk"])
    func makefileIcons(name: String) {
        #expect(file(name).systemImage == "makefile")
    }

    @Test
    func cmakeListsFileType() {
        // The whole file name must win over the `.txt` extension.
        #expect(file("CMakeLists.txt").type == .CMakeLists)
    }

    @Test
    func shellFilesKeepTerminalIcon() {
        #expect(file("build.sh").systemImage == "terminal")
        #expect(file("run.zsh").systemImage == "terminal")
    }

    @Test(arguments: ["c", "cheader", "cmake", "cpp", "hpp", "makefile"])
    func customSymbolsExistInAppBundle(name: String) throws {
        #expect(NSImage(named: name) != nil)
    }

    @Test(arguments: ["c", "cheader", "cmake", "cpp", "hpp"])
    func svgIconsAreIconSized(name: String) throws {
        // SVG images render at their intrinsic size in the navigator and tabs,
        // so they must be small enough to fit the icon slot.
        let image = try #require(NSImage(named: name))
        #expect(image.size.width <= 16)
        #expect(image.size.height <= 16)
    }
}
