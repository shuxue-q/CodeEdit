//
//  BreakpointCoordinator.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Combine
import Foundation
import CodeEditSourceEditor

/// Bridges the editor gutter and the debugging state for a single file.
///
/// The coordinator keeps the gutter's breakpoint markers in sync with ``BreakpointStore``
/// and highlights the current debug execution line when ``DebugService`` posts a
/// `.debugCurrentLineChanged` notification for this file. Gutter clicks toggle breakpoints
/// and, while a debug session is active, push the updated set to the debug adapter.
@MainActor
final class BreakpointCoordinator {
    /// The absolute path of the file this coordinator is attached to, if known.
    private let filePath: String?

    private weak var controller: TextViewController?
    private var cancellables = Set<AnyCancellable>()

    init(fileURL: URL?) {
        self.filePath = fileURL?.path
    }

    // MARK: - TextViewCoordinator

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller

        guard let filePath else { return }

        // Note: `controller.gutterView` does not exist yet here — it is created in `loadView()`,
        // which runs after `prepareCoordinator(controller:)`. The initial breakpoint markers are
        // applied in `controllerDidAppear(controller:)` instead.

        BreakpointStore.shared.$breakpoints
            .receive(on: DispatchQueue.main)
            .sink { [weak controller] breakpoints in
                guard let gutterView = controller?.gutterView else { return }
                gutterView.breakpointLines = breakpoints[filePath] ?? []
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .debugCurrentLineChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak controller] notification in
                guard let userInfo = notification.userInfo,
                      let postedPath = userInfo["filePath"] as? String,
                      DebugFilePath.sameFile(postedPath, filePath),
                      let gutterView = controller?.gutterView else {
                    return
                }
                // The posted line is already 0-based; a missing value clears the marker.
                gutterView.currentDebugLine = userInfo["line"] as? Int
            }
            .store(in: &cancellables)
    }

    func controllerDidAppear(controller: TextViewController) {
        // The gutter view exists by the time the view appears, so apply the stored breakpoints.
        // A stop that was posted before this editor existed never reaches the subscription above.
        guard let filePath, let gutterView = controller.gutterView else { return }
        gutterView.breakpointLines = BreakpointStore.shared.lines(for: filePath)
        guard let stopped = DebugService.shared.stoppedLocation,
              DebugFilePath.sameFile(stopped.filePath, filePath) else {
            return
        }
        gutterView.currentDebugLine = max(stopped.line, 1) - 1
    }

    func textViewDidClickGutter(controller: TextViewController, atLine line: Int) {
        guard let filePath else { return }

        BreakpointStore.shared.toggle(filePath: filePath, line: line)

        if DebugService.shared.sessionState != .inactive {
            Task {
                await DebugService.shared.syncBreakpoints(filePath: filePath)
            }
        }
    }

    func destroy() {
        cancellables.removeAll()
        controller = nil
    }
}

// The conformance is isolated to the main actor, matching this class's isolation.
extension BreakpointCoordinator: @MainActor TextViewCoordinator { }

/// Compares debugger paths that may differ by symlink (`/tmp` and `/private/tmp`).
enum DebugFilePath {
    static func sameFile(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).resolvingSymlinksInPath().standardizedFileURL
            == URL(fileURLWithPath: rhs).resolvingSymlinksInPath().standardizedFileURL
    }
}
