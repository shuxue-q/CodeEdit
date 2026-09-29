//
//  UtilityAreaDebuggerView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import SwiftUI

/// The debugger panel: variables and console output in the main area, the call stack in the
/// leading sidebar, watch expressions in the trailing sidebar, and debug session controls
/// in the bottom toolbar.
struct UtilityAreaDebuggerView: View {
    @EnvironmentObject private var utilityAreaViewModel: UtilityAreaViewModel

    var body: some View {
        UtilityAreaTabView(
            model: utilityAreaViewModel.tabViewModel,
            content: { _ in
                DebugVariablesView()
            },
            leadingSidebar: { _ in
                DebugCallStackView()
            },
            trailingSidebar: { _ in
                DebugWatchView()
            }
        )
        .paneToolbar {
            DebugToolbarView()
        }
        // The toolbar sits outside `UtilityAreaTabView`'s own `environmentObject` scope,
        // so the tab view model must be injected here for `PaneToolbar` to resolve it.
        .environmentObject(utilityAreaViewModel.tabViewModel)
    }
}
