//
//  ProjectTaskCatalog.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import CryptoKit
import Foundation

/// What a generated task is, beyond its command line.
struct GeneratedTaskInfo: Equatable, Sendable {
    /// How the task runs.
    enum Action: Equatable, Sendable {
        /// A shell command in the task terminal.
        case shell
        /// The workspace's CMake build controller.
        case cmakeBuild
    }

    /// What the task does, for grouping and icons.
    enum Role: String, Sendable {
        case run, build, check, test, analyze, dependencies, generate, clean, docs
    }

    var action: Action
    var toolchain: ProjectToolchain
    var role: Role
    /// The heading the task is listed under, such as `Flutter · omniexam_app`.
    var group: String
    /// The component folder, relative to the workspace.
    var componentPath: String
    /// The parser that turns the task's output into problems.
    var outputParser: TaskOutputParserKind?
    /// Whether the task is `flutter run` in debug mode, which accepts hot reload keys.
    var supportsHotReload = false
}

/// A task generated from the project inventory and settings.
struct GeneratedTask: Equatable, Sendable {
    var name: String
    var command: String
    /// Relative to the workspace folder.
    var workingDirectory: String
    var environment: [String: String] = [:]
    var info: GeneratedTaskInfo

    /// A stable identifier derived from the task's group and name, so selection survives rescans.
    var id: UUID { Self.stableID(for: "\(info.group)\u{1F}\(name)") }

    /// A UUID derived from `text` with SHA-256, formatted as a version 5-style UUID.
    static func stableID(for text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// A task-manager task with this task's identity, command and environment.
    func makeTask() -> CETask {
        let task = CETask()
        task.id = id
        update(task)
        return task
    }

    /// Copies the name, command, folder and environment into an existing task, so a task that ran
    /// before (and whose terminal holds on to it) runs the new command next time.
    func update(_ task: CETask) {
        let variables = environment
            .sorted { $0.key < $1.key }
            .map { CETask.EnvironmentVariable(key: $0.key, value: $0.value) }
        if task.name != name { task.name = name }
        if task.command != command { task.command = command }
        let folder = workingDirectory == "." ? "" : workingDirectory
        if task.workingDirectory != folder { task.workingDirectory = folder }
        // Compare contents: each variable gets a fresh identifier.
        if task.environmentVariables.map({ [$0.key, $0.value] }) != variables.map({ [$0.key, $0.value] }) {
            task.environmentVariables = variables
        }
    }
}

/// Turns a workspace's inventory and settings into Flutter, Cargo and CMake tasks.
///
/// Commands are assembled from individually quoted arguments; user-entered argument strings are
/// split with ``CommandLineArguments`` first, so nothing is interpolated into the shell unquoted.
enum ProjectTaskCatalog {
    /// The inputs that come from the Flutter workspace.
    struct FlutterInputs: Sendable {
        var settings: FlutterProjectSettings
        /// The SDK's `bin` folder when it is not the one on `PATH` (an override); `nil` uses `PATH`.
        var sdkBinDirectory: URL?
        var device: FlutterDevice
    }

    /// The inputs that come from the CMake models.
    struct CMakeInputs: Sendable {
        var projectName: String
        /// Where `ctest` finds the tests.
        var buildDirectory: URL
        /// The `-C` configuration for multi-config generators.
        var configuration: String?
    }

    /// The generated tasks, Flutter first, then Rust, then C++.
    static func tasks(
        inventory: ProjectInventory,
        flutter: FlutterInputs?,
        cargoSettings: CargoProjectSettings,
        cmake: CMakeInputs?
    ) -> [GeneratedTask] {
        var tasks: [GeneratedTask] = []
        if let project = inventory.flutter, let flutter {
            tasks += flutterTasks(project, inputs: flutter, inventory: inventory)
        }
        for root in inventory.cargoRoots {
            let path = inventory.relativePath(of: root.directory)
            tasks += cargoTasks(
                root,
                relativePath: path,
                settings: cargoSettings.root(path),
                multipleRoots: inventory.cargoRoots.count > 1
            )
        }
        // The CMake build is listed only next to other generated tasks: on its own the Run button
        // already builds a CMake workspace.
        if let cmake, !tasks.isEmpty {
            tasks += cmakeTasks(cmake, inventory: inventory)
        }
        return tasks
    }

