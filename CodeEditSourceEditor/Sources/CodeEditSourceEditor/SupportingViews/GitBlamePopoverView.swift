//
//  GitBlamePopoverView.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import SwiftUI

/// Information about the last git change for a line.
public struct GitBlameLineInfo: Equatable {
    public let commitHash: String
    public let author: String
    public let authorEmail: String
    public let date: Date
    public let summary: String
    public let lineContent: String

    public init(
        commitHash: String,
        author: String,
        authorEmail: String = "",
        date: Date,
        summary: String,
        lineContent: String = ""
    ) {
        self.commitHash = commitHash
        self.author = author
        self.authorEmail = authorEmail
        self.date = date
        self.summary = summary
        self.lineContent = lineContent
    }
}

/// A SwiftUI view displaying git commit information for a line.
public struct GitBlamePopoverView: View {
    public let info: GitBlameLineInfo
    public let onClose: () -> Void

    public init(info: GitBlameLineInfo, onClose: @escaping () -> Void = {}) {
        self.info = info
        self.onClose = onClose
    }

    private var isUncommitted: Bool {
        info.commitHash.isEmpty || info.commitHash.allSatisfy { $0 == "0" }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .imageScale(.large)
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.author)
                        .font(.headline)
                    Text(info.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isUncommitted {
                    Button(
                        action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info.commitHash, forType: .string)
                        },
                        label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text(String(info.commitHash.prefix(7)))
                            }
                            .font(.caption.monospaced())
                        }
                    )
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy commit hash")
                } else {
                    Text("Uncommitted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }

            Divider()

            Text(info.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 380)
    }
}
