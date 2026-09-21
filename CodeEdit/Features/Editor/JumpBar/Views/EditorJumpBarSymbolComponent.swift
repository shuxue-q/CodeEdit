//
//  EditorJumpBarSymbolComponent.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI
import LanguageServerProtocol
import CodeEditSourceEditor

/// Last jump-bar crumb: the symbol enclosing the cursor, or "No Selection".
struct EditorJumpBarSymbolComponent: View {
    @ObservedObject var model: EditorJumpBarSymbolModel
    @ObservedObject var editorInstance: EditorInstance

    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    var body: some View {
        Menu {
            if model.symbols.isEmpty {
                Button("No Selection") {}
                    .disabled(true)
            } else {
                ForEach(model.symbols) { symbol in
                    Button {
                        select(symbol)
                    } label: {
                        HStack {
                            Image(systemName: iconName(for: symbol.kind))
                            Text(menuTitle(for: symbol))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .scaleEffect(x: 1.30, y: 1.0, anchor: .center)
                Text(model.enclosingSymbol?.name ?? "No Selection")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(model.symbols.isEmpty)
        .help("Current Symbol")
        .onAppear {
            model.cursorMoved(editorInstance.cursorPositions.first)
        }
        .onChange(of: editorInstance.cursorPositions) { _, newValue in
            model.cursorMoved(newValue.first)
        }
    }

    private var labelColor: SwiftUI.Color {
        if activeState == .inactive {
            return SwiftUI.Color(nsColor: .tertiaryLabelColor)
        }
        return isActiveEditor ? .primary : .secondary
    }

    private func menuTitle(for symbol: JumpBarSymbol) -> String {
        String(repeating: "  ", count: symbol.depth) + symbol.name
    }

    private func select(_ symbol: JumpBarSymbol) {
        editorInstance.cursorPositions = [
            CursorPosition(line: symbol.line, column: symbol.column)
        ]
        model.cursorMoved(editorInstance.cursorPositions.first)
    }

    private func iconName(for kind: SymbolKind) -> String {
        switch kind {
        case .function, .method, .constructor:
            return "f.square"
        case .class, .interface:
            return "c.square"
        case .struct:
            return "s.square"
        case .enum:
            return "e.square"
        case .variable, .property, .field:
            return "v.square"
        case .constant:
            return "k.square"
        case .namespace, .module, .package:
            return "shippingbox"
        default:
            return "curlybraces"
        }
    }
}
