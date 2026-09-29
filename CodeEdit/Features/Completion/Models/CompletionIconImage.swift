//
//  CompletionIconImage.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import SwiftUI

/// Builds images (16pt vectors) from the `CompletionIcons` asset catalog folder.
enum CompletionIconImage {
    /// An icon rendered as a template, so `foregroundStyle` tints it.
    static func template(_ name: String) -> Image {
        Image(name).renderingMode(.template)
    }

    /// An icon drawn with its original asset colors; `foregroundStyle` has no effect on it.
    static func original(_ name: String) -> Image {
        Image(name).renderingMode(.original)
    }
}
