//
//  TaskRace.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Hands one value, or `nil`, to a continuation exactly once, whichever of two racers gets there first.
private final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Waits for `task` to finish, but for no longer than `duration`.
///
/// Unlike a task group racing the task against a sleep, this returns as soon as the time is up even if
/// `task` ignores cancellation or is blocked in a request that cannot be cancelled: the group would
/// wait for such a child before returning. `task` keeps running after a timeout.
/// - Returns: The task's value, or `nil` when `duration` elapsed first.
func awaitValue<Value: Sendable>(of task: Task<Value, Never>, upTo duration: Duration) async -> Value? {
    await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
        let gate = OneShotContinuation(continuation)
        Task { gate.resume(await task.value) }
        Task {
            try? await Task.sleep(for: duration)
            gate.resume(nil)
        }
    }
}
