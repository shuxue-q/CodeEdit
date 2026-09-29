//
//  LSPSignatureHelpContent.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import Foundation
import LanguageServerProtocol

/// The part of a `textDocument/signatureHelp` response shown in the parameter-hint tooltip.
struct LSPSignatureHelpContent: Equatable {
    /// The full signature, for example `const Ep *begin(initializer_list<Ep> il)`.
    let label: String
    /// The active parameter's range in `label`, in UTF-16 offsets.
    let activeParameterRange: NSRange?
    /// The active signature's index among the overloads.
    let signatureIndex: Int
    /// The number of overloads.
    let signatureCount: Int
    /// Documentation for the active parameter, if the server sent any.
    let parameterDocumentation: String?

    /// Picks the active signature and parameter from `help`. `nil` when there is no signature to show.
    init?(help: SignatureHelp) {
        guard !help.signatures.isEmpty else { return nil }
        let index = min(max(help.activeSignature ?? 0, 0), help.signatures.count - 1)
        let signature = help.signatures[index]
        guard !signature.label.isEmpty else { return nil }

        label = signature.label
        signatureIndex = index
        signatureCount = help.signatures.count

        let parameters = signature.parameters ?? []
        let activeIndex = signature.activeParameter.map { Int($0) } ?? help.activeParameter ?? 0
        if parameters.indices.contains(activeIndex) {
            activeParameterRange = Self.parameterRanges(parameters.map(\.label), in: signature.label)[activeIndex]
            parameterDocumentation = parameters[activeIndex].documentation.flatMap(Self.text(from:))
        } else {
            activeParameterRange = nil
            parameterDocumentation = nil
        }
    }

    /// Resolves parameter labels to ranges in the signature label.
    ///
    /// Offset labels are used as given. String labels are searched for in order, starting after the
    /// opening parenthesis and after the previous parameter, so `(int, int)` gets two different ranges
    /// and a parameter spelled like the function name is not matched in the name.
    static func parameterRanges(
        _ parameterLabels: [TwoTypeOption<String, [UInt]>],
        in signatureLabel: String
    ) -> [NSRange?] {
        let signature = signatureLabel as NSString
        let open = signature.range(of: "(")
        var searchStart = open.location == NSNotFound ? 0 : open.location + 1
        return parameterLabels.map { label in
            switch label {
            case .optionA(let text):
                guard !text.isEmpty, searchStart <= signature.length else { return nil }
                let found = signature.range(
                    of: text,
                    range: NSRange(location: searchStart, length: signature.length - searchStart)
                )
                guard found.location != NSNotFound else { return nil }
                searchStart = found.location + found.length
                return found
            case .optionB(let offsets):
                guard offsets.count == 2 else { return nil }
                let start = Int(offsets[0])
                let end = Int(offsets[1])
                guard end > start, end <= signature.length else { return nil }
                searchStart = end
                return NSRange(location: start, length: end - start)
            }
        }
    }

    private static func text(from documentation: TwoTypeOption<String, MarkupContent>) -> String? {
        let value: String
        switch documentation {
        case .optionA(let string):
            value = string
        case .optionB(let markup):
            value = markup.value
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
