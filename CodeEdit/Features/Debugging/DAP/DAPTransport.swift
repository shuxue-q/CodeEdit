//
//  DAPTransport.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

/// Incremental parser for the Debug Adapter Protocol wire framing.
///
/// DAP messages are sent as a `Content-Length: <n>` header block terminated by
/// `\r\n\r\n`, followed by exactly `n` bytes of JSON. This type buffers arbitrary
/// chunks of incoming data and yields complete JSON bodies one at a time.
///
/// Not thread-safe; callers must serialize access (see ``DAPClient``, which
/// guards its framer with a lock).
final class DAPMessageFramer {
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
    /// A header with no terminator past this size is discarded. DAP headers are
    /// a few dozen bytes; an unbounded wait would pin memory if stdout is not DAP.
    private static let maxHeaderBytes = 64 * 1024

    private var buffer = Data()

    /// Appends raw bytes received from the adapter to the internal buffer.
    func append(_ data: Data) {
        buffer.append(data)
    }

    /// Returns the JSON body of the next complete message, if one is available.
    ///
    /// Consumes the message's bytes from the buffer. Returns `nil` when the
    /// buffered data is incomplete (a partial header or a partial body), leaving
    /// the buffer untouched so more bytes can be appended. A header terminator
    /// whose `Content-Length` is missing, not an integer, or negative is dropped
    /// so a non-protocol write cannot stall every later frame.
    func nextMessage() -> Data? {
        while true {
            guard let headerEnd = buffer.range(of: Self.headerTerminator) else {
                if buffer.count > Self.maxHeaderBytes {
                    buffer.removeAll()
                }
                return nil
            }
            let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
            guard let header = String(bytes: headerData, encoding: .utf8),
                  let contentLength = Self.contentLength(from: header),
                  contentLength >= 0 else {
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
                continue
            }
            let bodyStart = headerEnd.upperBound
            let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
            guard available >= contentLength else {
                return nil
            }
            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
            let body = Data(buffer[bodyStart..<bodyEnd])
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
            return body
        }
    }

    /// Wraps a JSON body in the `Content-Length` framing for sending.
    static func frame(_ body: Data) -> Data {
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        return framed
    }

    /// Extracts the `Content-Length` value from a header block, tolerating
    /// additional headers such as `Content-Type`.
    private static func contentLength(from header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name.caseInsensitiveCompare("Content-Length") == .orderedSame else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
