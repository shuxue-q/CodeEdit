//
//  CompletionCandidate.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// A single completion candidate gathered from a ``CompletionProvider``, before filtering, ranking,
/// and presentation.
struct CompletionCandidate {
    /// A stable identity for this candidate within one completion session, used to route apply/resolve
    /// calls back to the provider that produced it.
    let id: String
    /// The text shown in the suggestion row.
    let label: String
    /// The text matched against the typed prefix. Falls back to `label` when empty.
    let filterText: String
    /// The server- (or provider-) supplied sort key, when there is one.
    var sortText: String?
    /// A server-supplied relevance score, when there is one.
    var score: Double?
    /// The symbol kind, used for the row's icon and for context-based ranking.
    let kind: LSPCompletionCategory
    /// Which provider kind produced this candidate. Determines the row's trailing badge.
    var source: CompletionSource
    /// Secondary text shown after the label.
    var detail: String?
    /// Documentation shown in the preview pane.
    var documentation: String?
    /// Whether the symbol is marked deprecated.
    var deprecated: Bool
    /// What is needed to apply this candidate.
    let payload: CompletionPayload
    /// Other sources this candidate absorbed during deduplication. Informational only.
    var mergedSources: Set<CompletionSource>

    /// Creates a candidate. Every field but `id`, `label`, `filterText`, `kind`, `source`, and
    /// `payload` has a convenience default.
    init(
        id: String,
        label: String,
        filterText: String,
        sortText: String? = nil,
        score: Double? = nil,
        kind: LSPCompletionCategory,
        source: CompletionSource,
        detail: String? = nil,
        documentation: String? = nil,
        deprecated: Bool = false,
        payload: CompletionPayload,
        mergedSources: Set<CompletionSource> = []
    ) {
        self.id = id
        self.label = label
        self.filterText = filterText
        self.sortText = sortText
        self.score = score
        self.kind = kind
        self.source = source
        self.detail = detail
        self.documentation = documentation
        self.deprecated = deprecated
        self.payload = payload
        self.mergedSources = mergedSources
    }
}
