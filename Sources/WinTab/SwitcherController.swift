// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import WinTabCore

/// Connects the keyboard tap, the window list and the overlay: one "session" lasts from pressing the
/// hotkey until the modifier is released (switch), Esc is pressed or a window is clicked.
@MainActor
final class SwitcherController {
    /// The overlay appears only when the modifier is held a little longer, so a quick ⌥Tab just flips
    /// to the previous window without flashing the panel – like Alt+Tab on Windows.
    static let showDelay: Duration = .milliseconds(120)

    private var machine = HotkeyStateMachine(config: .optionTab)
    private var handles = [WindowHandle]()
    private var selection = Selection(count: 0)
    private let panel = SwitcherPanel()
    private var showTask: Task<Void, Never>?

    init() {
        panel.model.onHover = { [weak self] index in self?.select(index) }
        panel.model.onClick = { [weak self] index in
            guard let self else { return }
            select(index)
            machine.deactivate()
            confirm()
        }
    }

    var isOpen: Bool { machine.isActive }

    /// Called by the keyboard tap for every key event; returns true to swallow it.
    func handle(_ event: KeyEvent) -> Bool {
        let result = machine.handle(event)
        if let action = result.action { perform(action) }
        return result.swallow
    }

    func perform(_ action: SwitcherAction) {
        switch action {
        case .open(let reverse): open(reverse: reverse)
        case .next: selection.next(); updateSelection()
        case .previous: selection.previous(); updateSelection()
        case .confirm: confirm()
        case .cancel: close()
        }
    }

    /// Debugging and testing without the keyboard: the current list of windows.
    func loadWindows(reverse: Bool = false) -> [WindowHandle] {
        handles = WindowSource.currentWindows()
        selection = Selection(count: handles.count, reverse: reverse)
        panel.model.items = handles.map {
            SwitcherModel.Item(id: $0.window.id, title: $0.window.displayTitle, appName: $0.window.appName,
                               icon: $0.icon, isMinimized: $0.window.isMinimized)
        }
        updateSelection()
        return handles
    }

    var debugPanel: SwitcherPanel { panel }

    private func open(reverse: Bool) {
        _ = loadWindows(reverse: reverse)
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard let self, !Task.isCancelled, machine.isActive else { return }
            panel.present()
        }
    }

    private func select(_ index: Int) {
        selection.select(index)
        updateSelection()
    }

    private func updateSelection() {
        panel.model.selectedIndex = selection.index
    }

    private func confirm() {
        let target = selection.index.flatMap { handles.indices.contains($0) ? handles[$0] : nil }
        close()
        if let target { WindowSource.activate(target) }
    }

    private func close() {
        showTask?.cancel()
        showTask = nil
        panel.orderOut(nil)
        machine.deactivate()
        handles = []
        panel.model.items = []
    }
}
