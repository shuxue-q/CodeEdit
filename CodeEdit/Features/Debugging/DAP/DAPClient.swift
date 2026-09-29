//
//  DAPClient.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Darwin
import Foundation

/// Errors thrown by ``DAPClient``.
enum DAPError: Error, Equatable {
    /// The debug adapter process terminated while requests were in flight.
    case processTerminated
    /// The adapter answered a request with `success == false`.
    case requestFailed(command: String, message: String?)
    /// Request arguments could not be encoded to JSON.
    case encodingFailed
    /// A response body could not be decoded into the requested type.
    case invalidResponse
}

/// A Debug Adapter Protocol client that owns an `lldb-dap` child process and
/// speaks DAP over its stdin/stdout pipes.
///
/// Thread safety: all mutable state is guarded by a single lock, held only
/// inside short synchronous helpers so async methods never suspend while
/// holding it. There are no MainActor requirements; ``send(_:arguments:)-9k3w0``
/// and ``stop()`` may be called from any context.
final class DAPClient: @unchecked Sendable {
    /// Events (`stopped`, `output`, `terminated`, …) emitted by the adapter.
    ///
    /// The stream finishes when the adapter process terminates.
    let events: AsyncStream<DAPEvent>

    private let executableURL: URL
    private let lock = NSLock()
    /// Serializes stdin frames. Separate from ``lock`` so a blocking write cannot
    /// stall the stdout reader, and so request bytes cannot interleave.
    private let writeLock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var framer = DAPMessageFramer()
    private var nextSeq = 1
    private var pending: [Int: CheckedContinuation<DAPResponse, Error>] = [:]
    private let eventsContinuation: AsyncStream<DAPEvent>.Continuation

    /// Creates a client for the given `lldb-dap` executable. Does not launch it;
    /// call ``start()`` to spawn the process.
    init(executableURL: URL) {
        self.executableURL = executableURL
        var continuation: AsyncStream<DAPEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        // Safe: the closure above runs synchronously during AsyncStream.init.
        self.eventsContinuation = continuation
    }

