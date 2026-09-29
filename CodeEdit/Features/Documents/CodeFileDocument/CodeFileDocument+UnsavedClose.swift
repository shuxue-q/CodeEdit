//
//  CodeFileDocument+UnsavedClose.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/28/26.
//

import AppKit

extension CodeFileDocument {
    /// Asks whether to save or discard unsaved edits before the file is closed.
    ///
    /// A pending autosave is cancelled first, so the dialog decides whether the edits are written.
    /// - Parameters:
    ///   - window: Window that hosts the sheet. Falls back to the key or main window.
    ///   - completion: `true` when the file may close, `false` when the user cancels.
    func confirmUnsavedClose(in window: NSWindow?, completion: @escaping (Bool) -> Void) {
        guard isDocumentEdited else {
            completion(true)
            return
        }
        cancelScheduledAutosave()

        let alert = unsavedCloseAlert()
        let respond = unsavedCloseResponse(completion: completion)
        if let host = window ?? NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: host, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    private func unsavedCloseAlert() -> NSAlert {
        let fileName = fileURL?.lastPathComponent ?? "Untitled"
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(fileName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.buttons.last?.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    private func unsavedCloseResponse(
        completion: @escaping (Bool) -> Void
    ) -> (NSApplication.ModalResponse) -> Void {
        return { [weak self] response in
            guard let self else {
                completion(false)
                return
            }
            switch response {
            case .alertFirstButtonReturn:
                self.saveBeforeClose(completion: completion)
            case .alertSecondButtonReturn:
                self.updateChangeCount(.changeCleared)
                completion(true)
            default:
                self.scheduleAutosaving()
                completion(false)
            }
        }
    }

    private func saveBeforeClose(completion: @escaping (Bool) -> Void) {
        guard let fileURL, let fileType else {
            scheduleAutosaving()
            completion(false)
            return
        }
        save(to: fileURL, ofType: fileType, for: .saveOperation) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }
                if let error {
                    self.presentError(error)
                    self.scheduleAutosaving()
                    completion(false)
                    return
                }
                completion(true)
            }
        }
    }
}
