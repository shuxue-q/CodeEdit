//
//  JumpToDefinitionDelegate.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/23/25.
//

import Foundation

/// A delegate that provides "Jump to Definition" locations for a source editor.
///
/// Both requirements are called from the main actor by ``JumpToDefinitionModel``.
@MainActor
public protocol JumpToDefinitionDelegate: AnyObject {
    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]?
    func openLink(link: JumpToDefinitionLink)
}
