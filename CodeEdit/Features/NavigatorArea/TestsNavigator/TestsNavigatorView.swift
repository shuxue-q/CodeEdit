//
//  TestsNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import SwiftUI
import CodeEditSourceEditor

/// The Tests navigator: an Xcode-style outline of the XCTest and swift-testing
/// declarations discovered in the workspace, grouped file ▸ suite ▸ test case.
///
/// Selecting a row opens the file in the workspace editor at the declaration's
/// line. This navigator only discovers and jumps to tests; it does not run them.
struct TestsNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @StateObject private var viewModel = TestsNavigatorViewModel()
    @State private var filter: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if filteredFiles.isEmpty {
                CEContentUnavailableView(
                    "No Tests",
                    description: viewModel.files.isEmpty
                        ? "No XCTest or swift-testing declarations were found in this workspace."
                        : "No tests match the current filter.",
                    systemImage: "checkmark.diamond"
                ) {
                    Button("Refresh") {
                        Task { await viewModel.scan(workspace: workspace) }
                    }
                }
            } else {
                testList
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
                    .help("Show tests with matching names")
                },
                trailingAccessories: {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.scan(workspace: workspace)
        }
    }

    private var testList: some View {
        List {
            ForEach(filteredFiles) { file in
                Section {
                    ForEach(file.suites) { suite in
                        TestsNavigatorSuiteRow(file: file, suite: suite) { line in
                            open(file: file, line: line)
                        }
                    }
                } header: {
                    fileHeader(file)
                }
            }
        }
        .listStyle(.inset)
    }

    private func fileHeader(_ file: DiscoveredTestFile) -> some View {
        HStack(spacing: 6) {
            Text(file.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(file: file, line: 1)
        }
        .accessibilityIdentifier("TestsNavigatorFileHeader")
    }

    // MARK: - Filtering

    /// Files matching the current filter. A file matches when its name matches or
    /// when any of its suites (or their test cases) match; suites are kept when
    /// their own name matches or when they contain matching test cases.
    private var filteredFiles: [DiscoveredTestFile] {
        guard !filter.isEmpty else { return viewModel.files }
        return viewModel.files.compactMap { file in
            if file.fileName.localizedCaseInsensitiveContains(filter) { return file }
            let suites = file.suites.compactMap { suite -> DiscoveredTestSuite? in
                if suite.name.localizedCaseInsensitiveContains(filter) { return suite }
                let tests = suite.tests.filter {
                    $0.name.localizedCaseInsensitiveContains(filter)
                }
                guard !tests.isEmpty else { return nil }
                var suite = suite
                suite.tests = tests
                return suite
            }
            guard !suites.isEmpty else { return nil }
            var file = file
            file.suites = suites
            return file
        }
    }

    // MARK: - Navigation

    /// Opens `file` in the workspace editor and moves the cursor to `line`.
    /// Both the parser's line numbers and ``CursorPosition`` are 1-indexed.
    private func open(file: DiscoveredTestFile, line: Int) {
        guard let fileItem = workspace.workspaceFileManager?.getFile(
            file.fileURL.path,
            createIfNotFound: true
        ) else {
            return
        }
        workspace.editorManager?.openTab(item: fileItem)
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [
            CursorPosition(line: max(line, 1), column: 1)
        ]
    }
}

/// A test suite row with a default-expanded disclosure group of its test cases.
private struct TestsNavigatorSuiteRow: View {
    let file: DiscoveredTestFile
    let suite: DiscoveredTestSuite
    let onSelect: (Int) -> Void

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(suite.tests) { test in
                TestsNavigatorRow(name: test.name, line: test.line, prominent: false) {
                    onSelect(test.line)
                }
            }
        } label: {
            TestsNavigatorRow(name: suite.name, line: suite.line, prominent: true) {
                onSelect(suite.line)
            }
        }
    }
}

/// A single tappable row showing a suite or test case name and its line number.
private struct TestsNavigatorRow: View {
    let name: String
    let line: Int
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(prominent ? .system(size: 12, weight: .semibold) : .system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(line)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityIdentifier(prominent ? "TestsNavigatorSuiteRow" : "TestsNavigatorTestRow")
    }
}
