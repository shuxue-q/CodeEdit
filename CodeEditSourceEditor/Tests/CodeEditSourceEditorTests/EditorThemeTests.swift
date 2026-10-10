import XCTest
@testable import CodeEditSourceEditor

final class EditorThemeTests: XCTestCase {
    private func makeTheme(
        functions: EditorTheme.Attribute? = nil,
        operators: EditorTheme.Attribute? = nil,
        assignedVariables: EditorTheme.Attribute? = nil,
        properties: EditorTheme.Attribute? = nil,
        parameters: EditorTheme.Attribute? = nil,
        globals: EditorTheme.Attribute? = nil,
        namespaces: EditorTheme.Attribute? = nil,
        macros: EditorTheme.Attribute? = nil,
        preprocessors: EditorTheme.Attribute? = nil,
        primitiveTypes: EditorTheme.Attribute? = nil
    ) -> EditorTheme {
        EditorTheme(
            text: .init(color: .white),
            insertionPoint: .white,
            invisibles: .init(color: .gray),
            background: .black,
            lineHighlight: .darkGray,
            selection: .blue,
            keywords: .init(color: .purple),
            commands: .init(color: .systemBlue),
            types: .init(color: .yellow),
            attributes: .init(color: .orange),
            variables: .init(color: .red),
            values: .init(color: .brown),
            numbers: .init(color: .magenta),
            strings: .init(color: .green),
            characters: .init(color: .green),
            comments: .init(color: .lightGray),
            functions: functions,
            operators: operators,
            assignedVariables: assignedVariables,
            properties: properties,
            parameters: parameters,
            globals: globals,
            namespaces: namespaces,
            macros: macros,
            preprocessors: preprocessors,
            primitiveTypes: primitiveTypes
        )
    }

    /// Themes that do not define the newer roles keep the colors those captures used before the roles existed.
    func test_newRolesFallBackToLegacyAttributes() {
        let theme = makeTheme()
        XCTAssertEqual(theme.functions, theme.commands)
        XCTAssertEqual(theme.assignedVariables, theme.variables)
        XCTAssertEqual(theme.operators, theme.text)
        XCTAssertEqual(theme.colorFor(.function), .systemBlue)
        XCTAssertEqual(theme.colorFor(.method), .systemBlue)
        XCTAssertEqual(theme.colorFor(.assignedVariable), .red)
        XCTAssertEqual(theme.colorFor(.operator), .white)
    }

    func test_captureRolesMapToTheirOwnAttributes() {
        let theme = makeTheme(
            functions: .init(color: .cyan),
            operators: .init(color: .systemPink, bold: true),
            assignedVariables: .init(color: .systemTeal, italic: true)
        )
        XCTAssertEqual(theme.colorFor(.function), .cyan)
        XCTAssertEqual(theme.colorFor(.method), .cyan)
        XCTAssertEqual(theme.colorFor(.assignedVariable), .systemTeal)
        XCTAssertEqual(theme.colorFor(.operator), .systemPink)
        // Variables that are only read, parameters and properties keep the variables color.
        XCTAssertEqual(theme.colorFor(.variable), .red)
        XCTAssertEqual(theme.colorFor(.parameter), .red)
        XCTAssertEqual(theme.colorFor(.property), .red)
        XCTAssertEqual(theme.colorFor(.constant), .brown)
        XCTAssertEqual(theme.colorFor(.number), .magenta)

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        XCTAssertTrue(theme.fontFor(for: .operator, from: font).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(theme.fontFor(for: .assignedVariable, from: font).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(theme.fontFor(for: .variable, from: font), font)
    }

    func test_assignedCaptureNameParsing() {
        XCTAssertEqual(CaptureName.fromString("variable.assigned"), .assignedVariable)
        XCTAssertEqual(CaptureName.fromString("variable.assigned.member"), .assignedVariable)
        XCTAssertEqual(CaptureName.fromString("variable"), .variable)
        XCTAssertTrue(CaptureName.variable.isVariableFamily)
        XCTAssertTrue(CaptureName.property.isVariableFamily)
        XCTAssertTrue(CaptureName.parameter.isVariableFamily)
        XCTAssertFalse(CaptureName.assignedVariable.isVariableFamily)
        XCTAssertFalse(CaptureName.function.isVariableFamily)
    }

    /// Themes that predate the symbol roles style the same text exactly as before.
    func test_symbolRolesFallBackToLegacyAttributes() {
        let theme = makeTheme()
        XCTAssertEqual(theme.colorFor(.property), .red)
        XCTAssertEqual(theme.colorFor(.parameter), .red)
        XCTAssertEqual(theme.colorFor(.globalVariable), .red)
        XCTAssertEqual(theme.colorFor(.namespace), .yellow)
        XCTAssertEqual(theme.colorFor(.macro), .brown)
        XCTAssertEqual(theme.colorFor(.preprocessor), .purple)
        XCTAssertEqual(theme.colorFor(.primitiveType), .yellow)
    }

    func test_symbolRolesMapToTheirOwnAttributes() {
        let theme = makeTheme(
            properties: .init(color: .cyan),
            parameters: .init(color: .systemTeal),
            globals: .init(color: .systemOrange),
            namespaces: .init(color: .systemIndigo),
            macros: .init(color: .systemMint),
            preprocessors: .init(color: .systemPink, bold: true),
            primitiveTypes: .init(color: .systemGreen, italic: true)
        )
        XCTAssertEqual(theme.colorFor(.property), .cyan)
        XCTAssertEqual(theme.colorFor(.parameter), .systemTeal)
        XCTAssertEqual(theme.colorFor(.globalVariable), .systemOrange)
        XCTAssertEqual(theme.colorFor(.namespace), .systemIndigo)
        XCTAssertEqual(theme.colorFor(.macro), .systemMint)
        XCTAssertEqual(theme.colorFor(.preprocessor), .systemPink)
        XCTAssertEqual(theme.colorFor(.primitiveType), .systemGreen)
        // Plain variables and types are unaffected.
        XCTAssertEqual(theme.colorFor(.variable), .red)
        XCTAssertEqual(theme.colorFor(.type), .yellow)

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        XCTAssertTrue(theme.fontFor(for: .preprocessor, from: font).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(theme.fontFor(for: .primitiveType, from: font).fontDescriptor.symbolicTraits.contains(.italic))
    }

    func test_symbolCaptureNameParsing() {
        XCTAssertEqual(CaptureName.fromString("variable.global"), .globalVariable)
        XCTAssertEqual(CaptureName.fromString("namespace"), .namespace)
        XCTAssertEqual(CaptureName.fromString("macro"), .macro)
        XCTAssertEqual(CaptureName.fromString("preprocessor"), .preprocessor)
        XCTAssertEqual(CaptureName.fromString("type.builtin"), .primitiveType)
        XCTAssertEqual(CaptureName.fromString("type"), .type)
        XCTAssertEqual(CaptureName.fromString("variable.parameter"), .parameter)
        XCTAssertEqual(CaptureName.fromString("variable.member"), .property)
    }

    func test_captureRefinementByScopeModifiers() {
        XCTAssertEqual(CaptureName.variable.refined(by: [.fileScope]), .globalVariable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.globalScope]), .globalVariable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.classScope]), .property)
        XCTAssertEqual(CaptureName.variable.refined(by: [.functionScope, .declaration]), .variable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.modification]), .assignedVariable)
        XCTAssertEqual(CaptureName.property.refined(by: [.modification]), .property)
        XCTAssertEqual(CaptureName.parameter.refined(by: [.globalScope]), .parameter)
    }
}
