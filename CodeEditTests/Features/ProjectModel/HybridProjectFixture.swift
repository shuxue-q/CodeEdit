//
//  HybridProjectFixture.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Writes a workspace shaped like OmniExam: a Flutter app at the root whose native assets hook
/// builds a CMake project, which links a Rust staticlib from a Cargo workspace in `rust/`, plus
/// a vendored Flutter package, Flutter's Windows runner, and folders that must be skipped.
enum HybridProjectFixture {
    static let files: [String: String] = [
        "pubspec.yaml": """
        name: omniexam_app
        version: 0.6.0+1
        environment:
          sdk: ^3.13.0
        dependencies:
          flutter:
            sdk: flutter
          ffi: ^2.1.4
          hooks: ^2.0.2
          flutter_math_fork:
            path: third_party/flutter_math_fork
        dev_dependencies:
          build_runner: ^2.4.0
        flutter:
          uses-material-design: true
        """,
        ".metadata": "project_type: app\nmigration:\n  platforms:\n    - platform: root\n    - platform: macos\n",
        "analysis_options.yaml": "include: package:flutter_lints/flutter.yaml\nanalyzer:\n  exclude:\n    - cpp/**\n",
        "hook/build.dart": "// Runs cmake -S . -B build, then copies the library.\nvoid main() {}\n",
        "lib/main.dart": "void main() {}\n",
        "macos/Runner/AppDelegate.swift": "",
        "CMakeLists.txt": """
        cmake_minimum_required(VERSION 3.25)
        project(omniexam LANGUAGES C CXX)
        add_subdirectory(cpp)
        """,
        "CMakePresets.json": "{\"version\": 3, \"configurePresets\": []}",
        "cpp/CMakeLists.txt": """
        add_library(omniexam_core SHARED src/core.cpp)
        # Typst kernel (Rust staticlib, rust/omniexam_typst), built with cargo.
        find_program(OMNIEXAM_CARGO cargo)
        """,
        "cpp/src/core.cpp": "",
        "rust/Cargo.toml": """
        [workspace]
        resolver = "2"
        members = ["omniexam_typst"]
        [profile.release]
        lto = "thin"
        """,
        "rust/rust-toolchain.toml": "[toolchain]\nchannel = \"1.97.1\"\ntargets = [\"aarch64-apple-darwin\"]\n",
        "rust/omniexam_typst/Cargo.toml": """
        [package]
        name = "omniexam_typst"
        version = "0.1.0"
        edition = "2024"
        [lib]
        crate-type = ["staticlib", "rlib"]
        [[bin]]
        name = "omniexam_typst_cli"
        path = "src/bin/omniexam_typst_cli.rs"
        [features]
        default = []
        fast = []
        """,
        "rust/omniexam_typst/src/lib.rs": "",
        "rust/omniexam_typst/src/bin/omniexam_typst_cli.rs": "",
        "rust/omniexam_typst/examples/render.rs": "",
        "rust/omniexam_typst/build.rs": "",
        "third_party/flutter_math_fork/pubspec.yaml": """
        name: flutter_math_fork
        version: 0.7.4
        dependencies:
          flutter:
            sdk: flutter
        """,
        "windows/CMakeLists.txt": "project(omniexam_app LANGUAGES CXX)\n",
        "windows/flutter/CMakeLists.txt": "",
        "windows/runner/CMakeLists.txt": "project(runner LANGUAGES CXX)\n",
        // Skipped: hidden folders, build output and caches.
        ".claude/worktrees/copy/pubspec.yaml": "name: copy\ndependencies:\n  flutter:\n    sdk: flutter\n",
        "build/macos-debug/CMakeLists.txt": "project(generated)\n",
        "rust/target/debug/Cargo.toml": "[package]\nname = \"ignored\"\n",
        ".dart_tool/package_config.json": "{}"
    ]

    /// Writes the fixture into `root`.
    static func write(in root: URL) throws {
        for (path, contents) in files {
            let url = root.appending(path: path)
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
