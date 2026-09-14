//
//  String+escapedWhiteSpaces.swift
//  CodeEdit
//
//  Created by Paul Ebose on 2024/07/05.
//

import Foundation

extension String {
    /// Escapes the string so it can be safely used as a single shell argument.
    ///
    /// The string is wrapped in single quotes and every embedded single quote is replaced
    /// with the `'\''` idiom, which protects against `$()`, backticks, `;`, `"`, and spaces.
    func escapedShellArgument() -> String {
        "'" + replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Escapes the string so it's an always-valid directory
    func escapedDirectory() -> String {
        escapedShellArgument()
    }

    /// Returns a new string, replacing all occurrences of ` ` with `\ ` if they aren't already escaped.
    func escapedWhiteSpaces() -> String {
        escape(replacing: " ")
    }

    /// Returns a new string, replacing all occurrences of `"` with `\"` if they aren't already escaped.
    func escapedQuotes() -> String {
        escape(replacing: #"""#)
    }

    func escape(replacing: Character) -> String {
        var string = ""
        var lastChar: Character?

        for char in self {
            defer {
                lastChar = char
            }

            guard char == replacing else {
                string.append(char)
                continue
            }

            if let lastChar, lastChar == #"\"# {
                string.append(char)
                continue
            }

            string.append(#"\"#)
            string.append(char)
        }

        return string
    }
}