    // MARK: - Flutter

    /// Builds Flutter tasks of one package: every one shares the group, folder and parser.
    private struct FlutterTaskFactory {
        let group: String
        let path: String

        func task(
            _ name: String,
            _ role: GeneratedTaskInfo.Role,
            _ command: String,
            hotReload: Bool = false
        ) -> GeneratedTask {
            GeneratedTask(
                name: name,
                command: command,
                workingDirectory: path,
                info: GeneratedTaskInfo(
                    action: .shell,
                    toolchain: .flutter,
                    role: role,
                    group: group,
                    componentPath: path,
                    outputParser: .flutter,
                    supportsHotReload: hotReload
                )
            )
        }
    }

    private static func flutterTasks(
        _ project: FlutterProject,
        inputs: FlutterInputs,
        inventory: ProjectInventory
    ) -> [GeneratedTask] {
        // `--no-wrap` keeps the tool's messages on one line whatever the terminal width, so they parse.
        let flutter = tool("flutter", in: inputs.sdkBinDirectory) + " --no-wrap"
        let dart = tool("dart", in: inputs.sdkBinDirectory)
        let factory = FlutterTaskFactory(
            group: String(localized: "Flutter · \(project.name)"),
            path: inventory.relativePath(of: project.rootDirectory)
        )
        var tasks = flutterAppTasks(project, inputs: inputs, flutter: flutter, factory: factory)
        tasks.append(factory.task(String(localized: "Test \(project.name)"), .test, "\(flutter) test"))
        tasks.append(factory.task(String(localized: "Analyze \(project.name)"), .analyze, "\(flutter) analyze"))
        tasks.append(factory.task(String(localized: "Pub Get"), .dependencies, "\(flutter) pub get"))
        tasks.append(factory.task(String(localized: "Pub Upgrade"), .dependencies, "\(flutter) pub upgrade"))
        if project.pubspec.hasDependency(named: "build_runner") {
            let command = "\(dart) run build_runner build --delete-conflicting-outputs"
            tasks.append(factory.task(String(localized: "Build Runner"), .generate, command))
        }
        if project.hasFFIgenConfig || project.pubspec.hasDependency(named: "ffigen") {
            let command = "\(dart) run ffigen --config ffigen.yaml"
            tasks.append(factory.task(String(localized: "Generate FFI Bindings"), .generate, command))
        }
        tasks.append(factory.task(String(localized: "Clean \(project.name)"), .clean, "\(flutter) clean"))
        return tasks
    }

    /// Run and Build, for packages that are apps (they have platform folders).
    private static func flutterAppTasks(
        _ project: FlutterProject,
        inputs: FlutterInputs,
        flutter: String,
        factory: FlutterTaskFactory
    ) -> [GeneratedTask] {
        let isApp = project.metadata?.projectType.map { $0 == "app" } ?? !project.platforms.isEmpty
        guard isApp else { return [] }
        let settings = inputs.settings
        let modeArguments = settings.modeArguments.map { $0.escapedShellArgument() }
        let run = [flutter, "run", "-d", inputs.device.id.escapedShellArgument()]
            + modeArguments
            + CommandLineArguments.split(settings.runArguments).map { $0.escapedShellArgument() }
        var tasks = [factory.task(
            String(localized: "Run \(project.name)"),
            .run,
            run.joined(separator: " "),
            hotReload: settings.buildMode.supportsHotReload
        )]
        if let platform = buildPlatform(project: project, settings: settings, device: inputs.device) {
            let build = [flutter, "build", platform.buildCommand] + modeArguments
            let name = String(localized: "Build \(project.name) (\(platform.title))")
            tasks.append(factory.task(name, .build, build.joined(separator: " ")))
        }
        return tasks
    }

    /// A tool from the SDK's `bin` folder as a quoted path, or its bare name to find it on `PATH`.
    private static func tool(_ name: String, in binDirectory: URL?) -> String {
        binDirectory.map { $0.appending(path: name).path.escapedShellArgument() } ?? name
    }

