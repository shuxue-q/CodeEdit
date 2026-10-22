//
//  FindMethod.swift
//  CodeEditSourceEditor
//
//  Created by Austin Condiff on 5/2/25.
//

enum FindMethod: CaseIterable {
    case contains
    case matchesWord
    case startsWith
    case endsWith
    case regularExpression

    var displayName: String {
        switch self {
        case .contains:
            return String(localized: "Contains", bundle: .module)
        case .matchesWord:
            return String(localized: "Matches Word", bundle: .module)
        case .startsWith:
            return String(localized: "Starts With", bundle: .module)
        case .endsWith:
            return String(localized: "Ends With", bundle: .module)
        case .regularExpression:
            return String(localized: "Regular Expression", bundle: .module)
        }
    }
}
