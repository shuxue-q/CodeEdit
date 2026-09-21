//
//  SourceEditorContextMenuDelegate.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit

/// A delegate protocol for handling context menu actions in the source editor.
public protocol SourceEditorContextMenuDelegate: AnyObject {
    /// Request to create a code snippet with the specified text and line number.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func createCodeSnippet(text: String, line: Int) -> Bool

    /// Request to show coding tools.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func showCodingTools() -> Bool

    /// Request to rename symbol at the current position.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorRename() -> Bool

    /// Request to extract selection to a function.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorExtractFunction() -> Bool

    /// Request to extract selection to a variable.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorExtractVariable() -> Bool

    /// Request to add missing switch cases.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorAddMissingSwitchCases() -> Bool

    /// Request to generate memberwise initializer.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorGenerateMemberwiseInit() -> Bool

    /// Request to format the document.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func refactorFormatDocument() -> Bool

    /// Request to find in workspace.
    func findInWorkspace(query: String?)

    /// Request to find selected text in workspace.
    func findSelectedTextInWorkspace()

    /// Request to find selected symbol in workspace.
    func findSelectedSymbolInWorkspace()

    /// Request to find call hierarchy.
    func findCallHierarchy()

    /// Request to jump to the type definition.
    func jumpToTypeDefinition()

    /// Request to reveal the file in the project navigator.
    func revealInProjectNavigator()

    /// Request to jump to the next counterpart.
    func jumpToNextCounterpart()

    /// Request to jump to the previous counterpart.
    func jumpToPreviousCounterpart()

    /// Request to show the previous editor tab.
    func showPreviousTab()

    /// Request to show the next editor tab.
    func showNextTab()

    /// Request to go back in navigation history.
    func navigateGoBack()

    /// Request to go forward in navigation history.
    func navigateGoForward()

    /// Request to show the last change (git blame) for a line.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func showLastChangeForLine(line: Int, rect: NSRect) -> Bool

    /// Request to bookmark a specific line.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func bookmarkLine(line: Int) -> Bool

    /// Request to bookmark the current file.
    /// Returns true if handled by delegate, false to fall back to the default editor implementation.
    func bookmarkFile() -> Bool
}

// Default empty implementations so adopters only need to implement what they need.
public extension SourceEditorContextMenuDelegate {
    /// Default implementation for createCodeSnippet.
    func createCodeSnippet(text: String, line: Int) -> Bool { false }
    /// Default implementation for showCodingTools.
    func showCodingTools() -> Bool { false }
    /// Default implementation for refactorRename.
    func refactorRename() -> Bool { false }
    /// Default implementation for refactorExtractFunction.
    func refactorExtractFunction() -> Bool { false }
    /// Default implementation for refactorExtractVariable.
    func refactorExtractVariable() -> Bool { false }
    /// Default implementation for refactorAddMissingSwitchCases.
    func refactorAddMissingSwitchCases() -> Bool { false }
    /// Default implementation for refactorGenerateMemberwiseInit.
    func refactorGenerateMemberwiseInit() -> Bool { false }
    /// Default implementation for refactorFormatDocument.
    func refactorFormatDocument() -> Bool { false }
    /// Default implementation for findInWorkspace.
    func findInWorkspace(query: String?) {}
    /// Default implementation for findSelectedTextInWorkspace.
    func findSelectedTextInWorkspace() {}
    /// Default implementation for findSelectedSymbolInWorkspace.
    func findSelectedSymbolInWorkspace() {}
    /// Default implementation for findCallHierarchy.
    func findCallHierarchy() {}
    /// Default implementation for jumpToTypeDefinition.
    func jumpToTypeDefinition() {}
    /// Default implementation for revealInProjectNavigator.
    func revealInProjectNavigator() {}
    /// Default implementation for jumpToNextCounterpart.
    func jumpToNextCounterpart() {}
    /// Default implementation for jumpToPreviousCounterpart.
    func jumpToPreviousCounterpart() {}
    /// Default implementation for showPreviousTab.
    func showPreviousTab() {}
    /// Default implementation for showNextTab.
    func showNextTab() {}
    /// Default implementation for navigateGoBack.
    func navigateGoBack() {}
    /// Default implementation for navigateGoForward.
    func navigateGoForward() {}
    /// Default implementation for showLastChangeForLine.
    func showLastChangeForLine(line: Int, rect: NSRect) -> Bool { false }
    /// Default implementation for bookmarkLine.
    func bookmarkLine(line: Int) -> Bool { false }
    /// Default implementation for bookmarkFile.
    func bookmarkFile() -> Bool { false }
}
