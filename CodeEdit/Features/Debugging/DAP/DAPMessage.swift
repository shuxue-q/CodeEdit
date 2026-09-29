//
//  DAPMessage.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

/// A free-form JSON value used for Debug Adapter Protocol payloads.
///
/// DAP message bodies are open-ended, so arguments and bodies that do not have a
/// strongly-typed model are represented with this type.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// The associated string, or `nil` if this value is not a string.
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The associated number truncated to an integer, or `nil` if this value is not a number.
    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    /// The associated boolean, or `nil` if this value is not a boolean.
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The associated array, or `nil` if this value is not an array.
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// The associated object, or `nil` if this value is not an object.
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// Returns the member of an object value for the given key.
    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Returns the element of an array value at the given index.
    subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Encodes any `Encodable` value into a ``JSONValue`` via `JSONEncoder`/`JSONDecoder`.
    static func encoding<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Decodes this value into a strongly-typed `Decodable` model.
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// A message on the Debug Adapter Protocol wire.
///
/// Every DAP message is a JSON object with a `seq` sequence number and a `type`
/// discriminator of `"request"`, `"response"`, or `"event"`.
enum DAPMessage: Codable, Sendable {
    case request(DAPRequest)
    case response(DAPResponse)
    case event(DAPEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "request":
            self = .request(try DAPRequest(from: decoder))
        case "response":
            self = .response(try DAPResponse(from: decoder))
        case "event":
            self = .event(try DAPEvent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown DAP message type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let request):
            try request.encode(to: encoder)
        case .response(let response):
            try response.encode(to: encoder)
        case .event(let event):
            try event.encode(to: encoder)
        }
    }
}

/// A DAP request message. Requests flow from client to adapter; adapters may also
/// send reverse requests to the client.
struct DAPRequest: Codable, Sendable {
    let seq: Int
    let command: String
    var arguments: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case seq, type, command, arguments
    }

    init(seq: Int, command: String, arguments: JSONValue? = nil) {
        self.seq = seq
        self.command = command
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent(JSONValue.self, forKey: .arguments)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode("request", forKey: .type)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(arguments, forKey: .arguments)
    }
}

/// A DAP response message, sent by the adapter in reply to a request.
struct DAPResponse: Codable, Sendable {
    let seq: Int
    /// The `seq` of the request this response answers (`request_seq` on the wire).
    let requestSeq: Int
    let success: Bool
    let command: String
    let message: String?
    let body: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case seq, type, success, command, message, body
        case requestSeq = "request_seq"
    }

    init(
        seq: Int,
        requestSeq: Int,
        success: Bool,
        command: String,
        message: String? = nil,
        body: JSONValue? = nil
    ) {
        self.seq = seq
        self.requestSeq = requestSeq
        self.success = success
        self.command = command
        self.message = message
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        requestSeq = try container.decode(Int.self, forKey: .requestSeq)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        command = try container.decode(String.self, forKey: .command)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        body = try container.decodeIfPresent(JSONValue.self, forKey: .body)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode("response", forKey: .type)
        try container.encode(requestSeq, forKey: .requestSeq)
        try container.encode(success, forKey: .success)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(body, forKey: .body)
    }

    /// Decodes the response `body` into a strongly-typed model, if a body is present.
    func typedBody<T: Decodable>(_ type: T.Type) -> T? {
        guard let body else { return nil }
        return try? body.decoded(type)
    }
}

/// A DAP event message, sent asynchronously by the adapter.
struct DAPEvent: Codable, Sendable {
    let seq: Int
    let event: String
    let body: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case seq, type, event, body
    }

    init(seq: Int, event: String, body: JSONValue? = nil) {
        self.seq = seq
        self.event = event
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        event = try container.decode(String.self, forKey: .event)
        body = try container.decodeIfPresent(JSONValue.self, forKey: .body)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode("event", forKey: .type)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(body, forKey: .body)
    }

    /// Decodes the event `body` into a strongly-typed model, if a body is present.
    func typedBody<T: Decodable>(_ type: T.Type) -> T? {
        guard let body else { return nil }
        return try? body.decoded(type)
    }
}
