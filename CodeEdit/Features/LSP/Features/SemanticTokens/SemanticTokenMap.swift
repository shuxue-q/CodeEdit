//
//  SemanticTokenMap.swift
//  CodeEdit
//
//  Created by Khan Winter on 11/10/24.
//

import LanguageClient
import LanguageServerProtocol
import CodeEditSourceEditor
import CodeEditTextView

// swiftlint:disable line_length
/// Creates a mapping from a language server's semantic token options to a format readable by CodeEdit.
/// Provides a convenience method for mapping tokens received from the server to highlight ranges suitable for
/// highlighting in the editor.
///
/// Use this type to handle the initially received semantic highlight capabilities structures. This type will figure
/// out how to read it into a format it can use.
///
/// After initialization, the map is static until the server is reinitialized. Consequently, this type is `Sendable`
/// and immutable after initialization.
///
/// This type is not coupled to any text system via the use of the ``SemanticTokenMapRangeProvider``. When decoding to
/// highlight ranges, provide a type that can provide ranges for highlighting.
///
/// [LSP Spec](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokensLegend)
struct SemanticTokenMap: Sendable { // swiftlint:enable line_length
    private let tokenTypeMap: [CaptureName?]
    private let modifierMap: [CaptureModifier?]

    init(semanticCapability: TwoTypeOption<SemanticTokensOptions, SemanticTokensRegistrationOptions>) {
        let legend: SemanticTokensLegend
        switch semanticCapability {
        case .optionA(let tokensOptions):
            legend = tokensOptions.legend
        case .optionB(let tokensRegistrationOptions):
            legend = tokensRegistrationOptions.legend
        }

        tokenTypeMap = legend.tokenTypes.map { Self.captureName(forTokenType: $0) }
        modifierMap = legend.tokenModifiers.map { CaptureModifier.fromString($0) }
    }

    /// Server token types named differently from the capture that styles the same role.
    ///
    /// Dart's `annotation` (`@override`) is what grammars capture as `attribute`.
    private static let tokenTypeAliases: [String: CaptureName] = [
        "annotation": .typeAlternate
    ]

    /// The capture for a token type in a server's legend, or `nil` when the type has no matching capture
    /// (Dart's `source`, code inside documentation comments): the grammar's highlight stays in place there.
    /// - Parameter tokenType: A token type name from the legend.
    /// - Returns: The capture to style tokens of that type with.
    static func captureName(forTokenType tokenType: String) -> CaptureName? {
        tokenTypeAliases[tokenType] ?? CaptureName.fromString(tokenType)
    }

    /// Decodes the compressed semantic token data into a `HighlightRange` type for use in an editor.
    /// This is marked main actor to prevent runtime errors, due to the use of the actor-isolated `rangeProvider`.
    /// - Parameters:
    ///   - tokens: Encoded semantic tokens type from a language server.
    ///   - rangeProvider: The provider to use to translate token ranges to text view ranges.
    /// - Returns: An array of decoded highlight ranges.
    @MainActor
    func decode(tokens: SemanticTokens, using rangeProvider: SemanticTokenMapRangeProvider) -> [HighlightRange] {
        return decode(tokens: tokens.decode(), using: rangeProvider)
    }

    /// Decodes the compressed semantic token data into a `HighlightRange` type for use in an editor.
    /// This is marked main actor to prevent runtime errors, due to the use of the actor-isolated `rangeProvider`.
    /// - Parameters:
    ///   - tokens: Decoded semantic tokens from a language server.
    ///   - rangeProvider: The provider to use to translate token ranges to text view ranges.
    /// - Returns: An array of decoded highlight ranges.
    @MainActor
    func decode(tokens: [SemanticToken], using rangeProvider: SemanticTokenMapRangeProvider) -> [HighlightRange] {
        tokens.compactMap { token in
            guard let range = rangeProvider.nsRangeFrom(line: token.line, char: token.char, length: token.length) else {
                return nil
            }

            // Only modifiers are bit packed, capture types are given as a simple index into the ``tokenTypeMap``
            let modifiers = decodeModifier(token.modifiers)

            let type = Int(token.type)
            let rawCapture = tokenTypeMap.indices.contains(type) ? tokenTypeMap[type] : nil

            // Variables are narrowed by the scope and write modifiers the server attached: class-scope variables
            // are members, file/global-scope ones are globals, and servers that flag written variables with the
            // `modification` modifier expose the assignment target role the same way the tree-sitter
            // `variable.assigned` capture does.
            let capture = rawCapture?.refined(by: modifiers)

            return HighlightRange(
                range: range,
                capture: capture,
                modifiers: modifiers
            )
        }
    }

    /// Decodes a raw modifier value into a set of capture modifiers.
    /// - Parameter raw: The raw modifier integer to decode.
    /// - Returns: A set of modifiers for highlighting.
    func decodeModifier(_ raw: UInt32) -> CaptureModifierSet {
        var modifiers: CaptureModifierSet = []
        var raw = raw
        while raw > 0 {
            let idx = raw.trailingZeroBitCount
            raw &= ~(1 << idx)
            // We don't use `[safe:]` because it creates a double optional here. If someone knows how to extend
            // a collection of optionals to make that return only a single optional this could be updated.
            guard let modifier = modifierMap.indices.contains(idx) ? modifierMap[idx] : nil else {
                continue
            }
            modifiers.insert(modifier)
        }
        return modifiers
    }
}
