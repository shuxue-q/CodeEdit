//
//  TextViewController+ContextMenuDocBlame.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit
import SwiftUI
import CodeEditTextView

extension TextViewController {

    // MARK: - Folding

    /// Toggles code folding for the block at the specified line number.
    /// - Parameter lineNumber: 1-indexed line number.
    public func toggleFold(at lineNumber: Int) {
        let lineIdx = max(0, lineNumber - 1)
        guard let fold = gutterView.foldingRibbon.model?.getCachedFoldAt(lineNumber: lineIdx) else {
            BezelNotification.show(symbolName: "line.3.horizontal", over: textView)
            return
        }
        gutterView.foldingRibbon.toggleFold(for: fold)
    }

    // MARK: - Documentation

    /// Adds documentation comment template above the specified line.
    /// - Parameter lineNumber: 1-indexed line number. Defaults to the current cursor line.
    public func addDocumentation(at lineNumber: Int? = nil) {
        guard isEditable else { return }
        let lineNum = lineNumber ?? currentCursorLine()
        let lineIdx = max(0, lineNum - 1)
        guard let lineInfo = textView.layoutManager.textLineForIndex(lineIdx) else { return }

        let (declaration, indent) = gatherDeclarationText(startingAt: lineIdx)
        let docString = generateDocComment(for: declaration, indent: indent)
        let docWithNewline = docString + "\n"

        let insertionLocation = lineInfo.range.lowerBound

        textView.replaceCharacters(
            in: NSRange(location: insertionLocation, length: 0),
            with: docWithNewline
        )

        selectPlaceholderOrEndOfDoc(docString: docString, insertionLocation: insertionLocation)
        BezelNotification.show(symbolName: "text.quote", over: textView)
    }

    /// Gathers multi-line declaration signature if declaration continues past the first line.
    func gatherDeclarationText(startingAt lineIdx: Int) -> (declaration: String, indent: String) {
        guard let firstLineInfo = textView.layoutManager.textLineForIndex(lineIdx) else {
            return ("", "")
        }
        let fullString = textView.textStorage.string as NSString
        let firstLineText = fullString.substring(with: firstLineInfo.range)
        let indent = String(firstLineText.prefix { $0 == " " || $0 == "\t" })

        var combined = firstLineText
        let trimmed = firstLineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDeclHeader = trimmed.contains("func ") || trimmed.hasPrefix("func ")
            || trimmed.contains("init(") || trimmed.contains("init?(") || trimmed.contains("init!(")
            || trimmed.contains("subscript(") || trimmed.hasPrefix("init") || trimmed.hasPrefix("subscript")

        if isDeclHeader && !combined.contains(")") {
            var currentIdx = lineIdx
            while currentIdx + 1 < textView.layoutManager.lineCount && currentIdx - lineIdx < 15 {
                currentIdx += 1
                if let nextLineInfo = textView.layoutManager.textLineForIndex(currentIdx) {
                    let nextText = fullString.substring(with: nextLineInfo.range)
                    combined += " " + nextText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextText.contains(")") || nextText.contains("{") {
                        break
                    }
                }
            }
        }

        return (combined, indent)
    }

    private func selectPlaceholderOrEndOfDoc(docString: String, insertionLocation: Int) {
        if let placeholderRange = docString.range(of: "<#Description#>") {
            let nsRange = NSRange(placeholderRange, in: docString)
            let selectRange = NSRange(location: insertionLocation + nsRange.location, length: nsRange.length)
            textView.selectionManager.setSelectedRange(selectRange)
        } else {
            let len = (docString as NSString).length + 1
            textView.selectionManager.setSelectedRange(NSRange(location: insertionLocation + len, length: 0))
        }
    }

