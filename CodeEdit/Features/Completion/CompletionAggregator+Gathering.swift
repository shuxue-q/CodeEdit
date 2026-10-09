//
//  CompletionAggregator+Gathering.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView

extension CompletionAggregator {
    // MARK: - Fan-out with per-provider deadlines

    /// One provider's in-flight request for the current completion session.
    @MainActor
    final class ProviderRun {
        let provider: any CompletionProvider
        var result: [CompletionCandidate]?
        /// Set once the window has opened without this run; receives the result when it arrives.
        var onLateResult: (([CompletionCandidate]) -> Void)?
        var task: Task<Void, Never>?

        init(provider: any CompletionProvider) {
            self.provider = provider
        }
    }

    /// Queries every provider concurrently.
    ///
    /// Providers with a zero `deadline` (language server, snippets) are awaited in full, as the
    /// language server was before the aggregator existed. Providers with a deadline (AI) never
    /// hold the window open once the others have answered: whatever they have returned by then is
    /// included, and a later answer is kept in `lateResults` for the next cursor move. When the
    /// blocking providers return nothing, a deadline provider is waited on for up to its deadline so
    /// the window can still open with its items alone.
    func gatherCandidates(
        context: CompletionContext,
        textView: TextViewController,
        generation: Int
    ) async -> [CompletionCandidate] {
        let runs = providers.map { ProviderRun(provider: $0) }
        for run in runs {
            run.task = Task { @MainActor in
                let result = await run.provider.candidates(for: context, textView: textView)
                run.result = result
                run.onLateResult?(result)
            }
        }
        let tasks = runs.compactMap(\.task)

        return await withTaskCancellationHandler {
            await self.collect(runs, generation: generation)
        } onCancel: {
            tasks.forEach { $0.cancel() }
        }
    }

    /// Awaits zero-deadline runs in full, then takes whatever the deadline runs have returned.
    func collect(_ runs: [ProviderRun], generation: Int) async -> [CompletionCandidate] {
        var gathered: [CompletionCandidate] = []
        func take(_ run: ProviderRun) {
            guard let result = run.result else { return }
            for candidate in result { candidateOwners[candidate.id] = run.provider }
            gathered.append(contentsOf: result)
        }

        for run in runs where run.provider.deadline == .zero {
            await run.task?.value
            take(run)
        }
        for run in runs where run.provider.deadline > .zero {
            if run.result == nil, gathered.isEmpty, let task = run.task {
                await Self.wait(for: task, upTo: run.provider.deadline)
            }
            if run.result != nil {
                take(run)
            } else {
                let provider = run.provider
                run.onLateResult = { [weak self] result in
                    guard let self, self.requestGeneration == generation, !result.isEmpty else { return }
                    self.lateResults.append((provider, result))
                }
            }
        }
        return gathered
    }

    /// The identifiers of the document, or none if tokenizing takes longer than 150 ms.
    func identifiers(from task: Task<[String: Int], Never>) async -> Set<String> {
        let words = await withTaskGroup(of: [String: Int]?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(150))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return words.map { Set($0.keys) } ?? []
    }

    /// Waits for `task` to finish or for `duration` to elapse, whichever comes first.
    private static func wait(for task: Task<Void, Never>, upTo duration: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: duration) }
            await group.next()
            group.cancelAll()
        }
    }
}
