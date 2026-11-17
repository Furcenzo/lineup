// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import LineupCore

@Suite struct HotkeyStateMachineTests {
    private func machine() -> HotkeyStateMachine { HotkeyStateMachine(config: .optionTab) }

    @Test func tabWithoutModifierPassesThrough() {
        var m = machine()
        #expect(m.handle(.keyDown(KeyCode.tab, [])) == .pass)
        #expect(m.handle(.keyUp(KeyCode.tab, [])) == .pass)
        #expect(!m.isActive)
    }

    @Test func optionTabOpensAndReleaseConfirms() {
        var m = machine()
        #expect(m.handle(.modifiersChanged(.option)) == .pass)
        #expect(m.handle(.keyDown(KeyCode.tab, .option)) == KeyEventResult(action: .open(reverse: false), swallow: true))
        #expect(m.isActive)
        #expect(m.handle(.keyUp(KeyCode.tab, .option)).swallow)
        #expect(m.handle(.keyDown(KeyCode.tab, .option)) == KeyEventResult(action: .next, swallow: true))
        #expect(m.handle(.modifiersChanged([])) == KeyEventResult(action: .confirm, swallow: false))
        #expect(!m.isActive)
    }

    @Test func shiftReverses() {
        var m = machine()
        #expect(m.handle(.keyDown(KeyCode.tab, [.option, .shift])).action == .open(reverse: true))
        #expect(m.handle(.keyDown(KeyCode.tab, [.option, .shift])).action == .previous)
        #expect(m.handle(.keyDown(KeyCode.tab, .option)).action == .next)
        // Releasing Shift while ⌥ is still held keeps the switcher open.
        #expect(m.handle(.modifiersChanged(.option)).action == nil)
        #expect(m.isActive)
    }

    @Test func otherModifiersDoNotTrigger() {
        var m = machine()
        #expect(m.handle(.keyDown(KeyCode.tab, [.option, .command])) == .pass)
        #expect(m.handle(.keyDown(KeyCode.tab, [.option, .control])) == .pass)
        #expect(m.handle(.keyDown(KeyCode.tab, .command)) == .pass)
        #expect(!m.isActive)
    }

    @Test func arrowsMoveSelection() {
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(m.handle(.keyDown(KeyCode.rightArrow, .option)).action == .next)
        #expect(m.handle(.keyDown(KeyCode.downArrow, .option)).action == .next)
        #expect(m.handle(.keyDown(KeyCode.leftArrow, .option)).action == .previous)
        #expect(m.handle(.keyDown(KeyCode.upArrow, .option)).action == .previous)
    }

    @Test func escapeCancelsAndSwallowsItsKeyUp() {
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(m.handle(.keyDown(KeyCode.escape, .option)) == KeyEventResult(action: .cancel, swallow: true))
        #expect(!m.isActive)
        #expect(m.handle(.keyUp(KeyCode.escape, .option)).swallow)
        // Releasing ⌥ afterwards does nothing.
        #expect(m.handle(.modifiersChanged([])) == .pass)
        // A later keyUp of Escape is a normal event again.
        #expect(m.handle(.keyUp(KeyCode.escape, [])) == .pass)
    }

    @Test func returnConfirms() {
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(m.handle(.keyDown(KeyCode.return, .option)) == KeyEventResult(action: .confirm, swallow: true))
        #expect(!m.isActive)
    }

    @Test func tabKeyUpAfterReleaseIsSwallowed() {
        // ⌥ released before Tab: the app must not receive a lone Tab keyUp.
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(m.handle(.modifiersChanged([])).action == .confirm)
        #expect(m.handle(.keyUp(KeyCode.tab, [])).swallow)
    }

    @Test func otherKeysAreSwallowedWhileOpen() {
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(m.handle(.keyDown(0, .option)) == KeyEventResult(action: nil, swallow: true))
        #expect(m.handle(.keyUp(0, .option)).swallow)
    }

    @Test func deactivateFromOutside() {
        var m = machine()
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        m.deactivate()
        #expect(!m.isActive)
        #expect(m.handle(.modifiersChanged([])) == .pass)
        // The next ⌥Tab opens the switcher again.
        #expect(m.handle(.keyDown(KeyCode.tab, .option)).action == .open(reverse: false))
    }

    @Test func commandTabWorksTheSameWay() {
        var m = HotkeyStateMachine(config: .commandTab)
        #expect(m.handle(.keyDown(KeyCode.tab, .option)) == .pass)
        #expect(m.handle(.keyDown(KeyCode.tab, [.command, .option])) == .pass)
        #expect(m.handle(.keyDown(KeyCode.tab, [.command, .shift])).action == .open(reverse: true))
        // ⌘Q while the switcher is open must not quit the app underneath.
        #expect(m.handle(.keyDown(12, .command)) == KeyEventResult(action: nil, swallow: true))
        #expect(m.handle(.modifiersChanged(.option)).action == .confirm)
    }

    @Test func shortcutChoiceFromStoredValue() {
        #expect(ShortcutChoice(storedValue: nil) == .commandTab)
        #expect(ShortcutChoice(storedValue: "option") == .optionTab)
        #expect(ShortcutChoice(storedValue: "nonsense") == .commandTab)
        #expect(ShortcutChoice.commandTab.replacesSystemSwitcher)
        #expect(!ShortcutChoice.optionTab.replacesSystemSwitcher)
        #expect(ShortcutChoice.optionTab.config == .optionTab)
    }

    @Test func tracksShiftOnlyWhileOpen() {
        var m = machine()
        _ = m.handle(.modifiersChanged([.option, .shift]))
        #expect(!m.isShiftHeld)
        _ = m.handle(.keyDown(KeyCode.tab, .option))
        #expect(!m.isShiftHeld)
        _ = m.handle(.modifiersChanged([.option, .shift]))
        #expect(m.isShiftHeld)
        _ = m.handle(.modifiersChanged(.option))
        #expect(!m.isShiftHeld)
        _ = m.handle(.modifiersChanged([.option, .shift]))
        _ = m.handle(.modifiersChanged(.shift))   // ⌥ released → switch, shift no longer counts
        #expect(!m.isActive && !m.isShiftHeld)
    }
}
