//
//  LSPHoverDeclarationFormatter.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import Foundation

/// Formats and breaks declarations cleanly for hover display.
enum LSPHoverDeclarationFormatter {
    /// Threshold length over which parameter lists are wrapped to multiple lines.
    private static let parameterWrapThreshold: Int = 45

    /// Formats a declaration string with clean line breaking and indentation.
    static func format(code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Clean common LSP prefixes like "(function) ", "(variable) " from Pyright/VSCode
        let cleaned = cleanLSPPrefix(trimmed)

        // Find the opening parenthesis belonging to the actual parameter list
        guard let openParenIdx = findParameterOpenParen(in: cleaned) else {
            if cleaned.contains("\n") {
                return normalizeMultiLine(cleaned)
            }
            return formatNonFunctionDeclaration(cleaned)
        }

        let chars = Array(cleaned)
        let openOffset = cleaned.distance(from: cleaned.startIndex, to: openParenIdx)

        guard let scanResult = scanParameters(chars: chars, startIndex: openOffset + 1) else {
            return cleaned.contains("\n") ? normalizeMultiLine(cleaned) : cleaned
        }

        let closeOffset = scanResult.closeIdx
        let commas = scanResult.commas
        let totalLength = cleaned.count
        let paramSpan = closeOffset - openOffset
        let suffixRaw = String(chars[closeOffset..<chars.count]).trimmingCharacters(in: .whitespaces)

        let shouldWrap = totalLength > parameterWrapThreshold
            && (!commas.isEmpty || paramSpan > 25 || suffixRaw.count > 30)

        guard shouldWrap else {
            return cleaned.contains("\n") ? normalizeMultiLine(cleaned) : cleaned
        }

        let prefix = String(chars[0...openOffset]).trimmingCharacters(in: .whitespacesAndNewlines)
        var suffix = suffixRaw

        // Cleanly format `where` clause if present and long
        if let whereRange = suffix.range(of: " where ") {
            let beforeWhere = suffix[..<whereRange.lowerBound]
            let afterWhere = suffix[whereRange.upperBound...]
            if afterWhere.count > 30 || afterWhere.contains(",") {
                suffix = "\(beforeWhere)\nwhere\n    \(afterWhere.replacingOccurrences(of: ", ", with: ",\n    "))"
            }
        } else if let arrowRange = suffix.range(of: " -> "), suffix.count > 35 {
            let beforeArrow = suffix[..<arrowRange.lowerBound]
            let afterArrow = suffix[arrowRange.upperBound...]
            suffix = "\(beforeArrow)\n    -> \(afterArrow)"
        }

        let formatted = extractParams(chars: chars, startIdx: openOffset + 1, closeIdx: closeOffset, commas: commas)

        guard !formatted.isEmpty else {
            return cleaned
        }

        return "\(prefix)\n\(formatted.joined(separator: ",\n"))\n\(suffix)"
    }

    /// Strips language server hover prefixes such as `(function) ` or `(method) `.
    private static func cleanLSPPrefix(_ code: String) -> String {
        let prefixes = [
            "(function) ", "(method) ", "(class) ", "(variable) ", "(property) ",
            "(type) ", "(constant) ", "(alias) ", "(interface) ", "(enum) "
        ]
        for prefix in prefixes where code.hasPrefix(prefix) {
            return String(code.dropFirst(prefix.count))
        }
        return code
    }

    /// Locates the parameter list's opening parenthesis `(`, skipping any leading attributes or receivers.
    private static func findParameterOpenParen(in code: String) -> String.Index? {
        let chars = Array(code)
        var idx = 0

        while idx < chars.count {
            if skipAttributeOrReceiver(chars: chars, index: &idx) {
                continue
            }
            if chars[idx] == "<" {
                skipMatchingDelimiter(chars: chars, index: &idx, open: "<", close: ">")
                continue
            }
            if chars[idx] == "=" && !code.contains("operator") {
                return nil
            }
            if chars[idx] == "(" {
                return code.index(code.startIndex, offsetBy: idx)
            }
            idx += 1
        }

        return nil
    }

    /// Normalizes existing multi-line code indentation.
    private static func normalizeMultiLine(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return code }

        var result: [String] = [firstLine.trimmingCharacters(in: .whitespaces)]
        for line in lines.dropFirst() {
            let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
            if lineTrimmed.isEmpty {
                result.append("")
            } else if lineTrimmed.hasPrefix(")") || lineTrimmed.hasPrefix("}") {
                result.append(lineTrimmed)
            } else if lineTrimmed.hasPrefix("where") {
                result.append(lineTrimmed)
            } else {
                result.append("    " + lineTrimmed)
            }
        }
        return result.joined(separator: "\n")
    }

    /// Formats non-function declarations such as variables, constants, typealiases, and concepts.
    private static func formatNonFunctionDeclaration(_ code: String) -> String {
        guard code.count > parameterWrapThreshold else { return code }

        // If declaration contains an assignment '='
        if let eqRange = code.range(of: " = ") {
            let left = String(code[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(code[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if code.count > parameterWrapThreshold {
                if findParameterOpenParen(in: right) != nil {
                    let formattedRight = format(code: right)
                    return "\(left)\n    = \(formattedRight.replacingOccurrences(of: "\n", with: "\n    "))"
                }
                return "\(left)\n    = \(right)"
            }
        }

        // If declaration contains ': ' with a long type annotation or identifier
        if let colonRange = code.range(of: ": ") {
            let left = String(code[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(code[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if code.count > parameterWrapThreshold && !left.contains("\n") {
                return "\(left)\n    : \(right)"
            }
        }

        return code
    }
}
