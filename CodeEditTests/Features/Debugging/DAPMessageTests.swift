//
//  DAPMessageTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/21/26.
//

import XCTest

@testable import CodeEdit

/// Unit tests for the Debug Adapter Protocol wire framing, `JSONValue`, and
/// `DAPMessage` decoding/encoding. These tests are purely synchronous and do
/// not launch any external process.
final class DAPMessageTests: XCTestCase {
    // MARK: - DAPMessageFramer

    /// A framed body survives a frame → append → nextMessage round trip.
    func testFramerRoundTrip() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"seq":1,"type":"request","command":"initialize"}"#.utf8)

        framer.append(DAPMessageFramer.frame(body))

        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// A header split across two appends is only yielded once complete.
    func testFramerHeaderSplitAcrossAppends() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"seq":2,"type":"event","event":"stopped"}"#.utf8)
        let framed = DAPMessageFramer.frame(body)
        // Split inside the "Content-Length" header (the header is 16+ bytes).
        let split = framed.index(framed.startIndex, offsetBy: 10)

        framer.append(Data(framed[..<split]))
        XCTAssertNil(framer.nextMessage())

        framer.append(Data(framed[split...]))
        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// A body split across two appends is only yielded once complete.
    func testFramerBodySplitAcrossAppends() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"seq":3,"type":"response","request_seq":1,"success":true,"command":"x"}"#.utf8)
        let framed = DAPMessageFramer.frame(body)
        let header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        // Split one byte into the body.
        let split = framed.index(framed.startIndex, offsetBy: header.count + 1)

        framer.append(Data(framed[..<split]))
        XCTAssertNil(framer.nextMessage())

        framer.append(Data(framed[split...]))
        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// Two messages appended at once are yielded one at a time, in order.
    func testFramerTwoMessagesInSingleAppend() {
        let framer = DAPMessageFramer()
        let first = Data(#"{"seq":1,"type":"request","command":"initialize"}"#.utf8)
        let second = Data(#"{"seq":2,"type":"event","event":"initialized"}"#.utf8)

        var combined = DAPMessageFramer.frame(first)
        combined.append(DAPMessageFramer.frame(second))
        framer.append(combined)

        XCTAssertEqual(framer.nextMessage(), first)
        XCTAssertEqual(framer.nextMessage(), second)
        XCTAssertNil(framer.nextMessage())
    }

    /// Additional header lines (e.g. `Content-Type`) are tolerated.
    func testFramerToleratesAdditionalHeaders() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"seq":4,"type":"event","event":"output"}"#.utf8)
        let header = "Content-Length: \(body.count)\r\n"
            + "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n"

        var data = Data(header.utf8)
        data.append(body)
        framer.append(data)

        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// The `Content-Length` header name is matched case-insensitively.
    func testFramerContentLengthIsCaseInsensitive() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"seq":5,"type":"event","event":"terminated"}"#.utf8)
        let header = "content-length: \(body.count)\r\n\r\n"

        var data = Data(header.utf8)
        data.append(body)
        framer.append(data)

        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// Appending empty data is a no-op.
    func testFramerEmptyAppend() {
        let framer = DAPMessageFramer()

        framer.append(Data())
        XCTAssertNil(framer.nextMessage())
    }

    /// A header terminator without `Content-Length` is skipped so the next frame is read.
    func testFramerSkipsHeaderMissingContentLength() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"ok":true}"#.utf8)
        var data = Data("Content-Type: text/plain\r\n\r\n".utf8)
        data.append(DAPMessageFramer.frame(body))
        framer.append(data)

        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// A negative `Content-Length` is skipped instead of trapping on a negative index.
    func testFramerSkipsNegativeContentLength() {
        let framer = DAPMessageFramer()
        let body = Data(#"{"ok":true}"#.utf8)
        var data = Data("Content-Length: -1\r\n\r\n".utf8)
        data.append(DAPMessageFramer.frame(body))
        framer.append(data)

        XCTAssertEqual(framer.nextMessage(), body)
        XCTAssertNil(framer.nextMessage())
    }

    /// Bytes with no header terminator past the cap are discarded, and a later frame still parses.
    func testFramerDropsUndelimitedBytesPastHeaderCap() {
        let framer = DAPMessageFramer()
        framer.append(Data(repeating: 0x41, count: 64 * 1024 + 1))
        XCTAssertNil(framer.nextMessage())

        let body = Data(#"{"ok":true}"#.utf8)
        framer.append(DAPMessageFramer.frame(body))
        XCTAssertEqual(framer.nextMessage(), body)
    }

    // MARK: - JSONValue

    /// Nested `JSONValue` trees round-trip through `JSONEncoder`/`JSONDecoder`.
    func testJSONValueRoundTrip() throws {
        let value: JSONValue = .object([
            "name": .string("demo"),
            "count": .number(42),
            "enabled": .bool(true),
            "nothing": .null,
            "tags": .array([.string("a"), .number(1.5)]),
            "nested": .object(["x": .bool(false)])
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(decoded, value)
    }

    /// Object and array subscripts expose members and elements.
    func testJSONValueSubscriptAccess() throws {
        let value: JSONValue = .object([
            "name": .string("demo"),
            "tags": .array([.string("a"), .null])
        ])

        XCTAssertEqual(value["name"]?.stringValue, "demo")
        XCTAssertNil(value["missing"])

        let tags = try XCTUnwrap(value["tags"]?.arrayValue)
        XCTAssertEqual(tags[0], .string("a"))
        XCTAssertEqual(tags[1], .null)
        XCTAssertEqual(value[0], nil)
    }

    // MARK: - DAPMessage decoding

    /// A raw JSON response decodes into `DAPMessage.response` with all fields,
    /// and its body decodes into a typed model.
    func testResponseDecoding() throws {
        let json = """
        {"seq":2,"type":"response","request_seq":1,"success":true,\
        "command":"initialize","body":{"supportsConfigurationDoneRequest":true}}
        """

        let message = try JSONDecoder().decode(DAPMessage.self, from: Data(json.utf8))
        guard case .response(let response) = message else {
            XCTFail("Expected a response message, got \(message)")
            return
        }

        XCTAssertEqual(response.seq, 2)
        XCTAssertEqual(response.requestSeq, 1)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.command, "initialize")

        let capabilities = try XCTUnwrap(response.typedBody(Capabilities.self))
        XCTAssertEqual(capabilities.supportsConfigurationDoneRequest, true)
    }

    /// A `stopped` event decodes and its typed body exposes reason and thread.
    func testStoppedEventDecoding() throws {
        let json = """
        {"seq":9,"type":"event","event":"stopped",\
        "body":{"reason":"breakpoint","threadId":7,"allThreadsStopped":true}}
        """

        let message = try JSONDecoder().decode(DAPMessage.self, from: Data(json.utf8))
        guard case .event(let event) = message else {
            XCTFail("Expected an event message, got \(message)")
            return
        }

        XCTAssertEqual(event.seq, 9)
        XCTAssertEqual(event.event, "stopped")

        let body = try XCTUnwrap(event.typedBody(StoppedEventBody.self))
        XCTAssertEqual(body.reason, "breakpoint")
        XCTAssertEqual(body.threadId, 7)
        XCTAssertEqual(body.allThreadsStopped, true)
    }

    /// A raw JSON request decodes into `DAPMessage.request`.
    func testRequestDecoding() throws {
        let json = """
        {"seq":1,"type":"request","command":"launch",\
        "arguments":{"program":"/tmp/a.out","stopOnEntry":false}}
        """

        let message = try JSONDecoder().decode(DAPMessage.self, from: Data(json.utf8))
        guard case .request(let request) = message else {
            XCTFail("Expected a request message, got \(message)")
            return
        }

        XCTAssertEqual(request.seq, 1)
        XCTAssertEqual(request.command, "launch")
        XCTAssertEqual(request.arguments?["program"]?.stringValue, "/tmp/a.out")
        XCTAssertEqual(request.arguments?["stopOnEntry"]?.boolValue, false)
    }

    // MARK: - Typed bodies

    /// A `variables` response body decodes into `VariablesResponse`, keeping
    /// non-zero `variablesReference` values for structured children.
    func testVariablesResponseTypedBody() throws {
        let json = """
        {"seq":6,"type":"response","request_seq":5,"success":true,"command":"variables",\
        "body":{"variables":[\
        {"name":"value","value":"21","type":"int","variablesReference":0},\
        {"name":"items","value":"[3]","type":"int[3]","variablesReference":12}\
        ]}}
        """

        let message = try JSONDecoder().decode(DAPMessage.self, from: Data(json.utf8))
        guard case .response(let response) = message else {
            XCTFail("Expected a response message, got \(message)")
            return
        }

        let body = try XCTUnwrap(response.typedBody(VariablesResponse.self))
        XCTAssertEqual(body.variables.count, 2)
        XCTAssertEqual(body.variables[0].name, "value")
        XCTAssertEqual(body.variables[0].value, "21")
        XCTAssertEqual(body.variables[1].name, "items")
        XCTAssertGreaterThan(body.variables[1].variablesReference, 0)
    }

    // MARK: - Encoding

    /// `InitializeRequestArguments` encodes with the expected DAP defaults.
    func testInitializeRequestArgumentsEncoding() throws {
        let arguments = InitializeRequestArguments(adapterID: "test")

        let encoded = try JSONValue.encoding(arguments)
        XCTAssertEqual(encoded["adapterID"]?.stringValue, "test")
        XCTAssertEqual(encoded["pathFormat"]?.stringValue, "path")
        XCTAssertEqual(encoded["linesStartAt1"]?.boolValue, true)
        XCTAssertEqual(encoded["columnsStartAt1"]?.boolValue, true)
        XCTAssertEqual(encoded["supportsVariableType"]?.boolValue, true)

        let roundTripped = try encoded.decoded(InitializeRequestArguments.self)
        XCTAssertEqual(roundTripped.adapterID, "test")
        XCTAssertEqual(roundTripped.pathFormat, "path")
        XCTAssertTrue(roundTripped.linesStartAt1)
    }
}
