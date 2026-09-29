//
//  ReportsNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/22/26.
//

import SwiftUI

/// The report navigator: an Xcode-style history of past builds, debug sessions, and
/// tasks for the current workspace, with an (unavailable) Xcode Cloud section.
struct ReportsNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var selectedSection = 0
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(
                $selectedSection,
                options: ["Local", "Cloud"],
                prominent: true
            )
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .padding(.horizontal, 8)
            Divider()
            if selectedSection == 0 {
                localContent
            } else {
                CEContentUnavailableView(
                    "No Cloud Reports",
                    description: "Xcode Cloud reports are not available in CodeEdit.",
                    systemImage: "cloud"
                )
            }
            NavigatorFilterView(
                text: $filter,
                menu: { EmptyView() },
                leadingAccessories: {
                    Image(
                        systemName: filter.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                    )
                    .foregroundStyle(
                        filter.isEmpty
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color(nsColor: .controlAccentColor)
                    )
                    .padding(.leading, 4)
                    .help("Show reports with matching title")
                },
                trailingAccessories: { EmptyView() }
            )
        }
    }

    @ViewBuilder private var localContent: some View {
        if let reportStore = workspace.reportStore {
            ReportsNavigatorListView(reportStore: reportStore, filter: filter)
        } else {
            CEContentUnavailableView(
                "No Reports",
                description: "Builds, debug sessions, and tasks will appear here.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }
}

/// The local reports list, observed directly so new records refresh the navigator.
private struct ReportsNavigatorListView: View {
    @ObservedObject var reportStore: ReportStore
    let filter: String

    @State private var expanded: Set<UUID> = []

    private var filteredRecords: [ReportRecord] {
        guard !filter.isEmpty else { return reportStore.records }
        return reportStore.records.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        if filteredRecords.isEmpty {
            CEContentUnavailableView(
                "No Reports",
                description: "Builds, debug sessions, and tasks will appear here.",
                systemImage: "doc.text.magnifyingglass"
            )
        } else {
            List(filteredRecords) { record in
                recordRow(record)
                    .contextMenu {
                        Button("Delete Report") {
                            reportStore.remove(record)
                        }
                        Button("Clear All Reports") {
                            reportStore.clearAll()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ record: ReportRecord) -> some View {
        if record.diagnostics.isEmpty && (record.logExcerpt?.isEmpty ?? true) {
            recordLabel(record)
        } else {
            DisclosureGroup(isExpanded: expansionBinding(for: record.id)) {
                recordDetail(record)
            } label: {
                recordLabel(record)
            }
        }
    }

    private func recordLabel(_ record: ReportRecord) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: record.kind))
                .foregroundStyle(record.status == .failed ? Color.red : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .lineLimit(1)
                Text(formattedDate(record.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.errorCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.octagon.fill")
                    Text("\(record.errorCount)")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
            if record.warningCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(record.warningCount)")
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func recordDetail(_ record: ReportRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let duration = record.duration {
                Text("Duration: \(formattedDuration(duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !record.diagnostics.isEmpty {
                DiagnosticsListView(diagnostics: record.diagnostics)
                    .frame(height: min(240, CGFloat(record.diagnostics.count) * 44 + 40))
            }
            if let log = record.logExcerpt, !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Presentation helpers

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }

    private func icon(for kind: ReportRecord.Kind) -> String {
        switch kind {
        case .build: return "hammer"
        case .run: return "play"
        case .debug: return "ant"
        case .task: return "gearshape"
        }
    }

    /// An Xcode-style report date: "Today, 09:02", "Yesterday, 09:02", then an
    /// absolute date.
    private func formattedDate(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(time)"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1f s", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d min %d s", minutes, seconds)
    }
}
