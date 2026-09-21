//
//  PaneToolbar.swift
//  CodeEdit
//
//  Created by Austin Condiff on 5/31/23.
//

import SwiftUI

struct PaneToolbar<Content: View>: View {
    @ViewBuilder var content: Content
    @EnvironmentObject var model: UtilityAreaTabViewModel
    @Environment(\.paneArea)
    var paneArea: PaneArea?

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            if shouldShowLeadingSection() {
                PaneToolbarSection {
                    Spacer()
                        .frame(width: 24)
                }
                .opacity(0)
            }
            content
            if shouldShowTrailingSection() {
                PaneToolbarSection {
                    Spacer()
                        .frame(width: 24)
                }
                .opacity(0)
            }
        }
        .buttonStyle(.icon(size: 24))
        .padding(.horizontal, 5.0)
        .padding(.vertical, 8.0)
        .frame(maxHeight: 27.0)
    }

    private func shouldShowLeadingSection() -> Bool {
        model.hasLeadingSidebar
        && (
            ((paneArea == .main || paneArea == .mainLeading) && model.leadingSidebarIsCollapsed)
            || paneArea == .leading
        )
    }

    private func shouldShowTrailingSection() -> Bool {
        model.hasTrailingSidebar
        && (
            ((paneArea == .main || paneArea == .mainTrailing) && model.trailingSidebarIsCollapsed)
            || paneArea == .trailing
        )
    }
}
