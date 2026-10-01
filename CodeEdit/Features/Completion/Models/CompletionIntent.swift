//
//  CompletionIntent.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// What the user is most likely writing at the cursor.
///
/// Recognized by ``CompletionIntentRecognizer`` from the text typed before the cursor and the
/// syntax tree around it. The intent decides which candidates are offered, how they are weighted
/// (see ``CompletionIntentPolicy``), and whether a typing-triggered request opens the window at all.
enum CompletionIntent: Equatable, Hashable, Sendable, CaseIterable {
    /// After `.` or `->`: a field or method of the receiver.
    case memberAccess
    /// After `::`: a member of a namespace, class, or enum.
    case scopeAccess
    /// Inside the `<…>` or `"…"` of an `#include` / `#import`: a header path.
    case includePath
    /// On any other preprocessor line: a directive or a macro.
    case preprocessor
    /// Where a type is expected: after `const`, `new`, `struct`, a cast's `<`, in a parameter list.
    case typeName
    /// Right after a complete type (`int |`, `std::string |`): the user is naming a new symbol.
    case declarationName
    /// After `case`: an enumerator or constant.
    case caseLabel
    /// Where a value is expected: after `=`, `return`, `(`, `,`, or an operator.
    case expression
    /// At the start of a statement inside a function body.
    case statement
    /// At file, namespace, or class-body scope.
    case topLevel
    /// Inside a comment.
    case comment
    /// Inside a string or character literal.
    case string
    /// Typing a number literal.
    case numberLiteral
    /// The intent could not be determined.
    case unknown

    /// A short, human-readable description, used in the AI completion prompt.
    var promptDescription: String {
        switch self {
        case .memberAccess: return "a member of the object before the cursor"
        case .scopeAccess: return "a member of the scope before `::`"
        case .includePath: return "a header path"
        case .preprocessor: return "a preprocessor directive or macro"
        case .typeName: return "a type name"
        case .declarationName: return "the name of a new declaration"
        case .caseLabel: return "a case label (an enumerator or constant)"
        case .expression: return "an expression"
        case .statement: return "a statement"
        case .topLevel: return "a declaration at file or class scope"
        case .comment: return "comment text"
        case .string: return "string contents"
        case .numberLiteral: return "a number"
        case .unknown: return "code"
        }
    }
}
