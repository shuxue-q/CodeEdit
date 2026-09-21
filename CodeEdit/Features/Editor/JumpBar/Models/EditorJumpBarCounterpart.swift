//
//  EditorJumpBarCounterpart.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import Foundation

/// Header/source counterpart lookup used by the jump bar Related Items menu.
enum EditorJumpBarCounterpart {
    static let headerExtensions: Set<String> = ["h", "hh", "hpp", "hxx", "h++"]
    static let sourceExtensions: Set<String> = ["c", "cc", "cpp", "cxx", "c++", "m", "mm"]

    /// Extensions that pair with `ext` as a counterpart.
    /// - Parameter ext: A path extension, with or without a leading dot.
    /// - Returns: The opposite set of C-family extensions, or empty when `ext` is unpaired.
    static func counterpartExtensions(for ext: String) -> Set<String> {
        let lower = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if headerExtensions.contains(lower) {
            return sourceExtensions
        }
        if sourceExtensions.contains(lower) {
            return headerExtensions
        }
        return []
    }

    /// Existing counterpart files that share `url`'s basename in the same directory.
    /// - Parameters:
    ///   - url: The file whose counterparts should be found.
    ///   - fileManager: File manager used to test existence.
    /// - Returns: Counterpart URLs that currently exist on disk.
    static func counterpartURLs(
        for url: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let targets = counterpartExtensions(for: url.pathExtension)
        guard !targets.isEmpty else { return [] }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        return targets.compactMap { candidateExt in
            let candidate = directory
                .appendingPathComponent(base)
                .appendingPathExtension(candidateExt)
            return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }
}