    /// Generates a documentation comment string based on the language and declaration on the line.
    func generateDocComment(for declaration: String, indent: String? = nil) -> String {
        let trimmed = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIndent = indent ?? String(declaration.prefix { $0 == " " || $0 == "\t" })

        if language.id == .python {
            return "\(resolvedIndent)\"\"\"<#Description#>\"\"\""
        }

        let isSwiftCallable = trimmed.contains("func ") || trimmed.hasPrefix("func ")
            || trimmed.contains("init(") || trimmed.contains("init?(") || trimmed.contains("init!(")
            || trimmed.contains("subscript(") || trimmed.hasPrefix("init") || trimmed.hasPrefix("subscript")

        if isSwiftCallable {
            let paramNames = extractSwiftParamNames(from: trimmed)
            let hasReturn = trimmed.contains("->") && !trimmed.contains("-> Void") && !trimmed.contains("-> ()")
            let throwsError = trimmed.contains(" throws") || trimmed.contains(" rethrows")
            return generateSwiftFuncDoc(
                indent: resolvedIndent,
                paramNames: paramNames,
                hasReturn: hasReturn,
                throwsError: throwsError
            )
        }

        return "\(resolvedIndent)/// <#Description#>"
    }

    private struct NestingDepth {
        var paren = 0
        var bracket = 0
        var angle = 0
        var brace = 0

        var isAtTopLevel: Bool {
            paren == 0 && bracket == 0 && angle == 0 && brace == 0
        }

        mutating func adjust(for char: Character) {
            switch char {
            case "(": paren += 1
            case ")": paren = max(0, paren - 1)
            case "[": bracket += 1
            case "]": bracket = max(0, bracket - 1)
            case "<": angle += 1
            case ">": angle = max(0, angle - 1)
            case "{": brace += 1
            case "}": brace = max(0, brace - 1)
            default: break
            }
        }
    }

