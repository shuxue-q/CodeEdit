//
//  DebugVariableNode.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

/// A node in the debugger's variables tree.
///
/// A node either represents a scope (root level) or a variable. Nodes whose
/// `variablesReference` is greater than zero have children in the debuggee; those children
/// are loaded lazily — `children` stays `nil` until the node is first expanded.
@MainActor
final class DebugVariableNode: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let type: String?
    let variablesReference: Int

    /// The loaded child variables, or `nil` when children exist but have not been loaded yet.
    @Published var children: [DebugVariableNode]?

    init(name: String, value: String, type: String?, variablesReference: Int) {
        self.name = name
        self.value = value
        self.type = type
        self.variablesReference = variablesReference
    }

    convenience init(scope: DAPScope) {
        self.init(name: scope.name, value: "", type: nil, variablesReference: scope.variablesReference)
    }

    convenience init(variable: DAPVariable) {
        self.init(
            name: variable.name,
            value: variable.value,
            type: variable.type,
            variablesReference: variable.variablesReference
        )
    }
}