    /// Launches the debug adapter process and begins reading its output.
    ///
    /// Does nothing if the process is already running.
    func start() throws {
        lock.lock()
        guard process == nil else {
            lock.unlock()
            return
        }
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process
        let stdin = stdinPipe.fileHandleForWriting
        // A closed pipe otherwise delivers SIGPIPE and kills the app.
        _ = fcntl(stdin.fileDescriptor, F_SETNOSIGPIPE, 1)
        stdinHandle = stdin
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        lock.unlock()

        // readabilityHandler fires on a private background queue. Empty
        // `availableData` means EOF, and the handle stays readable until the
        // handler is cleared, so leaving it installed spins a thread.
        stdoutHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.handleReadData(data)
        }
        stderrHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            self?.handleStderr(text)
        }
        process.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        do {
            try process.run()
        } catch {
            handleTermination()
            throw error
        }
    }

    /// Sends a request and waits for the adapter's response.
    ///
    /// - Parameters:
    ///   - command: The DAP command name (e.g. `"initialize"`, `"stackTrace"`).
    ///   - arguments: The command arguments, encoded into the request's `arguments` object.
    /// - Returns: The decoded response body, or `nil` if the response has no body.
    /// - Throws: ``DAPError/requestFailed(command:message:)`` if the adapter reports
    ///   failure, ``DAPError/processTerminated`` if the adapter dies while waiting,
    ///   ``DAPError/encodingFailed`` if the arguments cannot be encoded, or
    ///   ``DAPError/invalidResponse`` if the body does not match `Body`.
    @discardableResult
    func send<Arguments: Encodable, Body: Decodable>(
        _ command: String,
        arguments: Arguments?
    ) async throws -> Body? {
        let argumentsValue: JSONValue?
        if let arguments {
            do {
                argumentsValue = try JSONValue.encoding(arguments)
            } catch {
                throw DAPError.encodingFailed
            }
        } else {
            argumentsValue = nil
        }

        let request = DAPRequest(seq: reserveSeq(), command: command, arguments: argumentsValue)
        let framed: Data
        do {
            framed = DAPMessageFramer.frame(try JSONEncoder().encode(request))
        } catch {
            throw DAPError.encodingFailed
        }
        let response: DAPResponse = try await withCheckedThrowingContinuation { continuation in
            registerAndWrite(framed, seq: request.seq, continuation: continuation)
        }

        guard response.success else {
            throw DAPError.requestFailed(command: response.command, message: response.message)
        }
        guard let body = response.body else {
            return nil
        }
        do {
            return try body.decoded(Body.self)
        } catch {
            throw DAPError.invalidResponse
        }
    }

    /// Sends a request without arguments and waits for the response body.
    @discardableResult
    func send<Body: Decodable>(_ command: String) async throws -> Body? {
        try await send(command, arguments: nil as JSONValue?)
    }

    /// Sends a request whose response carries no body. Still throws if the
    /// adapter reports failure or dies while waiting.
    func send<Arguments: Encodable>(_ command: String, arguments: Arguments?) async throws {
        let _: JSONValue? = try await send(command, arguments: arguments)
    }

    /// Sends a request without arguments whose response carries no body.
    func send(_ command: String) async throws {
        let _: JSONValue? = try await send(command, arguments: nil as JSONValue?)
    }

    /// Asks the adapter to disconnect and terminates the process if it is still
    /// running afterwards.
    func stop() async {
        if isProcessRunning() {
            try? await send("disconnect", arguments: DisconnectArguments())
        }
        if let process = currentProcess(), process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Reading

    /// Feeds raw stdout bytes into the framer and dispatches every complete message.
    private func handleReadData(_ data: Data) {
        lock.lock()
        framer.append(data)
        var bodies: [Data] = []
        while let body = framer.nextMessage() {
            bodies.append(body)
        }
        lock.unlock()
        for body in bodies {
            dispatchMessage(body)
        }
    }

    private func dispatchMessage(_ body: Data) {
        let message: DAPMessage
        do {
            message = try JSONDecoder().decode(DAPMessage.self, from: body)
        } catch {
            NSLog("DAPClient: failed to decode message: \(error.localizedDescription)")
            return
        }
        switch message {
        case .response(let response):
            removePending(for: response.requestSeq)?.resume(returning: response)
        case .event(let event):
            eventsContinuation.yield(event)
        case .request(let request):
            respondUnsupported(to: request)
        }
    }

    /// Replies to reverse requests (e.g. `runInTerminal`) with a failure response.
    ///
    /// CodeEdit does not advertise `supportsRunInTerminalRequest`, so this is a
    /// safety net that keeps the adapter from hanging on an unanswered request.
    private func respondUnsupported(to request: DAPRequest) {
        NSLog("DAPClient: unsupported reverse request '\(request.command)', replying with failure")
        let response = DAPResponse(
            seq: reserveSeq(),
            requestSeq: request.seq,
            success: false,
            command: request.command,
            message: "Unsupported"
        )
        write(response)
    }

    /// Forwards adapter stderr to the event stream as synthetic `output` events.
    private func handleStderr(_ text: String) {
        let body: JSONValue = .object([
            "category": .string("stderr"),
            "output": .string(text)
        ])
        eventsContinuation.yield(DAPEvent(seq: 0, event: "output", body: body))
    }

    // MARK: - Lifecycle

    private func handleTermination() {
        lock.lock()
        let continuations = pending
        pending.removeAll()
        let stdout = stdoutHandle
        let stderr = stderrHandle
        let process = process
        stdoutHandle = nil
        stderrHandle = nil
        stdinHandle = nil
        self.process = nil
        lock.unlock()
        // Drop the handlers before releasing the handles. The dispatch source
        // retains the handle while a handler is installed.
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        process?.terminationHandler = nil
        for continuation in continuations.values {
            continuation.resume(throwing: DAPError.processTerminated)
        }
        eventsContinuation.finish()
    }
}

extension DAPClient {
    // MARK: - Writing

    private func write<Message: Encodable>(_ message: Message) {
        let framed: Data
        do {
            framed = DAPMessageFramer.frame(try JSONEncoder().encode(message))
        } catch {
            NSLog("DAPClient: failed to encode message: \(error.localizedDescription)")
            return
        }
        do {
            try writeFrame(framed)
        } catch {
            NSLog("DAPClient: failed to write message: \(error.localizedDescription)")
        }
    }

    /// Registers `continuation` only while the process is alive, then writes the
    /// frame. A failed write, or a process that has already exited, resumes the
    /// continuation instead of leaving `send` suspended.
    private func registerAndWrite(
        _ framed: Data,
        seq: Int,
        continuation: CheckedContinuation<DAPResponse, Error>
    ) {
        lock.lock()
        let running = process?.isRunning == true && stdinHandle != nil
        if running {
            pending[seq] = continuation
        }
        lock.unlock()
        guard running else {
            continuation.resume(throwing: DAPError.processTerminated)
            return
        }
        do {
            try writeFrame(framed)
        } catch {
            if let pendingContinuation = removePending(for: seq) {
                pendingContinuation.resume(throwing: DAPError.processTerminated)
            }
        }
    }

    /// Writes one complete frame. `F_SETNOSIGPIPE` makes a closed stdin return
    /// `EPIPE` instead of raising `SIGPIPE`.
    private func writeFrame(_ framed: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        lock.lock()
        let handle = stdinHandle
        let running = process?.isRunning == true
        lock.unlock()
        guard running, let handle else {
            throw DAPError.processTerminated
        }
        try handle.write(contentsOf: framed)
    }

    // MARK: - Locked State Access

    private func isProcessRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    private func currentProcess() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return process
    }

    private func reserveSeq() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let seq = nextSeq
        nextSeq += 1
        return seq
    }

    private func removePending(for seq: Int) -> CheckedContinuation<DAPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return pending.removeValue(forKey: seq)
    }
}
