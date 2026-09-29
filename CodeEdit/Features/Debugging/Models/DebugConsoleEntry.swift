//
//  DebugConsoleEntry.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

/// A single line of debug console output, from the debuggee (stdout/stderr),
/// from `lldb-dap` itself, or from CodeEdit (session status and errors).
struct DebugConsoleEntry: Identifiable, Equatable {
    /// Unique identifier for list rendering.
    let id: UUID = UUID()
    /// The DAP output category (`"stdout"`, `"stderr"`, `"console"`, …) or
    /// `"error"` for CodeEdit-side failures.
    let category: String
    /// The output text.
    let text: String
}
