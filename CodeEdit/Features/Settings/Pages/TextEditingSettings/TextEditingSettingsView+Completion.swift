//
//  TextEditingSettingsView+Completion.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import SwiftUI

extension TextEditingSettingsView {
    /// The toggles that control what accepting a completion does.
    @ViewBuilder var completionBehaviorSettings: some View {
        Toggle(isOn: $textEditing.completion.applyAdditionalEdits) {
            Text("Apply Additional Completion Edits")
            Text("Lets the language server add related edits, such as an automatic #include, when you accept an item.")
        }
        Toggle(isOn: $textEditing.completion.insertParenthesesForFunctions) {
            Text("Insert Parentheses for Functions")
            Text("Adds () after an accepted function and shows its parameter hints.")
        }
        Toggle(isOn: $textEditing.completion.commitCharactersEnabled) {
            Text("Accept Completions with Commit Characters")
            Text("Typing ( . ; , or similar after a word accepts the highlighted item and keeps the character.")
        }
    }
}
