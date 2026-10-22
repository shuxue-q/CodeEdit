//
//  TextEditingSettings+Commands.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

extension SettingsData.TextEditingSettings {
    /// Adds toggle-able preferences to the command palette via shared `CommandManager`
    func populateCommands() { // swiftlint:disable:this function_body_length
        let mgr = CommandManager.shared

        mgr.addCommand(
            name: "Toggle Type-Over Completion",
            title: String(localized: "Toggle Type-Over Completion"),
            id: "prefs.text_editing.type_over_completion",
            command: {
                Settings[\.textEditing].enableTypeOverCompletion.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Autocomplete Braces",
            title: String(localized: "Toggle Autocomplete Braces"),
            id: "prefs.text_editing.autocomplete_braces",
            command: {
                Settings[\.textEditing].autocompleteBraces.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Inline Completion Info",
            title: String(localized: "Toggle Inline Completion Info"),
            id: "prefs.text_editing.inline_completion_info",
            command: {
                Settings[\.textEditing].showInlineCompletionInfo.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Word Wrap",
            title: String(localized: "Toggle Word Wrap"),
            id: "prefs.text_editing.wrap_lines_to_editor_width",
            command: {
                Settings[\.textEditing].wrapLinesToEditorWidth.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Minimap",
            title: String(localized: "Toggle Minimap"),
            id: "prefs.text_editing.toggle_minimap"
        ) {
            Settings[\.textEditing].showMinimap.toggle()
        }

        mgr.addCommand(
            name: "Toggle Gutter",
            title: String(localized: "Toggle Gutter"),
            id: "prefs.text_editing.toggle_gutter"
        ) {
            Settings[\.textEditing].showGutter.toggle()
        }

        mgr.addCommand(
            name: "Toggle Folding Ribbon",
            title: String(localized: "Toggle Folding Ribbon"),
            id: "prefs.text_editing.toggle_folding_ribbon"
        ) {
            Settings[\.textEditing].showFoldingRibbon.toggle()
        }
    }
}
