//
//  DebugNavigatorToolbarBottom.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import SwiftUI

/// Compact debug-session controls for the bottom of the Debug navigator: continue, pause,
/// step over/into/out, and stop. Mirrors the symbols and actions of ``DebugToolbarView``
/// without its (too wide) target picker.
struct DebugNavigatorToolbarBottom: View {
    @ObservedObject private var debugService: DebugService = .shared

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    Task { await debugService.resume() }
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState != .paused)
                .help("Continue")

                Button {
                    Task { await debugService.pause() }
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState != .running)
                .help("Pause")

                Button {
                    Task { await debugService.stepOver() }
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState != .paused)
                .help("Step Over")

                Button {
                    Task { await debugService.stepInto() }
                } label: {
                    Image(systemName: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState != .paused)
                .help("Step Into")

                Button {
                    Task { await debugService.stepOut() }
                } label: {
                    Image(systemName: "arrow.up.to.line")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState != .paused)
                .help("Step Out")

                Button {
                    Task { await debugService.stopDebugging() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .disabled(debugService.sessionState == .inactive)
                .help("Stop Debugging")

                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }
}
