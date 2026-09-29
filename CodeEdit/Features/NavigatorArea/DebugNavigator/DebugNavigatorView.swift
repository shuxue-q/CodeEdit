//
//  DebugNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import SwiftUI

/// The Debug navigator: a slim session-status header above the threads and call stack
/// of the active debug session. Shows an empty state when no session is running.
struct DebugNavigatorView: View {
    @ObservedObject private var debugService: DebugService = .shared

    var body: some View {
        Group {
            if debugService.sessionState == .inactive {
                CEContentUnavailableView(
                    "Not Debugging",
                    description: "Start a debug session to inspect threads and the call stack."
                )
            } else {
                VStack(spacing: 0) {
                    sessionHeader
                    Divider()
                    DebugCallStackView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A compact status row: state icon, state label, and — when paused — the stopped location.
    private var sessionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateColor)
                .imageScale(.medium)

            Text(stateLabel)
                .font(.system(size: 12, weight: .semibold))

            if let stoppedLocation = debugService.stoppedLocation,
               debugService.sessionState == .paused {
                Text(locationLabel(stoppedLocation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var stateIcon: String {
        switch debugService.sessionState {
        case .inactive: return "circle.dotted"
        case .launching: return "circle.dotted"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        }
    }

    private var stateColor: Color {
        switch debugService.sessionState {
        case .inactive, .launching: return .secondary
        case .running: return .green
        case .paused: return .orange
        }
    }

    private var stateLabel: String {
        switch debugService.sessionState {
        case .inactive: return "Not Debugging"
        case .launching: return "Launching…"
        case .running: return "Running"
        case .paused: return "Paused"
        }
    }

    /// A short `file:line` label for the stopped location.
    private func locationLabel(_ location: (filePath: String, line: Int)) -> String {
        "\(URL(fileURLWithPath: location.filePath).lastPathComponent):\(location.line)"
    }
}
