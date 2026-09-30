//
//  ProjectSettingsControls.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// A text field for a file or folder path with a "Choose…" button that opens a panel.
struct ProjectPathField: View {
    let title: String
    @Binding var path: String
    var prompt: String = ""
    var choosesDirectories = false
    /// Where the open panel starts, and what relative paths are shown against.
    var baseDirectory: URL?
    /// Stores chosen paths inside ``baseDirectory`` relative to it.
    var prefersRelativePaths = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: $path, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Choose…", action: choose)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !choosesDirectories
        panel.canChooseDirectories = choosesDirectories
        panel.canCreateDirectories = choosesDirectories
        panel.allowsMultipleSelection = false
        panel.directoryURL = baseDirectory
        panel.message = "Choose \(title.lowercased())"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = displayPath(for: url)
    }

    private func displayPath(for url: URL) -> String {
        let chosen = url.standardizedFileURL.path
        guard prefersRelativePaths, let base = baseDirectory?.standardizedFileURL.path else { return chosen }
        if chosen == base { return "." }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return chosen.hasPrefix(prefix) ? String(chosen.dropFirst(prefix.count)) : chosen
    }
}

/// Edits an ordered list of switchable name/value pairs, such as CMake definitions or
/// environment variables.
struct KeyValueListEditor: View {
    @Binding var rows: [CMakeProjectSettings.KeyValue]
    var namePlaceholder = "Name"
    var valuePlaceholder = "Value"
    var emptyText = "No Values"
    /// Splits a `-DNAME=VALUE` entered as a name into name and value when it is committed.
    var splitsDefinitions = false

    @State private var selection: CMakeProjectSettings.KeyValue.ID?
    @FocusState private var focusedRow: CMakeProjectSettings.KeyValue.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 16)
                Text("Name").frame(width: 220, alignment: .leading)
                Text("Value").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            List(selection: $selection) {
                ForEach(rows) { row in
                    rowView(row.id)
                        .tag(row.id)
                }
            }
            .frame(minHeight: 88)
            .overlay {
                if rows.isEmpty {
                    Text(emptyText).foregroundStyle(.secondary)
                }
            }
            .actionBar {
                Button {
                    let row = CMakeProjectSettings.KeyValue()
                    rows.append(row)
                    selection = row.id
                    // Focus once the new row's field exists.
                    DispatchQueue.main.async { focusedRow = row.id }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add")
                .accessibilityLabel("Add")
                Divider()
                Button {
                    removeSelection()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                .help("Remove")
                .accessibilityLabel("Remove")
            }
            .onDeleteCommand(perform: removeSelection)
        }
        .onChange(of: focusedRow) { oldRow, _ in
            if let oldRow { splitDefinition(oldRow) }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowView(_ id: CMakeProjectSettings.KeyValue.ID) -> some View {
        HStack(spacing: 8) {
            Toggle("Enabled", isOn: binding(id, \.isEnabled, default: true))
                .toggleStyle(.checkbox)
                .labelsHidden()
            TextField("Name", text: binding(id, \.name, default: ""), prompt: Text(namePlaceholder))
                .labelsHidden()
                .focused($focusedRow, equals: id)
                .onSubmit { splitDefinition(id) }
                .font(.system(.body, design: .monospaced))
                .frame(width: 220)
            TextField("Value", text: binding(id, \.value, default: ""), prompt: Text(valuePlaceholder))
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
        }
        .autocorrectionDisabled()
        .textFieldStyle(.plain)
    }

    /// Looks rows up by id instead of index so removing a row while a field in it is being
    /// edited cannot read past the end of the array.
    private func binding<Value>(
        _ id: CMakeProjectSettings.KeyValue.ID,
        _ keyPath: WritableKeyPath<CMakeProjectSettings.KeyValue, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding {
            rows.first { $0.id == id }?[keyPath: keyPath] ?? defaultValue
        } set: { newValue in
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index][keyPath: keyPath] = newValue
        }
    }

    /// Turns a committed `-DNAME=VALUE` name into separate name and value, keeping any value
    /// already entered. Runs on commit rather than per keystroke, while the field editor still
    /// owns the text.
    private func splitDefinition(_ id: CMakeProjectSettings.KeyValue.ID) {
        guard splitsDefinitions, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let name = rows[index].name.trimmingCharacters(in: .whitespaces)
        guard name.hasPrefix("-D"), let equals = name.firstIndex(of: "=") else { return }
        rows[index].name = String(name[name.index(name.startIndex, offsetBy: 2)..<equals])
        if rows[index].value.isEmpty {
            rows[index].value = String(name[name.index(after: equals)...])
        }
    }

    private func removeSelection() {
        guard let selection else { return }
        rows.removeAll { $0.id == selection }
        self.selection = nil
    }
}

/// Explains that a selected configure preset overrides toolchain and build settings.
struct PresetOverrideNotice: View {
    let preset: CMakePreset?

    var body: some View {
        if let preset {
            Section {
                Label {
                    Text("Configure preset “\(preset.title)” is selected. It controls the generator, build "
                         + "directory, compilers, build type, and C++ standard, so those settings are "
                         + "unavailable. CMake variables and run settings still apply.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
