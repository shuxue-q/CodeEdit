//
//  DebugCallStackView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import SwiftUI

/// The debugger's leading sidebar: the threads of the debugged process and the call stack
/// of the stopped thread. Selecting a frame drives the variables view and the editor's
/// current-debug-line highlight.
struct DebugCallStackView: View {
    @ObservedObject private var debugService: DebugService = .shared

    var body: some View {
        Group {
            if debugService.sessionState == .inactive {
                Text("Not debugging.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                callStackList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var callStackList: some View {
        List(selection: $debugService.selectedFrameID) {
            Section("Threads") {
                ForEach(debugService.threads, id: \.id) { thread in
                    Text(thread.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Section("Call Stack") {
                ForEach(debugService.stackFrames, id: \.id) { frame in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(frame.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let location = locationLabel(for: frame) {
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(Optional(frame.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// A short `file:line` label for a stack frame, when the adapter reported a source path.
    private func locationLabel(for frame: DAPStackFrame) -> String? {
        guard let path = frame.source?.path else { return nil }
        return "\(URL(fileURLWithPath: path).lastPathComponent):\(frame.line)"
    }
}
