//
//  CMakeKeywords.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

/// The CMake vocabulary used to recognize completion intent: which language ids the CMake rules
/// apply to, and which tree-sitter node types of the vendored `tree-sitter-cmake` grammar mean what.
enum CMakeKeywords {
    /// Language identifiers the CMake rules apply to. `CMakeLists.txt` and `*.cmake` both resolve to
    /// `cmake`, in the editor's `CodeLanguage` ids and in the language server's.
    static let languageIds: Set<String> = ["cmake"]

    /// What a node type at the cursor says about where the cursor is, in a CMake syntax tree.
    enum TreeScope: Equatable {
        /// In a `#` or `#[[ … ]]` comment.
        case comment
        /// In the name of a `${…}`, `$ENV{…}`, or `$CACHE{…}` reference.
        case reference
        /// In a quoted or bracket argument.
        case string
        /// On a command's name (`add_executable`, `endif`), as opposed to its parentheses.
        case commandName
        /// In a command's parentheses or argument list.
        case argument
        /// In a function, macro, block, `if`, `foreach`, or `while` body.
        case body
        /// Directly in the file.
        case file
    }

    /// Node types for comments.
    static let commentNodes: Set<String> = ["line_comment", "bracket_comment"]

    /// Node types for the name inside a variable reference. The reference node itself
    /// (`variable_ref`) is included: its braces are anonymous nodes, so an innermost `}` or `{`
    /// resolves through it.
    static let referenceNodes: Set<String> = ["variable_ref", "normal_var", "env_var", "cache_var", "variable"]

    /// Node types for quoted text. `bracket_argument_content` is left out on purpose: the grammar's
    /// external scanner emits it with zero width at the end of an unfinished command.
    static let stringNodes: Set<String> = ["quoted_argument", "quoted_element", "bracket_argument"]

    /// Node types for the command name. `identifier` names a plain command; the flow-control
    /// commands have a node per keyword.
    static let commandNameNodes: Set<String> = [
        "identifier",
        "if", "elseif", "else", "endif",
        "foreach", "endforeach", "while", "endwhile",
        "function", "endfunction", "macro", "endmacro", "block", "endblock"
    ]

    /// Node types for a command's argument list, and for the command headers that own the
    /// parentheses. The cursor in `foo(|)` has only the header around it.
    static let argumentNodes: Set<String> = [
        "argument_list", "argument", "unquoted_argument",
        "normal_command", "if_command", "elseif_command", "else_command", "endif_command",
        "foreach_command", "endforeach_command", "while_command", "endwhile_command",
        "function_command", "endfunction_command", "macro_command", "endmacro_command",
        "block_command", "endblock_command"
    ]

    /// Node types for the commands between a block's opening and closing command.
    static let bodyNodes: Set<String> = [
        "body", "if_condition", "function_def", "macro_def", "block_def", "foreach_loop", "while_loop"
    ]

    /// Where the cursor is, from the innermost node type the table knows. Anonymous nodes (`(`,
    /// `}`, `ENV`) and `ERROR` are skipped, so incomplete code resolves through the first real
    /// ancestor.
    static func treeScope(_ types: [String]) -> TreeScope? {
        for type in types {
            if commentNodes.contains(type) { return .comment }
            if referenceNodes.contains(type) { return .reference }
            if stringNodes.contains(type) { return .string }
            if commandNameNodes.contains(type) { return .commandName }
            if argumentNodes.contains(type) { return .argument }
            if bodyNodes.contains(type) { return .body }
            if type == "source_file" { return .file }
        }
        return nil
    }

    /// The enclosing scope for a command name: the nearest body is a block of commands, the file
    /// itself is file scope. `nil` when the tree has neither.
    static func commandScope(_ types: [String]) -> CompletionIntent? {
        for type in types {
            if bodyNodes.contains(type) { return .statement }
            if type == "source_file" { return .topLevel }
        }
        return nil
    }
}
