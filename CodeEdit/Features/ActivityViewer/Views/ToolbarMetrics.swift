//
//  ToolbarMetrics.swift
//  CodeEdit
//
//  Created by CodeEdit on 10/10/26.
//

import SwiftUI

/// Design tokens shared by every toolbar control so the leading and trailing capsule groups
/// stay symmetric.
enum ToolbarMetrics {
    /// Point size of toolbar icons.
    static let iconSize: CGFloat = 17
    /// Width of an icon button's cell.
    static let cellWidth: CGFloat = 37
    /// Height of an icon button's cell and of a capsule.
    static let cellHeight: CGFloat = 40
    /// Height of the vertical divider between capsule segments.
    static let separatorHeight: CGFloat = 16
    /// Width of the vertical divider between capsule segments.
    static let separatorWidth: CGFloat = 0.75
    /// Horizontal padding of capsules that contain only icon buttons.
    static let iconCapsulePadding: CGFloat = 4
    /// Horizontal padding of capsules that contain text.
    static let textCapsulePadding: CGFloat = 10
    /// Spacing between sibling capsules inside a toolbar item.
    static let groupSpacing: CGFloat = 8
}

/// The thin vertical divider between segments of a toolbar capsule.
struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: ToolbarMetrics.separatorWidth, height: ToolbarMetrics.separatorHeight)
    }
}