    private func splitTopLevelParameters(_ paramsString: Substring) -> [String] {
        var rawParams: [String] = []
        var currentParam = ""
        var depth = NestingDepth()

        for char in paramsString {
            if char == "," && depth.isAtTopLevel {
                rawParams.append(currentParam)
                currentParam = ""
            } else {
                depth.adjust(for: char)
                currentParam.append(char)
            }
        }
        if !currentParam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawParams.append(currentParam)
        }
        return rawParams
    }

    private func parseParamName(from rawParam: String) -> String? {
        let trimmed = rawParam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
        let namePart = trimmed[..<colonIdx].trimmingCharacters(in: .whitespaces)
        guard let actualName = namePart.split(whereSeparator: { $0.isWhitespace }).last,
              actualName != "_" else { return nil }
        return String(actualName)
    }

    private func extractSwiftParamNames(from declaration: String) -> [String] {
        guard let openParen = declaration.firstIndex(of: "("),
              let closeParen = declaration.lastIndex(of: ")"),
              openParen < closeParen else { return [] }

        let paramsString = declaration[declaration.index(after: openParen)..<closeParen]
        return splitTopLevelParameters(paramsString).compactMap { parseParamName(from: $0) }
    }

    private func generateSwiftFuncDoc(
        indent: String,
        paramNames: [String],
        hasReturn: Bool,
        throwsError: Bool = false
    ) -> String {
        var docLines: [String] = ["\(indent)/// <#Description#>"]
        if !paramNames.isEmpty || hasReturn || throwsError {
            docLines.append("\(indent)///")
        }
        if !paramNames.isEmpty {
            docLines.append("\(indent)/// - Parameters:")
            for name in paramNames {
                docLines.append("\(indent)///   - \(name): <#\(name) description#>")
            }
        }
        if throwsError {
            docLines.append("\(indent)/// - Throws: <#description#>")
        }
        if hasReturn {
            docLines.append("\(indent)/// - Returns: <#return value description#>")
        }
        return docLines.joined(separator: "\n")
    }

    // MARK: - Git Blame

    /// Shows the last git change (git blame) for the specified line.
    /// - Parameter lineNumber: 1-indexed line number.
    public func showLastChange(at lineNumber: Int) {
        let lineIdx = max(0, lineNumber - 1)
        guard let lineInfo = textView.layoutManager.textLineForIndex(lineIdx) else { return }

        var lineRect = textView.layoutManager.rectForOffset(lineInfo.range.lowerBound)
            ?? NSRect(x: 0, y: CGFloat(lineIdx) * 18, width: 100, height: 18)
        if lineRect.size.width <= 0 { lineRect.size.width = 100 }
        if lineRect.size.height <= 0 { lineRect.size.height = 18 }

        if contextMenuDelegate?.showLastChangeForLine(line: lineNumber, rect: lineRect) == true {
            return
        }

        guard let fileURL = fileURL else {
            BezelNotification.show(symbolName: "questionmark.circle", over: textView)
            return
        }

        queryGitBlame(for: fileURL, line: lineNumber, rect: lineRect)
    }

    /// Queries git blame for a line and presents the result in a popover.
    func queryGitBlame(for fileURL: URL, line: Int, rect: NSRect) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.currentDirectoryURL = fileURL.deletingLastPathComponent()
            process.arguments = ["blame", "-L", "\(line),\(line)", "--porcelain", fileURL.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty,
                   let info = self?.parseGitBlameOutput(output) {
                    DispatchQueue.main.async {
                        self?.showGitBlamePopover(info: info, at: rect)
                    }
                    return
                }

                self?.handleGitBlameFallback(directory: fileURL.deletingLastPathComponent(), rect: rect)
            } catch {
                self?.showGitBlameError()
            }
        }
    }

    private func checkGitWorkTree(directory: URL) -> Bool {
        let checkGit = Process()
        checkGit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        checkGit.currentDirectoryURL = directory
        checkGit.arguments = ["rev-parse", "--is-inside-work-tree"]
        checkGit.standardOutput = Pipe()
        checkGit.standardError = Pipe()
        try? checkGit.run()
        checkGit.waitUntilExit()
        return checkGit.terminationStatus == 0
    }

    private func handleGitBlameFallback(directory: URL, rect: NSRect) {
        if checkGitWorkTree(directory: directory) {
            let uncommittedInfo = GitBlameLineInfo(
                commitHash: "0000000000000000000000000000000000000000",
                author: "Not Committed Yet",
                authorEmail: "",
                date: Date(),
                summary: "Uncommitted changes on this line",
                lineContent: ""
            )
            DispatchQueue.main.async { [weak self] in
                self?.showGitBlamePopover(info: uncommittedInfo, at: rect)
            }
        } else {
            showGitBlameError()
        }
    }

    private func showGitBlameError() {
        DispatchQueue.main.async { [weak self] in
            if let textView = self?.textView {
                BezelNotification.show(symbolName: "questionmark.circle", over: textView)
            }
        }
    }

    private func parseGitBlameOutput(_ output: String) -> GitBlameLineInfo {
        var commitHash = ""
        var author = "Unknown"
        var authorEmail = ""
        var authorTime: TimeInterval = 0
        var summary = ""
        var lineContent = ""

        let lines = output.components(separatedBy: "\n")
        if let firstLine = lines.first, let hash = firstLine.split(separator: " ").first {
            commitHash = String(hash)
        }

        for line in lines {
            if line.hasPrefix("author ") {
                author = String(line.dropFirst(7))
            } else if line.hasPrefix("author-mail ") {
                authorEmail = String(line.dropFirst(12)).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            } else if line.hasPrefix("author-time ") {
                authorTime = TimeInterval(line.dropFirst(12).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("summary ") {
                summary = String(line.dropFirst(8))
            } else if line.hasPrefix("\t") {
                lineContent = String(line.dropFirst(1))
            }
        }

        if !commitHash.isEmpty && commitHash.allSatisfy({ $0 == "0" }) {
            author = "Not Committed Yet"
            summary = "Uncommitted changes on this line"
        }

        let date = authorTime > 0 ? Date(timeIntervalSince1970: authorTime) : Date()
        return GitBlameLineInfo(
            commitHash: commitHash,
            author: author,
            authorEmail: authorEmail,
            date: date,
            summary: summary.isEmpty ? "No commit message" : summary,
            lineContent: lineContent
        )
    }

    /// Shows the git blame popover over the specified line rect.
    func showGitBlamePopover(info: GitBlameLineInfo, at rect: NSRect) {
        let popover = NSPopover()
        popover.behavior = .transient
        let view = GitBlamePopoverView(info: info) { [weak popover] in
            popover?.close()
        }
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }
}
