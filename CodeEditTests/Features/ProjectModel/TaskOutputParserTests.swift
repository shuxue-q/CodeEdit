//
//  TaskOutputParserTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct TaskOutputParserTests {
    private let base = URL(filePath: "/w/rust")

    private func parse(_ parser: some TaskOutputParser, _ text: String) -> [CMakeBuildDiagnostic] {
        var parser = parser
        var found: [CMakeBuildDiagnostic] = []
        for line in text.components(separatedBy: "\n") {
            found += parser.consume(line: TaskOutputText.strippingANSI(line))
        }
        return found + parser.finish()
    }

    // MARK: - Cargo

    @Test
    func readsRustcErrorsAndWarnings() {
        let output = """
           Compiling omniexam_typst v0.1.0 (/w/rust/omniexam_typst)
        \u{1B}[1m\u{1B}[33mwarning\u{1B}[0m\u{1B}[1m: unused variable: `x`\u{1B}[0m
          \u{1B}[1m\u{1B}[94m--> \u{1B}[0momniexam_typst/src/lib.rs:4:9
           |
        4  |     let x = 1;
           |         ^ help: if this is intentional, prefix it with an underscore: `_x`

        error[E0425]: cannot find value `y` in this scope
         --> omniexam_typst/src/lib.rs:10:5
          |
        10 |     y
          |     ^ not found in this scope

        warning: `omniexam_typst` (lib) generated 1 warning
        error: could not compile `omniexam_typst` (lib) due to 1 previous error; 1 warning emitted
        """
        let diagnostics = parse(CargoOutputParser(baseDirectory: base), output)
        #expect(diagnostics.count == 3)
        #expect(diagnostics[0].severity == .warning)
        #expect(diagnostics[0].message == "unused variable: `x`")
        #expect(diagnostics[0].filePath == "/w/rust/omniexam_typst/src/lib.rs")
        #expect(diagnostics[0].line == 4)
        #expect(diagnostics[0].column == 9)
        #expect(diagnostics[1].severity == .error)
        #expect(diagnostics[1].code == "E0425")
        #expect(diagnostics[1].line == 10)
        #expect(diagnostics[2].message.hasPrefix("could not compile `omniexam_typst`"))
        #expect(diagnostics[2].filePath == nil)
    }

    @Test
    func readsTestPanics() {
        let output = """
        running 1 test
        thread 'tests::renders' panicked at omniexam_typst/src/lib.rs:42:9:
        assertion `left == right` failed
        """
        let diagnostics = parse(CargoOutputParser(baseDirectory: base), output)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message == "Test panicked: assertion `left == right` failed")
        #expect(diagnostics[0].line == 42)
    }

    // MARK: - Flutter

    @Test
    func readsDartCompilerAnalyzerAndNativeMessages() {
        let output = """
        Launching lib/main.dart on macOS in debug mode...
        lib/main.dart:12:3: Error: Expected ';' after this.
          print('x')
          ^^^^^
        lib/widgets/card.dart:8:10: Warning: Operand of null-aware operation '?.' has type 'String'.
          error • Undefined name 'foo' • lib/home.dart:3:5 • undefined_identifier
           info • Unused import • lib/home.dart:1:8 • unused_import
        /w/app/cpp/src/core.cpp:7:1: error: unknown type name 'foo'
        Error (Xcode): /w/app/macos/Runner/AppDelegate.swift:5:9: error: cannot find 'bar' in scope
        Error (Xcode): Command PhaseScriptExecution failed with a nonzero exit code
        Error: No pubspec.yaml file found.
        """
        let diagnostics = parse(FlutterOutputParser(baseDirectory: URL(filePath: "/w/app")), output)
        let summary = diagnostics.map { "\($0.severity.rawValue) \($0.filePath ?? "-"):\($0.line ?? 0) \($0.message)" }
        #expect(summary == [
            "error /w/app/lib/main.dart:12 Expected ';' after this.",
            "warning /w/app/lib/widgets/card.dart:8 Operand of null-aware operation '?.' has type 'String'.",
            "error /w/app/lib/home.dart:3 Undefined name 'foo'",
            "note /w/app/lib/home.dart:1 Unused import",
            "error /w/app/cpp/src/core.cpp:7 unknown type name 'foo'",
            "error /w/app/macos/Runner/AppDelegate.swift:5 cannot find 'bar' in scope",
            "error -:0 Command PhaseScriptExecution failed with a nonzero exit code",
            "error -:0 No pubspec.yaml file found."
        ])
        #expect(diagnostics[2].code == "undefined_identifier")
    }

    @Test
    func joinsAnalyzerMessagesWrappedToTheTerminalWidth() {
        // `flutter analyze` in an 80-column terminal.
        let output = """
        Analyzing demo_pkg...

          error • Undefined name 'undefinedName'. Try correcting the name to one that is
                 defined, or defining the name • lib/demo_pkg.dart:1:17 •
                 undefined_identifier
          error • The function 'Calculator' isn't defined. Try importing the library
                 that defines 'Calculator', correcting the name to the name of an
                 existing function, or defining a function named 'Calculator' •
                 test/demo_pkg_test.dart:7:24 • undefined_function
        warning • Unused import • lib/a.dart:1:8 • unused_import

        3 issues found. (ran in 2.6s)
        """
        let diagnostics = parse(FlutterOutputParser(baseDirectory: URL(filePath: "/w/pkg")), output)
        #expect(diagnostics.map(\.code) == ["undefined_identifier", "undefined_function", "unused_import"])
        let expected = "Undefined name 'undefinedName'. Try correcting the name to one that is defined, "
            + "or defining the name"
        #expect(diagnostics.first?.message == expected)
        #expect(diagnostics.first?.filePath == "/w/pkg/lib/demo_pkg.dart")
        #expect(diagnostics[1].line == 7)
    }

    @Test
    func stripsColorsAndTitles() {
        #expect(TaskOutputText.strippingANSI("\u{1B}[31mred\u{1B}[0m \u{1B}]0;title\u{07}done") == "red done")
    }

    // MARK: - Monitor and store

    @MainActor
    @Test
    func monitorSplitsTerminalLinesAndReportsHotReloadEvents() {
        let store = TaskDiagnosticsStore()
        let taskID = UUID()
        let monitor = TaskOutputMonitor(
            taskID: taskID,
            name: "Run app",
            parserKind: .flutter,
            baseDirectory: URL(filePath: "/w"),
            store: store,
            watchesFlutterRun: true
        )
        var events: [TaskOutputMonitor.FlutterRunEvent] = []
        monitor.onFlutterRunEvent = { events.append($0) }
        // Chunks split mid-line and between "\r" and "\n", as a pseudo-terminal delivers them.
        let chunks = [
            "lib/main.dart:3:1: Error: Bad",
            " thing.\r",
            "\nFlutter run key commands.\r\n",
            "Reloaded 1 of 812 libraries in 240ms (compile: 20 ms).\r\n",
            "lib/main.dart:3:1: Error: Bad thing.\r\n"
        ]
        for chunk in chunks {
            monitor.consume(ArraySlice(Array(chunk.utf8)))
        }
        monitor.finish()
        #expect(store.all.map(\.message) == ["Bad thing."])
        // A finished run ignores output that arrives later (it may belong to the next run).
        monitor.consume(ArraySlice(Array("lib/late.dart:1:1: Error: Late.\r\n".utf8)))
        #expect(store.all.count == 1)
        #expect(events == [.readyForHotReload, .reloaded("Reloaded 1 of 812 libraries in 240ms (compile: 20 ms).")])

        store.reset(taskID: taskID, name: "Run app")
        #expect(store.isEmpty)
    }

    // MARK: - Settings

    @Test
    func settingsDecodeLeniently() throws {
        let flutter = try JSONDecoder().decode(FlutterProjectSettings.self, from: Data("""
        {"buildMode": "turbo", "device": "  ", "hotReloadOnSave": "yes", "flavor": "dev",
         "dartDefines": [{"name": "A", "value": "1"}]}
        """.utf8))
        #expect(flutter.buildMode == .debug)
        #expect(flutter.device == nil)
        #expect(flutter.hotReloadOnSave)
        #expect(flutter.modeArguments == ["--debug", "--flavor", "dev", "--dart-define=A=1"])

        let cargo = try JSONDecoder().decode(CargoProjectSettings.self, from: Data("""
        {"roots": {"rust": {"profile": "", "features": ["a"], "allFeatures": true,
                            "runTarget": {"package": "p", "kind": "example", "name": "demo"}}}}
        """.utf8))
        let root = cargo.root("rust")
        #expect(root.profile == "dev")
        #expect(root.runTarget == CargoRunTarget(package: "p", kind: .example, name: "demo"))
        #expect(root.buildArguments(profiles: []) == ["--all-features"])
        #expect(cargo.root("missing") == CargoProjectSettings.Root())
    }

    @MainActor
    @Test
    func settingsFileSavesAndReloads() throws {
        try withTempDir { root in
            let file = ProjectSettingsFile<CargoProjectSettings>(workspaceDirectory: root)
            file.value.roots["."] = CargoProjectSettings.Root()
            try file.save()
            #expect(FileManager.default.fileExists(atPath: root.appending(path: ".codeedit/cargo-settings.json").path))
            var changed = CargoProjectSettings()
            changed.roots["."] = { var value = CargoProjectSettings.Root(); value.profile = "release"; return value }()
            try JSONEncoder().encode(changed).write(to: file.fileURL)
            var notified = false
            file.onChange = { _ in notified = true }
            file.reloadFromDisk()
            #expect(file.value.root(".").profile == "release")
            #expect(notified)
        }
    }
}
