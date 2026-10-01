//
//  CompletionIntentRecognizerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class CompletionIntentRecognizerTests: XCTestCase {
    /// Node ancestry inside a function body.
    private let body = ["compound_statement", "function_definition", "translation_unit"]
    /// Node ancestry at file scope.
    private let file = ["translation_unit"]

    /// Recognizes the intent at the end of `line`, where the typed prefix is the trailing word.
    private func intent(
        _ line: String,
        nodeTypes: [String] = [],
        languageId: String = "cpp"
    ) -> CompletionIntent {
        let prefix = String(line.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" }.reversed())
        return CompletionIntentRecognizer { _ in nodeTypes }
            .recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: languageId)
    }

    // MARK: - Tree ancestry (migrated from SyntacticContextResolver)

    func testCommentNodeResolvesToComment() {
        XCTAssertEqual(intent("// ", nodeTypes: ["comment", "translation_unit"]), .comment)
    }

    func testStringLiteralNodeResolvesToString() {
        XCTAssertEqual(intent("\"", nodeTypes: ["string_literal", "compound_statement"]), .string)
    }

    func testPreprocNodeResolvesToPreprocessor() {
        XCTAssertEqual(intent("#define ", nodeTypes: ["preproc_def", "translation_unit"]), .preprocessor)
    }

    func testFieldExpressionResolvesToMemberAccess() {
        XCTAssertEqual(intent("point.", nodeTypes: ["field_expression", "compound_statement"]), .memberAccess)
    }

    func testCompoundStatementResolvesToStatement() {
        XCTAssertEqual(intent("    ", nodeTypes: ["compound_statement"]), .statement)
    }

    func testTranslationUnitResolvesToTopLevel() {
        XCTAssertEqual(intent("", nodeTypes: file), .topLevel)
    }

    func testUnrecognizedNodeTypesResolveToUnknown() {
        XCTAssertEqual(intent("", nodeTypes: ["some_unmapped_node"]), .unknown)
    }

    func testInnermostEnclosingNodeWins() {
        // A lambda body inside a call's arguments is a statement position, not an argument.
        let types = ["compound_statement", "lambda_expression", "argument_list", "compound_statement"]
        XCTAssertEqual(intent("        ", nodeTypes: types), .statement)
        XCTAssertEqual(intent("        ", nodeTypes: ["argument_list", "call_expression"] + body), .expression)
    }

    // MARK: - Text fallbacks without a tree

    func testTextFallbackDetectsPreprocessorWithoutATree() {
        XCTAssertEqual(intent("#inc"), .preprocessor)
    }

    func testTextFallbackDetectsLineComments() {
        XCTAssertEqual(intent("  // note"), .comment)
        XCTAssertEqual(intent("x = 1; // trailing note"), .comment)
    }

    func testTextFallbackDetectsBlockComments() {
        XCTAssertEqual(intent("x = 1; /* open"), .comment)
        XCTAssertEqual(intent(" * continued"), .comment)
        XCTAssertEqual(intent("x = /* closed */ val"), .expression)
    }

    func testDereferenceAtLineStartIsNotAComment() {
        XCTAssertNotEqual(intent("*ptr"), .comment)
    }

    func testUnterminatedStringIsDetectedFromText() {
        XCTAssertEqual(intent("printf(\"hello wor", nodeTypes: body), .string)
        XCTAssertEqual(intent("c = 'a", nodeTypes: body), .string)
        XCTAssertEqual(intent("puts(\"done\"); fo", nodeTypes: body), .statement)
    }

    // MARK: - Access operators

    func testAccessOperators() {
        XCTAssertEqual(intent("point.x"), .memberAccess)
        XCTAssertEqual(intent("    node->", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    std::vec", nodeTypes: ["identifier"] + body), .scopeAccess)
    }

    func testScopeOperatorAtTopLevelResolvesToScopeAccess() {
        // `template <typename T> std::` parses as an ERROR node under the translation unit.
        let types = ["namespace_identifier", "ERROR", "translation_unit"]
        XCTAssertEqual(intent("template <typename T> std::", nodeTypes: types), .scopeAccess)
    }

    func testSingleColonIsNotMemberAccess() {
        XCTAssertEqual(intent("    label:", nodeTypes: ["compound_statement"]), .statement)
    }

    func testCFamilyScopesDoNotApplyToOtherGrammars() {
        // CMake's grammar also has an `argument_list`: `set(CMAKE_` must not be treated as a C call.
        let types = ["argument_list", "normal_command", "source_file"]
        XCTAssertEqual(intent("set(CMAKE_", nodeTypes: types, languageId: "cmake"), .unknown)
    }

    func testAccessOperatorsApplyToOtherLanguages() {
        XCTAssertEqual(intent("self.na", languageId: "python"), .memberAccess)
        XCTAssertEqual(intent("Foo::ba", languageId: "rust"), .scopeAccess)
    }

    // MARK: - Literals and preprocessor

    func testNumberLiteral() {
        XCTAssertEqual(intent("x = 12", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("x = 0x1F", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("x = 1.5", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("x = v1", nodeTypes: body), .expression)
    }

    func testIncludePathInsideAngleBracketsAndQuotes() {
        XCTAssertEqual(intent("#include <vec", nodeTypes: ["system_lib_string", "preproc_include"]), .includePath)
        // `#include "…"` parses as a string literal; it is still a header path.
        XCTAssertEqual(intent("#include \"my", nodeTypes: ["string_literal", "preproc_include"]), .includePath)
        XCTAssertEqual(intent("  #  import <Foundation/Fo"), .includePath)
    }

    func testClosedIncludeIsPreprocessor() {
        XCTAssertEqual(intent("#include <vector> ", nodeTypes: ["preproc_include"]), .preprocessor)
    }

    func testPreprocessorDirectiveName() {
        XCTAssertEqual(intent("#def"), .preprocessor)
        XCTAssertEqual(intent("#ifdef DEB"), .preprocessor)
    }

    func testHashLineIsNotPreprocessorOutsideTheCFamily() {
        XCTAssertNotEqual(intent("# note", languageId: "python"), .preprocessor)
    }

    // MARK: - Keywords

    func testKeywordsThatDecideTheIntent() {
        XCTAssertEqual(intent("    return va", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    case Col", nodeTypes: body), .caseLabel)
        XCTAssertEqual(intent("    } else ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    throw std", nodeTypes: body), .expression)
    }

    func testTypeModifiersExpectAType() {
        XCTAssertEqual(intent("    const Str", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    unsigned ", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    auto *p = new Po", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("static ", nodeTypes: file), .typeName)
    }

    func testUsingNamespace() {
        XCTAssertEqual(intent("using namespace st", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("namespace fo", nodeTypes: file), .declarationName)
    }

    // MARK: - Declarations

    func testNameAfterABuiltinTypeIsADeclarationName() {
        XCTAssertEqual(intent("    int cou", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    unsigned int to", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("void ma", nodeTypes: file), .declarationName)
    }

    func testNameAfterAUserTypeIsADeclarationName() {
        XCTAssertEqual(intent("    Point p", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    std::string na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    const Foo f", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    std::map<int, std::string> by", nodeTypes: body), .declarationName)
    }

    func testPointerAndReferenceDeclarators() {
        XCTAssertEqual(intent("    int *p", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    for (const auto &it", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    x = a * b", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    return a & ma", nodeTypes: body), .expression)
    }

    func testMacroBeforeADeclarationIsNotATypeName() {
        XCTAssertNotEqual(intent("EXPORT_API vo", nodeTypes: file), .declarationName)
    }

    func testObjectiveCMessageSendIsNotADeclaration() {
        XCTAssertNotEqual(intent("    [receiver sen", nodeTypes: body, languageId: "objective-c"), .declarationName)
    }

    func testMultipleDeclarators() {
        XCTAssertEqual(intent("    int a, b", nodeTypes: body), .declarationName)
    }

    // MARK: - Expressions and types

    func testOperatorsExpectAValue() {
        XCTAssertEqual(intent("    x = va", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    if (a == b", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    total += co", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    ok = !fl", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    items[in", nodeTypes: body), .expression)
    }

    func testParenthesesAfterControlKeywordsAndCalls() {
        XCTAssertEqual(intent("    if (va", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    for (in", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    foo(ar", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    foo(a, ar", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    std::max(a", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    } catch (co", nodeTypes: body), .typeName)
    }

    func testFunctionDeclarationParametersExpectATypeAtFileScope() {
        XCTAssertEqual(intent("void draw(Sha", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("int *make(const Foo &f, Ba", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("void Canvas::draw(Sha", nodeTypes: file), .typeName)
        // Inside a body, `Foo f(` is a constructor call.
        XCTAssertEqual(intent("    Foo f(va", nodeTypes: body), .expression)
    }

    func testTemplateArguments() {
        XCTAssertEqual(intent("    std::vector<Po", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    auto n = static_cast<in", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("template <typ", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("    std::map<int, Str", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    if (a < b", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    if (a > b", nodeTypes: body), .expression)
    }

    func testTemplateHeadIsFollowedByADeclaration() {
        XCTAssertEqual(intent("template <typename T> cl", nodeTypes: file), .topLevel)
    }

    func testBaseClause() {
        XCTAssertEqual(intent("class Circle : public Sha", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("struct Circle : Sha", nodeTypes: file), .typeName)
    }

    func testEnumBodyNamesNewEnumerators() {
        XCTAssertEqual(intent("enum Color { Red, Gr", nodeTypes: file), .declarationName)
    }

    func testTernaryAndInitializerLists() {
        XCTAssertEqual(intent("    x = ok ? a : b", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    int v[] = { on", nodeTypes: body), .expression)
    }

    func testStatementStartFallsBackToTheTree() {
        XCTAssertEqual(intent("    fo", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    x = 1; fo", nodeTypes: body), .statement)
        XCTAssertEqual(intent("st", nodeTypes: file), .topLevel)
    }
}
