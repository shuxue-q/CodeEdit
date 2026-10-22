//
//  FontWeightPicker.swift
//  CodeEdit
//
//  Created by Austin Condiff on 6/13/24.
//

import SwiftUI

struct FontWeightPicker: View {
    @Binding var selection: NSFont.Weight
    var label: String?

    let fontWeights: [NSFont.Weight] = [
        .ultraLight,
        .thin,
        .light,
        .regular,
        .medium,
        .semibold,
        .bold,
        .heavy,
        .black
    ]

    var weightNames: [NSFont.Weight: String] = [
        .ultraLight: String(localized: "Ultra Light"),
        .thin: String(localized: "Thin"),
        .light: String(localized: "Light"),
        .regular: String(localized: "Regular"),
        .medium: String(localized: "Medium"),
        .semibold: String(localized: "Semi Bold"),
        .bold: String(localized: "Bold"),
        .heavy: String(localized: "Heavy"),
        .black: String(localized: "Black")
    ]

    var body: some View {
        Picker(label ?? String(localized: "Font Weight"), selection: $selection) {
            ForEach(fontWeights, id: \.self) { weight in
                Text(weightNames[weight] ?? String(localized: "Unknown"))
                    .tag(weight)
            }
        }
    }
}
