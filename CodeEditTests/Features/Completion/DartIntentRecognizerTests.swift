//
//  DartIntentRecognizerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
@testable import CodeEdit

/// Each row of the Dart intent table (``DartTokenRules``), with node types as the vendored grammar
/// reports them. ``DartIntentTreeTests`` parses whole documents with the real grammar.
final class DartIntentRecognizerTests: XCTestCase {
    /// Node ancestry in a function body.
    private let body = ["block", "function_body", "program"]
    /// Node ancestry in a class body.
    private let classBody = ["class_body", "class_definition", "program"]
    /// Node ancestry at file scope.
    private let file = ["program"]
    /// Node ancestry on a new line of a multi-line argument list.
    private let arguments = ["arguments", "argument_part", "selector", "expression_statement", "block"]
    /// Node ancestry on a new line of a list literal.
    private let listLiteral = ["list_literal", "named_argument", "arguments", "argument_part"]
    /// Node ancestry in a parameter list.
    private let parameters = ["formal_parameter_list", "function_signature", "program"]

    /// Recognizes the intent at the end of `line`, where the typed prefix is the trailing word, the way
    /// the aggregator splits it (`$` belongs to a word).
    private func intent(_ line: String, nodeTypes: [String] = []) -> CompletionIntent {
        let prefix = String(line.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }.reversed())
        return CompletionIntentRecognizer { _ in nodeTypes }
            .recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: "dart")
    }

    // MARK: - Member access

    func testMemberAccess() {
        XCTAssertEqual(intent("    context.", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    context.mou", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    a?.", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    b..", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    b?..ad", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("      ..add", nodeTypes: body), .memberAccess, "A cascade continued on its own line")
        XCTAssertEqual(intent("    padding: const EdgeInsets.", nodeTypes: arguments), .memberAccess)
    }

    func testSpreadAndNumbersAreNotMemberAccess() {
        XCTAssertEqual(intent("    children: [...", nodeTypes: arguments), .expression)
        XCTAssertEqual(intent("    children: [...?ex", nodeTypes: arguments), .expression)
        XCTAssertEqual(intent("    x = 1.5", nodeTypes: body), .numberLiteral)
    }

    // MARK: - Type position

    func testTypePositions() {
        XCTAssertEqual(intent("    final w = new Wid", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    if (x is Wid", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    if (x is! Wid", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    final y = x as Wid", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("class Home extends Stateless", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("class Home implements Comp", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("class Home implements A, Comp", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("class Home with Ticker", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("    } on Format", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    final xs = List<St", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("    final m = Map<String, Li", nodeTypes: body), .typeName)
    }

    func testConstInAValuePositionExpectsAConstructor() {
        XCTAssertEqual(intent("    child: const Te", nodeTypes: arguments), .typeName)
        XCTAssertEqual(intent("    return const Te", nodeTypes: body), .typeName)
        XCTAssertEqual(intent("      const Te", nodeTypes: listLiteral), .typeName, "A list element on its own line")
        XCTAssertEqual(intent("    foo(const Te", nodeTypes: body), .typeName)
    }

    func testParameterListsAreTypePositions() {
        XCTAssertEqual(intent("void greet(", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("  Widget build(", nodeTypes: classBody), .typeName)
        XCTAssertEqual(intent("  const Home(", nodeTypes: classBody), .typeName, "A constructor declaration")
        XCTAssertEqual(intent("  Home.named(", nodeTypes: classBody), .typeName, "A named constructor")
        XCTAssertEqual(intent("void greet(int a, ", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("void greet({required ", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("  const Home({super.key, ", nodeTypes: classBody), .typeName)
        XCTAssertEqual(intent("    ", nodeTypes: parameters), .typeName, "A parameter on its own line")
    }

    // MARK: - Declaration names

    func testNewDeclarationNames() {
        XCTAssertEqual(intent("    var na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    final na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    const na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("  static const na", nodeTypes: classBody), .declarationName)
        XCTAssertEqual(intent("    late na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("  late final na", nodeTypes: classBody), .declarationName)
        XCTAssertEqual(intent("  Widget bu", nodeTypes: classBody), .declarationName)
        XCTAssertEqual(intent("    final String na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    List<int> na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    String? na", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    ui.Image im", nodeTypes: body), .declarationName, "A library-prefixed type")
        XCTAssertEqual(intent("void greet(String na", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("void greet({required String na", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("    } catch (e", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    for (final it", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("class Ho", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("  int get to", nodeTypes: classBody), .declarationName)
    }

    func testValuesAreNotDeclarations() {
        XCTAssertNotEqual(intent("    return va", nodeTypes: body), .declarationName)
        XCTAssertNotEqual(intent("    await fo", nodeTypes: body), .declarationName)
        XCTAssertNotEqual(intent("    x = a ? b ", nodeTypes: body), .declarationName, "A conditional, not `b?`")
    }

    // MARK: - Arguments

    func testCallArguments() {
        XCTAssertEqual(intent("    return Text(", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    Text(", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    Text(", nodeTypes: []), .argument, "Without a syntax tree")
        XCTAssertEqual(intent("    return Padding(padding: x, ", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    return Padding(padding: EdgeInsets.all(8), ch", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    setState(", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    padding: EdgeInsets.all(", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("    child: Text(", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("    final xs = List<int>.filled(", nodeTypes: body), .argument)
        XCTAssertEqual(intent("    foo<int>(", nodeTypes: body), .argument)
        XCTAssertEqual(intent("  Home() : super(", nodeTypes: classBody), .argument)
    }

    func testANewLineOfAMultiLineArgumentListIsAnArgument() {
        XCTAssertEqual(intent("      ", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("      chi", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("      padding: x, chi", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("      pad", nodeTypes: [":", "label", "named_argument"] + arguments), .argument)
    }

    // MARK: - Values

    func testValuePositions() {
        XCTAssertEqual(intent("      child: ", nodeTypes: arguments), .expression)
        XCTAssertEqual(intent("      child: Te", nodeTypes: arguments), .expression)
        XCTAssertEqual(intent("    x = ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    return ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("int twice(int x) => ", nodeTypes: file), .expression)
        XCTAssertEqual(intent("    final y = a ?? ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    a ??= ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    if (", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    final y = ok ? ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    final m = {'a': ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    await fo", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    for (final x in it", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    final ok = !fl", nodeTypes: body), .expression)
        XCTAssertEqual(intent("  @over", nodeTypes: classBody), .expression)
        XCTAssertEqual(intent("      ", nodeTypes: listLiteral), .expression)
    }

    // MARK: - Statements and file scope

    func testStatementAndFileScope() {
        XCTAssertEqual(intent("    ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    fo", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    print('a'); fo", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    if (ok) ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    } else ", nodeTypes: body), .statement)
        let closure = ["block", "function_expression_body", "function_expression", "argument", "arguments"]
        XCTAssertEqual(intent("      ", nodeTypes: closure), .statement, "A closure body inside an argument")
        XCTAssertEqual(intent("cl", nodeTypes: file), .topLevel)
        XCTAssertEqual(intent("  ", nodeTypes: classBody), .topLevel)
        XCTAssertEqual(intent("  ", nodeTypes: ["extension_body", "extension_declaration", "program"]), .topLevel)
        XCTAssertEqual(intent("  ", nodeTypes: ["class_body", "mixin_declaration", "program"]), .topLevel)
        XCTAssertEqual(intent("cl"), .unknown, "No tree and nothing on the line")
    }

    func testCaseLabels() {
        XCTAssertEqual(intent("      case Col", nodeTypes: body), .caseLabel)
        XCTAssertEqual(intent("      case Color.red: ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("      default: ", nodeTypes: body), .statement)
    }

    // MARK: - Interpolation

    func testInterpolatedNamesAreVariableReferences() {
        XCTAssertEqual(intent("    print('Hi $na", nodeTypes: body), .variableReference)
        XCTAssertEqual(intent("    print('Hi $", nodeTypes: body), .variableReference)
        XCTAssertEqual(intent("    print(\"Hi$na", nodeTypes: body), .variableReference)
        XCTAssertEqual(intent("    print('Hi ${us", nodeTypes: body), .variableReference)
        XCTAssertEqual(intent("    print('Hi ${", nodeTypes: body), .variableReference)
    }

    func testCodeInsideAnInterpolationFollowsTheTokenRules() {
        XCTAssertEqual(intent("    print('Hi ${user.na", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("    print('Sum ${a + ", nodeTypes: body), .expression)
    }

    func testDollarSignsThatDoNotInterpolate() {
        XCTAssertEqual(intent("    print(r'Hi $na", nodeTypes: body), .string)
        XCTAssertEqual(intent("    print('Cost \\$na", nodeTypes: body), .string)
        XCTAssertEqual(intent("    final $na", nodeTypes: body), .declarationName, "`$` in an identifier")
    }

    // MARK: - Strings, comments, numbers

    func testStringsCommentsAndNumbers() {
        XCTAssertEqual(intent("    print('hello wo", nodeTypes: body), .string)
        XCTAssertEqual(intent("    print(\"hello", nodeTypes: body), .string)
        XCTAssertEqual(intent("    final s = '''multi", nodeTypes: body), .string)
        XCTAssertEqual(intent("    // note", nodeTypes: body), .comment)
        XCTAssertEqual(intent("/// Docs for", nodeTypes: file), .comment)
        XCTAssertEqual(intent("    x = 1; // why", nodeTypes: body), .comment)
        XCTAssertEqual(intent("    /* open", nodeTypes: body), .comment)
        XCTAssertEqual(intent("    x = 42", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("    x = 0x1F", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("    x = v1", nodeTypes: body), .expression)
    }

    func testStringsAndCommentsThatStartedOnAnEarlierLine() {
        let multiLineString = ["string_literal", "initialized_variable_definition"]
        XCTAssertEqual(intent("continued te", nodeTypes: multiLineString), .string)
        XCTAssertEqual(intent("   * more do", nodeTypes: ["comment", "program"]), .comment)
        XCTAssertEqual(intent("/// more do", nodeTypes: ["documentation_comment", "program"]), .comment)
        XCTAssertNotEqual(
            intent("    foo(na", nodeTypes: ["'", "string_literal", "arguments"]),
            .string,
            "On the opening quote of the next string, the cursor is in code"
        )
    }

    func testDirectiveURIs() {
        XCTAssertEqual(intent("import 'package:fl", nodeTypes: file), .includePath)
        XCTAssertEqual(intent("export 'src/", nodeTypes: file), .includePath)
        XCTAssertEqual(intent("part of '", nodeTypes: file), .includePath)
    }

    // MARK: - Other languages

    func testOtherLanguagesAreUnaffected() {
        let recognizer = CompletionIntentRecognizer { _ in ["compound_statement"] }
        func cIntent(_ line: String, _ prefix: String, _ language: String = "cpp") -> CompletionIntent {
            recognizer.recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: language)
        }
        XCTAssertEqual(cIntent("    c = 'a", "a"), .string)
        XCTAssertEqual(cIntent("    p->", ""), .memberAccess)
        XCTAssertEqual(cIntent("    int va", "va"), .declarationName)
        XCTAssertEqual(cIntent("    a?.", ""), .memberAccess, "C reads `?` then `.`, as before")
    }
}
