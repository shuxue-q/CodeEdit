//
//  DAPTypes.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

// Strongly-typed Codable models for the Debug Adapter Protocol commands and
// events CodeEdit uses. Instances are encoded into / decoded from `JSONValue`
// payloads via `JSONValue.encoding(_:)` and `JSONValue.decoded(_:)`.

// MARK: - Request Arguments

/// Arguments for the `initialize` request.
struct InitializeRequestArguments: Codable, Sendable {
    let adapterID: String
    let pathFormat: String
    let linesStartAt1: Bool
    let columnsStartAt1: Bool
    let supportsVariableType: Bool?

    init(adapterID: String, supportsVariableType: Bool? = true) {
        self.adapterID = adapterID
        self.pathFormat = "path"
        self.linesStartAt1 = true
        self.columnsStartAt1 = true
        self.supportsVariableType = supportsVariableType
    }
}

/// Arguments for the `launch` request.
struct LaunchRequestArguments: Codable, Sendable {
    let program: String
    let args: [String]
    let cwd: String
    let env: [String: String]?
    let stopOnEntry: Bool

    init(
        program: String,
        args: [String] = [],
        cwd: String,
        env: [String: String]? = nil,
        stopOnEntry: Bool = false
    ) {
        self.program = program
        self.args = args
        self.cwd = cwd
        self.env = env
        self.stopOnEntry = stopOnEntry
    }
}

/// A source file reference used by breakpoint and stack frame messages.
struct DAPSource: Codable, Sendable {
    let name: String?
    /// The absolute path of the source file. Optional because stack frames may
    /// reference sources that have no on-disk path.
    let path: String?

    init(name: String? = nil, path: String?) {
        self.name = name
        self.path = path
    }
}

/// A single breakpoint location within a source file.
struct DAPSourceBreakpoint: Codable, Sendable {
    let line: Int
    let column: Int?

    init(line: Int, column: Int? = nil) {
        self.line = line
        self.column = column
    }
}

/// Arguments for the `setBreakpoints` request.
struct SetBreakpointsArguments: Codable, Sendable {
    let source: DAPSource
    let breakpoints: [DAPSourceBreakpoint]
    let sourceModified: Bool?

    init(source: DAPSource, breakpoints: [DAPSourceBreakpoint], sourceModified: Bool? = nil) {
        self.source = source
        self.breakpoints = breakpoints
        self.sourceModified = sourceModified
    }
}

/// Arguments for the `configurationDone` request (empty).
struct ConfigurationDoneArguments: Codable, Sendable {}

/// Arguments for requests that only take a thread id (`continue`, `next`,
/// `stepIn`, `stepOut`, `pause`).
struct ThreadIdArguments: Codable, Sendable {
    let threadId: Int
}

/// Arguments for the `stackTrace` request.
struct StackTraceArguments: Codable, Sendable {
    let threadId: Int
    let startFrame: Int?
    let levels: Int?

    init(threadId: Int, startFrame: Int? = nil, levels: Int? = nil) {
        self.threadId = threadId
        self.startFrame = startFrame
        self.levels = levels
    }
}

/// Arguments for the `scopes` request.
struct ScopesArguments: Codable, Sendable {
    let frameId: Int
}

/// Arguments for the `variables` request.
struct VariablesArguments: Codable, Sendable {
    let variablesReference: Int
}

/// Arguments for the `evaluate` request.
struct EvaluateArguments: Codable, Sendable {
    let expression: String
    let frameId: Int?
    let context: String

    init(expression: String, frameId: Int? = nil, context: String = "watch") {
        self.expression = expression
        self.frameId = frameId
        self.context = context
    }
}

/// Arguments for the `disconnect` request.
struct DisconnectArguments: Codable, Sendable {
    let terminateDebuggee: Bool

    init(terminateDebuggee: Bool = true) {
        self.terminateDebuggee = terminateDebuggee
    }
}

// MARK: - Response Bodies

/// Adapter capabilities reported in the `initialize` response.
struct Capabilities: Codable, Sendable {
    let supportsConfigurationDoneRequest: Bool?
    let supportsEvaluateForHovers: Bool?
    let supportsSetVariable: Bool?
    let supportsTerminateRequest: Bool?
    let supportsStepBack: Bool?

    init(
        supportsConfigurationDoneRequest: Bool? = nil,
        supportsEvaluateForHovers: Bool? = nil,
        supportsSetVariable: Bool? = nil,
        supportsTerminateRequest: Bool? = nil,
        supportsStepBack: Bool? = nil
    ) {
        self.supportsConfigurationDoneRequest = supportsConfigurationDoneRequest
        self.supportsEvaluateForHovers = supportsEvaluateForHovers
        self.supportsSetVariable = supportsSetVariable
        self.supportsTerminateRequest = supportsTerminateRequest
        self.supportsStepBack = supportsStepBack
    }
}

/// The body of the `initialize` response.
typealias InitializeResponse = Capabilities

/// A breakpoint as reported (verified or not) by the adapter.
struct DAPBreakpoint: Codable, Sendable {
    let verified: Bool
    let line: Int?
    let message: String?
}

/// The body of the `setBreakpoints` response.
struct SetBreakpointsResponse: Codable, Sendable {
    let breakpoints: [DAPBreakpoint]
}

/// A thread in the debuggee process.
struct DAPThread: Codable, Sendable {
    let id: Int
    let name: String
}

/// The body of the `threads` response.
struct ThreadsResponse: Codable, Sendable {
    let threads: [DAPThread]
}

/// A single stack frame.
struct DAPStackFrame: Codable, Sendable {
    let id: Int
    let name: String
    let source: DAPSource?
    let line: Int
    let column: Int
}

/// The body of the `stackTrace` response.
struct StackTraceResponse: Codable, Sendable {
    let stackFrames: [DAPStackFrame]
}

/// A variable scope of a stack frame.
struct DAPScope: Codable, Sendable {
    let name: String
    let variablesReference: Int
    let expensive: Bool?
}

/// The body of the `scopes` response.
struct ScopesResponse: Codable, Sendable {
    let scopes: [DAPScope]
}

/// A variable (or child of a structured variable) in the debuggee.
struct DAPVariable: Codable, Sendable {
    let name: String
    let value: String
    let type: String?
    let variablesReference: Int
}

/// The body of the `variables` response.
struct VariablesResponse: Codable, Sendable {
    let variables: [DAPVariable]
}

/// The body of the `continue` response.
struct ContinueResponse: Codable, Sendable {
    let allThreadsContinued: Bool?
}

/// The body of the `evaluate` response.
struct EvaluateResponse: Codable, Sendable {
    let result: String
    let type: String?
    let variablesReference: Int
}

// MARK: - Event Bodies

/// The body of the `stopped` event.
struct StoppedEventBody: Codable, Sendable {
    let reason: String
    let threadId: Int?
    let allThreadsStopped: Bool?
}

/// The body of the `continued` event.
struct ContinuedEventBody: Codable, Sendable {
    let threadId: Int
    let allThreadsContinued: Bool?
}

/// The body of the `output` event.
struct OutputEventBody: Codable, Sendable {
    let category: String?
    let output: String
}

/// The body of the `terminated` event. Kept loose because adapters may attach
/// implementation-specific payloads.
struct TerminatedEventBody: Codable, Sendable {
    let restart: JSONValue?
}

/// The body of the `exited` event.
struct ExitedEventBody: Codable, Sendable {
    let exitCode: Int
}
