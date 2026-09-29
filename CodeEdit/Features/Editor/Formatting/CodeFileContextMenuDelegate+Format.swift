//
//  CodeFileContextMenuDelegate+Format.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/28/26.
//

import AppKit
import CodeEditSourceEditor

extension CodeFileContextMenuDelegate {
    func canFormatCode(fileURL: URL?) -> Bool {
        ClangFormatLanguage.supports(url: fileURL)
    }

    func formatCode(
        text: String,
        fileURL: URL?,
        cursorUTF8: Int?,
        lineRanges: [ClosedRange<Int>],
        completion: @escaping (FormatCodeResult) -> Void
    ) -> Bool {
        guard !isFormattingCode else { return true }
        guard ClangFormatLanguage.supports(url: fileURL) else {
            ClangFormatPresenter.showUnsupportedFile()
            completion(.failed)
            return true
        }
        isFormattingCode = true
        let request = ClangFormatRequest(
            source: text,
            style: Settings[\.textEditing].codeFormatStyle,
            fileURL: fileURL,
            cursorUTF8: cursorUTF8,
            lineRanges: lineRanges,
            executablePath: nil
        )
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = ClangFormatPresenter.outcome(for: request)
            // `self` from `[weak self]` is a mutable capture. Copy it before the main-actor hop.
            let delegate = self
            await MainActor.run {
                if case .failure(let error) = outcome {
                    ClangFormatPresenter.show(error)
                }
                delegate?.isFormattingCode = false
                completion(ClangFormatPresenter.result(outcome))
            }
        }
        return true
    }
}

/// Turns a clang-format result into an alert and a context-menu result.
enum ClangFormatPresenter {
    /// Runs the formatter. Safe to call off the main thread.
    static func outcome(for request: ClangFormatRequest) -> Result<ClangFormatOutput, ClangFormatError> {
        do {
            return .success(try ClangFormatRunner.format(request))
        } catch let error as ClangFormatError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// The value passed back to the editor.
    static func result(_ outcome: Result<ClangFormatOutput, ClangFormatError>) -> FormatCodeResult {
        switch outcome {
        case .success(let output):
            let cursor = output.cursorUTF8.map {
                ClangFormatRunner.utf16Offset(utf8Offset: $0, in: output.text)
            }
            return .formatted(text: output.text, cursor: cursor)
        case .failure:
            return .failed
        }
    }

    /// Shows why formatting did not change the file.
    static func show(_ error: ClangFormatError) {
        present(message: error.message)
    }

    /// Shown when Format Code is invoked for a language clang-format does not handle.
    static func showUnsupportedFile() {
        present(
            message: "Format Code supports C, C++, Objective-C, Java, JavaScript, " +
                "TypeScript, JSON, C#, and Protobuf files."
        )
    }

    private static func present(message: String) {
        let alert = NSAlert()
        alert.messageText = "Unable to Format Code"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
