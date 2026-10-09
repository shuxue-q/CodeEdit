//
//  KeyboardShortcutWrapperTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import SwiftUI
import XCTest
@testable import CodeEdit

final class KeyboardShortcutWrapperTests: XCTestCase {
    private func wrapper(modifier: String) -> KeyboardShortcutWrapper {
        KeyboardShortcutWrapper(
            name: "x", description: "x", context: "Global", keybinding: "x", modifier: modifier, id: "x"
        )
    }

    func testSingleModifiersKeepTheirMeaning() {
        XCTAssertEqual(wrapper(modifier: "command").parsedModifier, .command)
        XCTAssertEqual(wrapper(modifier: "shift").parsedModifier, .shift)
        XCTAssertEqual(wrapper(modifier: "option").parsedModifier, .option)
        XCTAssertEqual(wrapper(modifier: "control").parsedModifier, .control)
    }

    func testSeveralModifiersAreCombined() {
        XCTAssertEqual(wrapper(modifier: "control,shift").parsedModifier, [.control, .shift])
        XCTAssertEqual(wrapper(modifier: "command, option").parsedModifier, [.command, .option])
    }

    func testUnknownOrEmptyModifiersFallBackToCommand() {
        XCTAssertEqual(wrapper(modifier: "hyper").parsedModifier, .command)
        XCTAssertEqual(wrapper(modifier: "").parsedModifier, .command)
    }

    func testTheCompleteChainBindingIsControlShiftSpace() {
        let binding = KeybindingManager.shared.named(with: "complete_chain")
        XCTAssertEqual(binding.id, "complete_chain")
        XCTAssertEqual(binding.keybinding, " ")
        XCTAssertEqual(binding.parsedModifier, [.control, .shift])
    }
}
