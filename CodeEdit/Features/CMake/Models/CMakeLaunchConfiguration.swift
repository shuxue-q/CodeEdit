//
//  CMakeLaunchConfiguration.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// Everything the debugger needs to launch the project's run target.
struct CMakeLaunchConfiguration: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    /// Variables added to the debuggee's environment.
    let environment: [String: String]
}

extension CMakeProjectSettings.Run {
    /// Whether a run target has been chosen at all. An empty custom path counts as unset.
    var hasExecutable: Bool {
        customPath != nil || (customExecutable == nil && targetName != nil)
    }

    /// The custom executable path, when one has been entered.
    private var customPath: String? {
        guard let path = customExecutable?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        return path
    }

    /// The executable these settings launch: the custom path, or the built artifact of the
    /// selected target. `nil` when nothing is chosen or the target's location is unknown.
    func executable(sourceDirectory: URL, targets: [CMakeExecutableTarget]) -> URL? {
        if customExecutable != nil {
            return customPath.map { CMakeConfigureOptions.resolve($0, against: sourceDirectory) }
        }
        guard let targetName else { return nil }
        return targets.first { $0.name == targetName }?.artifact
    }

    /// Resolves the launch configuration, or returns `nil` when no executable can be determined.
    func launchConfiguration(
        sourceDirectory: URL,
        targets: [CMakeExecutableTarget]
    ) -> CMakeLaunchConfiguration? {
        guard let executable = executable(sourceDirectory: sourceDirectory, targets: targets) else { return nil }
        var variables: [String: String] = [:]
        for variable in environment where variable.isEnabled {
            let name = variable.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { variables[name] = variable.value }
        }
        return CMakeLaunchConfiguration(
            executable: executable,
            arguments: CommandLineArguments.split(arguments),
            workingDirectory: workingDirectory.map {
                CMakeConfigureOptions.resolve($0, against: sourceDirectory)
            } ?? sourceDirectory.standardizedFileURL,
            environment: variables
        )
    }
}
