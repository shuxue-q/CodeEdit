//
//  SyntacticContext.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// The syntactic position of the cursor, used to weight and filter completion candidates.
enum SyntacticContext: Equatable, Hashable, Sendable {
    /// After `.`, `->`, or `::`.
    case memberAccess
    /// Inside a preprocessor directive line.
    case preprocessor
    /// Inside a comment.
    case comment
    /// Inside a string literal.
    case string
    /// A position where a type name is expected.
    case typePosition
    /// Inside a function body / statement position.
    case statement
    /// Outside of any function body, at file scope.
    case topLevel
    /// The context could not be determined.
    case unknown
}
