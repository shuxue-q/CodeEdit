//
//  UtilityAreaTab.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 02/06/2023.
//

import SwiftUI

enum UtilityAreaTab: WorkspacePanelTab, CaseIterable {
    var id: Self { self }

    case terminal
    case debugConsole
    case debugger
    case output
    case problems

    var title: String {
        switch self {
        case .terminal:
            return String(localized: "Terminal")
        case .debugConsole:
            return String(localized: "Debug Console")
        case .debugger:
            return String(localized: "Debugger")
        case .output:
            return String(localized: "Output")
        case .problems:
            return String(localized: "Problems")
        }
    }

    var systemImage: String {
        switch self {
        case .terminal:
            return "terminal"
        case .debugConsole:
            return "ladybug"
        case .debugger:
            return "ant"
        case .output:
            return "list.bullet.indent"
        case .problems:
            return "checklist"
        }
    }

    var body: some View {
        switch self {
        case .terminal:
            UtilityAreaTerminalView()
        case .debugConsole:
            UtilityAreaDebugView()
        case .debugger:
            UtilityAreaDebuggerView()
        case .output:
            UtilityAreaOutputView()
        case .problems:
            UtilityAreaProblemsView()
        }
    }
}
