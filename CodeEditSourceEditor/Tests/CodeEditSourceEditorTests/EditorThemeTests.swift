import XCTest
@testable import CodeEditSourceEditor

final class EditorThemeTests: XCTestCase {
    private func makeTheme(
        functions: EditorTheme.Attribute? = nil,
        operators: EditorTheme.Attribute? = nil,
        assignedVariables: EditorTheme.Attribute? = nil
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
            assignedVariables: assignedVariables
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
}
