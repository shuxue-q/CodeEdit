//
//  CMakeTokenRules.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

/// The CMake rules of ``CompletionIntentRecognizer``: what the cursor's line and the syntax tree say
/// about where the user is in a `CMakeLists.txt` or `*.cmake` file.
///
/// CMake has three places a completion can happen, and they map onto the shared ``CompletionIntent``
/// cases like this:
///
/// - **Command position**, the first word of a command (`add_|`): ``CompletionIntent/statement``
///   inside a function, macro, block, `if`, or loop body, ``CompletionIntent/topLevel`` at file
///   scope. The two differ in the C family; for CMake they only record where the command goes.
/// - **Arguments**, after the `(` or a space: ``CompletionIntent/argument``. This covers keyword
///   arguments (`PUBLIC`, `REQUIRED`), targets, paths, and bare variable names alike.
/// - **Variable names**, inside `${`, `$ENV{`, or `$CACHE{`, also inside quoted text:
///   ``CompletionIntent/variableReference``.
///
/// Comments (`#`) and quoted or bracket arguments are ``CompletionIntent/comment`` and
/// ``CompletionIntent/string``. CMake has neither member access nor number literals as far as
/// completion goes: `src/main.cpp` and `3.20` are arguments, so the window stays available.
///
/// The line decides what it can see (an open parenthesis, an open quote, an open reference); the
/// syntax tree decides what only it can see (the continuation lines of a command, a multi-line
/// quote or bracket comment). Incomplete code parses as `ERROR`, so the tree is consulted for scope,
/// not trusted for the cursor's exact node.
enum CMakeTokenRules {
    /// Recognizes the intent for a CMake document.
    /// - Parameters:
    ///   - types: The node types around the cursor, innermost first. Empty without a syntax tree.
    ///   - prefix: The word being typed, up to the cursor.
    ///   - beforePrefix: The cursor's line up to the typed prefix.
    static func intent(types: [String], prefix: String, beforePrefix: String) -> CompletionIntent {
        let scan = CMakeLineScanner.scan(beforePrefix)
        let tree = CMakeKeywords.treeScope(types)

        if scan.state.isComment || tree == .comment {
            return .comment
        }
        if scan.reference != nil || tree == .reference && !prefix.isEmpty {
            return .variableReference
        }
        if scan.state.isString || tree == .string && !scan.endsWithClosedQuote {
            return .string
        }
        if prefix.hasPrefix("#") {
            return .comment
        }

        if scan.parenthesisDepth > 0 {
            return .argument
        }
        if scan.isBlank || scan.lastCodeCharacter == nil {
            // Nothing but whitespace (or a finished comment) before the prefix: a command name, unless
            // the tree says an earlier line's argument list is still open.
            return tree == .argument ? .argument : commandPosition(types: types, indented: !beforePrefix.isEmpty)
        }
        // Code precedes the prefix on this line. After a finished command (`endif() add_`) a new
        // command can start; otherwise the line continues an argument list from an earlier line.
        return scan.lastCodeCharacter == ")" ? commandPosition(types: types, indented: true) : .argument
    }

    /// The scope of a command name: from the tree, or, without one, from the indentation, since
    /// CMake files indent the commands of a block.
    private static func commandPosition(types: [String], indented: Bool) -> CompletionIntent {
        CMakeKeywords.commandScope(types) ?? (indented ? .statement : .topLevel)
    }
}