    /// The platform `flutter build` targets: the chosen one, else the run device's, else macOS,
    /// as long as the project has that platform's folder.
    static func buildPlatform(
        project: FlutterProject,
        settings: FlutterProjectSettings,
        device: FlutterDevice
    ) -> FlutterPlatform? {
        let candidates = [settings.buildPlatform.flatMap(FlutterPlatform.init(rawValue:)), device.buildPlatform, .host]
        return candidates.compactMap { $0 }.first { project.platforms.contains($0) }
    }

    // MARK: - Cargo

    private static func cargoTasks(
        _ root: CargoRoot,
        relativePath path: String,
        settings: CargoProjectSettings.Root,
        multipleRoots: Bool
    ) -> [GeneratedTask] {
        let group = String(localized: "Rust · \(root.name)")
        let suffix = multipleRoots ? " \(root.name)" : ""
        let shared = settings.buildArguments(profiles: root.profiles).map { $0.escapedShellArgument() }
        let environment = Dictionary(
            settings.environment.filter { $0.isEnabled && !$0.name.isEmpty }.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        func task(
            _ name: String,
            _ role: GeneratedTaskInfo.Role,
            _ arguments: [String],
            environment: [String: String] = [:]
        ) -> GeneratedTask {
            GeneratedTask(
                name: name,
                command: (["cargo"] + arguments).joined(separator: " "),
                workingDirectory: path,
                environment: environment,
                info: GeneratedTaskInfo(
                    action: .shell,
                    toolchain: .cargo,
                    role: role,
                    group: group,
                    componentPath: path,
                    outputParser: .cargo
                )
            )
        }

        var tasks = [
            task(String(localized: "Cargo Build") + suffix, .build, ["build"] + shared),
            task(String(localized: "Cargo Check") + suffix, .check, ["check", "--all-targets"] + shared),
            task(String(localized: "Cargo Test") + suffix, .test, ["test"] + shared, environment: environment),
            task(String(localized: "Cargo Clippy") + suffix, .analyze, ["clippy", "--all-targets"] + shared),
            task(String(localized: "Cargo Doc") + suffix, .docs, ["doc", "--no-deps"] + shared)
        ]
        let runnable = root.runnableTargets
        let selected = settings.runTarget.flatMap { target in runnable.first { $0 == target } } ?? runnable.first
        for target in runnable {
            var arguments = ["run"] + target.cargoArguments.map { $0.escapedShellArgument() } + shared
            if target == selected {
                let programArguments = CommandLineArguments.split(settings.runArguments)
                if !programArguments.isEmpty {
                    arguments += ["--"] + programArguments.map { $0.escapedShellArgument() }
                }
            }
            tasks.append(task(String(localized: "Run \(target.title)"), .run, arguments, environment: environment))
        }
        return tasks
    }

    // MARK: - CMake

    private static func cmakeTasks(_ cmake: CMakeInputs, inventory: ProjectInventory) -> [GeneratedTask] {
        let group = String(localized: "C++ · \(cmake.projectName)")
        var ctest = ["ctest", "--test-dir", cmake.buildDirectory.path.escapedShellArgument(), "--output-on-failure"]
        if let configuration = cmake.configuration {
            ctest += ["-C", configuration.escapedShellArgument()]
        }
        return [
            GeneratedTask(
                name: String(localized: "Build \(cmake.projectName) (CMake)"),
                command: "",
                workingDirectory: ".",
                info: GeneratedTaskInfo(
                    action: .cmakeBuild,
                    toolchain: .cmake,
                    role: .build,
                    group: group,
                    componentPath: ".",
                    outputParser: nil
                )
            ),
            GeneratedTask(
                name: String(localized: "Test \(cmake.projectName) (CTest)"),
                command: ctest.joined(separator: " "),
                workingDirectory: ".",
                info: GeneratedTaskInfo(
                    action: .shell,
                    toolchain: .cmake,
                    role: .test,
                    group: group,
                    componentPath: ".",
                    outputParser: .compiler
                )
            )
        ]
    }
}
