//
//  ProjectTextFile.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation
import Observation

/// A small text file in the workspace, such as `.gitignore` or `.clang-format`, edited in the
/// project editor.
///
/// Unsaved edits are kept until ``save()`` or ``revert()``. ``checkForExternalChanges()`` picks
/// up changes made on disk: they replace the text when there are no unsaved edits, and otherwise
/// set ``changedOnDisk`` so the editor can offer to reload.
@MainActor
@Observable
final class ProjectTextFile: Identifiable {
    let url: URL
    /// The path shown to the user, relative to the workspace root.
    let displayPath: String

    var id: URL { url }

    /// The text being edited.
    var text: String = ""
    /// The text last read from or written to disk.
    private(set) var savedText: String = ""
    private(set) var exists = false
    private(set) var changedOnDisk = false
    private(set) var error: String?

    /// Called after a successful save, for example to reload a model that owns the file.
    @ObservationIgnored var didSave: (() -> Void)?

    @ObservationIgnored private var modificationDate: Date?

    var hasUnsavedChanges: Bool {
        text != savedText
    }

    init(url: URL, displayPath: String) {
        self.url = url
        self.displayPath = displayPath
        load()
    }

    /// Reads the file, discarding unsaved edits. A missing file reads as empty.
    func load() {
        changedOnDisk = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            exists = false
            modificationDate = nil
            savedText = ""
            text = ""
            error = nil
            return
        }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            exists = true
            modificationDate = Self.modificationDate(of: url)
            savedText = contents
            text = contents
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Writes the text atomically, creating missing parent folders.
    func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            exists = true
            savedText = text
            modificationDate = Self.modificationDate(of: url)
            changedOnDisk = false
            error = nil
            didSave?()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Discards unsaved edits and reloads the file from disk.
    func revert() {
        load()
    }

    /// Reloads the file if it changed on disk since it was last read or written.
    func checkForExternalChanges() {
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let date = fileExists ? Self.modificationDate(of: url) : nil
        guard fileExists != exists || date != modificationDate else { return }
        if hasUnsavedChanges {
            changedOnDisk = true
        } else {
            load()
        }
    }

    /// Reads the date from the file system each time; `URL.resourceValues` caches per URL value.
    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
