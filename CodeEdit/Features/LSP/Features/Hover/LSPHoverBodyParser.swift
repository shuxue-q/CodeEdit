//
//  LSPHoverBodyParser.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import Foundation

/// Internal parser for processing hover body documentation lines (summary, parameters, returns, discussion).
final class LSPHoverBodyParser {
    enum Section {
        case summary
        case parameters
        case returns
        case `throws`
        case discussion
    }

    private var section: Section = .summary
    private var summaryLines: [String] = []
    private var discussionLines: [String] = []
    private var currentParam: LSPHoverSectionExtractor.ParsedParam?
    private var insideCodeBlock = false

    func parse(text: String, into doc: inout LSPHoverDocumentation) {
        for rawLine in text.components(separatedBy: "\n") {
            let line = insideCodeBlock ? rawLine : stripCommentPrefix(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track fenced code blocks in discussion to avoid misparsing code lines as headers/params
            if trimmed.hasPrefix("```") {
                insideCodeBlock.toggle()
                if section != .discussion {
                    flushParam(into: &doc)
                    section = .discussion
                }
                discussionLines.append(line)
                continue
            }

            if insideCodeBlock {
                discussionLines.append(line)
                continue
            }

            if LSPHoverParser.isDividerLine(trimmed) {
                flushParam(into: &doc)
                section = .discussion
                continue
            }

            if handleSectionHeaders(trimmed: trimmed, into: &doc) {
                continue
            }

            handleLine(line, trimmed: trimmed, into: &doc)
        }

        flushParam(into: &doc)
        finalize(into: &doc)
    }

    private func stripCommentPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("///") {
            let after = trimmed.dropFirst(3)
            return after.hasPrefix(" ") ? String(after.dropFirst()) : String(after)
        }
        if trimmed.hasPrefix("//!") {
            let after = trimmed.dropFirst(3)
            return after.hasPrefix(" ") ? String(after.dropFirst()) : String(after)
        }
        if trimmed.hasPrefix("* @") || trimmed.hasPrefix("* \\") || trimmed.hasPrefix("*-") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private func handleSectionHeaders(trimmed: String, into doc: inout LSPHoverDocumentation) -> Bool {
        if isDiscussionHeader(trimmed) {
            flushParam(into: &doc)
            section = .discussion
            return true
        }
        if LSPHoverSectionExtractor.isParametersHeader(trimmed) {
            flushParam(into: &doc)
            section = .parameters
            return true
        }
        if let ret = LSPHoverSectionExtractor.extractReturns(trimmed) {
            flushParam(into: &doc)
            section = .returns
            doc.returns = appendText(doc.returns, newPart: ret)
            return true
        }
        if let thr = LSPHoverSectionExtractor.extractThrows(trimmed) {
            flushParam(into: &doc)
            section = .throws
            doc.throwsDescription = appendText(doc.throwsDescription, newPart: thr)
            return true
        }
        if let callout = LSPHoverSectionExtractor.extractCallout(trimmed) {
            flushParam(into: &doc)
            doc.callouts.append(callout)
            return true
        }
        return false
    }

    private func isDiscussionHeader(_ trimmed: String) -> Bool {
        guard !trimmed.hasPrefix("#") else { return false }
        let clean = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "*-: \t")).lowercased()
        let headers: Set<String> = [
            "discussion", "remarks", "details", "overview", "notes", "example", "examples", "usage"
        ]
        return headers.contains(clean)
    }

    private func handleLine(_ line: String, trimmed: String, into doc: inout LSPHoverDocumentation) {
        if section == .returns {
            handleReturnsLine(line, trimmed: trimmed, into: &doc)
            return
        }
        if section == .throws {
            handleThrowsLine(line, trimmed: trimmed, into: &doc)
            return
        }

        let parsedParam = LSPHoverSectionExtractor.parseParameterLine(
            trimmed,
            inParametersSection: section == .parameters
        )
        if let param = parsedParam {
            flushParam(into: &doc)
            section = .parameters
            currentParam = param
            return
        }

        switch section {
        case .summary:
            handleSummaryLine(line, trimmed: trimmed)
        case .parameters:
            handleParameterLine(line, trimmed: trimmed, into: &doc)
        case .discussion:
            discussionLines.append(line)
        case .returns, .throws:
            break
        }
    }

    private func handleSummaryLine(_ line: String, trimmed: String) {
        if trimmed.hasPrefix("#") || Self.isDefinitionCode(trimmed) || isDiscussionHeader(trimmed) {
            section = .discussion
            discussionLines.append(line)
        } else if trimmed.isEmpty && !summaryLines.isEmpty {
            section = .discussion
        } else if !trimmed.isEmpty {
            summaryLines.append(line)
        }
    }

    private func handleParameterLine(_ line: String, trimmed: String, into doc: inout LSPHoverDocumentation) {
        if (line.hasPrefix("  ") || line.hasPrefix("\t")) && !trimmed.isEmpty {
            currentParam?.description += " " + trimmed
        } else if trimmed.isEmpty {
            flushParam(into: &doc)
        } else {
            flushParam(into: &doc)
            section = .discussion
            discussionLines.append(line)
        }
    }

    private func isNewSectionLine(_ trimmed: String) -> Bool {
        trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("-")
            || trimmed.hasPrefix("*") || trimmed.hasPrefix("@") || isDiscussionHeader(trimmed)
            || Self.isDefinitionCode(trimmed) || LSPHoverSectionExtractor.isParametersHeader(trimmed)
            || LSPHoverSectionExtractor.extractThrows(trimmed) != nil
            || LSPHoverSectionExtractor.extractReturns(trimmed) != nil
            || LSPHoverSectionExtractor.extractCallout(trimmed) != nil
    }

    private func handleReturnsLine(_ line: String, trimmed: String, into doc: inout LSPHoverDocumentation) {
        if !isNewSectionLine(trimmed) {
            doc.returns = appendText(doc.returns, newPart: trimmed)
        } else {
            section = .discussion
            if !trimmed.isEmpty {
                if handleSectionHeaders(trimmed: trimmed, into: &doc) {
                    return
                }
                discussionLines.append(line)
            }
        }
    }

    private func handleThrowsLine(_ line: String, trimmed: String, into doc: inout LSPHoverDocumentation) {
        if !isNewSectionLine(trimmed) {
            doc.throwsDescription = appendText(doc.throwsDescription, newPart: trimmed)
        } else {
            section = .discussion
            if !trimmed.isEmpty {
                if handleSectionHeaders(trimmed: trimmed, into: &doc) {
                    return
                }
                discussionLines.append(line)
            }
        }
    }

    private func flushParam(into doc: inout LSPHoverDocumentation) {
        guard let current = currentParam else { return }
        doc.parameters.append(LSPHoverParameter(
            name: current.name,
            type: current.type,
            description: current.description.trimmingCharacters(in: .whitespaces)
        ))
        currentParam = nil
    }

    private func appendText(_ existing: String?, newPart: String) -> String {
        guard let existing, !existing.isEmpty else { return newPart }
        return existing + " " + newPart
    }

    private func finalize(into doc: inout LSPHoverDocumentation) {
        let sumText = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        doc.summary = sumText.isEmpty ? nil : sumText

        let discText = discussionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        doc.discussion = discText.isEmpty ? nil : discText
    }

    /// Determines if a line represents definition code (such as `namespace core {}`, `class Foo;`, etc.).
    static func isDefinitionCode(_ trimmed: String) -> Bool {
        let definitionStarters = [
            "namespace ", "template", "using ", "typedef ", "concept ",
            "class ", "struct ", "enum ", "union ", "fn ", "func ", "def ", "sub ",
            "extern ", "inline ", "constexpr ", "consteval ", "constinit ",
            "static ", "virtual ", "explicit ", "override ", "public:", "private:", "protected:"
        ]
        if definitionStarters.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        if trimmed.hasPrefix("~") && (trimmed.contains("(") || trimmed.hasSuffix("{}")) {
            return true
        }
        if trimmed.hasSuffix("{}") || trimmed.hasSuffix("};") {
            return true
        }
        return false
    }
}
