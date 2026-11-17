// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import OSLog
import WinTabCore

/// `log stream --level debug --predicate 'subsystem == "io.github.furcenzo.wintab"'` shows these.
let log = Logger(subsystem: "io.github.furcenzo.wintab", category: "switcher")

/// Connects the keyboard tap, the window list and the overlay: one "session" lasts from pressing the
/// hotkey until the modifier is released (switch), Esc is pressed or a window is clicked.
@MainActor
final class SwitcherController {
    /// The overlay appears only when the modifier is held a little longer, so a quick ⌘Tab just flips
    /// to the previous window without flashing the panel – like Alt+Tab on Windows.
    static let showDelay: Duration = .milliseconds(120)

    private var machine: HotkeyStateMachine
    private var handles = [WindowHandle]()
    private var selection = Selection(count: 0)
    private var recent = RecentWindows()
    private let panel = SwitcherPanel()
    private var showTask: Task<Void, Never>?
    /// Set (to the `reverse` flag) while the window list of a just-opened switcher has not been read yet.
    private var pendingLoad: Bool?

    init(config: HotkeyConfig) {
        machine = HotkeyStateMachine(config: config)
        panel.model.onHover = { [weak self] index in self?.select(index) }
        panel.model.onClick = { [weak self] index in
            guard let self else { return }
            select(index)
            machine.deactivate()
            confirm()
        }
    }

    var isOpen: Bool { machine.isActive }

    /// Changes the shortcut; closes an open switcher.
    func setHotkey(_ config: HotkeyConfig) {
        close()
        machine = HotkeyStateMachine(config: config)
    }

    /// A window got the focus (from `FocusTracker`).
    func recordFocus(_ windowKey: String) {
        log.debug("focus \(windowKey, privacy: .public)")
        recent.touch(windowKey)
    }

    /// Called by the keyboard tap for every key event; returns true to swallow it.
    func handle(_ event: KeyEvent) -> Bool {
        let result = machine.handle(event)
        if let action = result.action { perform(action) }
        return result.swallow
    }

    func perform(_ action: SwitcherAction) {
        switch action {
        case .open(let reverse): open(reverse: reverse)
        case .next: loadIfPending(); selection.next(); updateSelection()
        case .previous: loadIfPending(); selection.previous(); updateSelection()
        case .confirm: loadIfPending(); confirm()
        case .cancel: close()
        }
    }

    /// Reads the windows of the current Space in most-recently-used order and resets the selection.
    @discardableResult
    func loadWindows(reverse: Bool = false) -> [WindowHandle] {
        let focusedID = NSWorkspace.shared.frontmostApplication
            .flatMap { FocusTracker.focusedWindowID(of: $0.processIdentifier) }
        if let focusedID { recent.touch(SwitcherWindow.id(windowID: focusedID)) }

        let unordered = WindowSource.currentWindows()
        let byID = Dictionary(unordered.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        handles = recent.order(unordered.map(\.window)).compactMap { byID[$0.id] }

        let firstIsCurrent = focusedID != nil && handles.first?.window.windowID == focusedID
        selection = Selection(count: handles.count, reverse: reverse, firstIsCurrent: firstIsCurrent)
        panel.model.items = handles.map {
            SwitcherModel.Item(id: $0.window.id, title: $0.window.displayTitle, appName: $0.window.appName,
                               icon: $0.icon, isMinimized: $0.window.isMinimized)
        }
        updateSelection()
        log.debug("listed \(self.handles.count) windows: \(self.handles.map(\.window.id).joined(separator: " "), privacy: .public)")
        return handles
    }

    var debugPanel: SwitcherPanel { panel }

    private func open(reverse: Bool) {
        // Reading the windows takes a few tens of milliseconds. Don't do it inside the event tap callback –
        // the keyboard of the whole system waits for it. Any later key event loads it first if needed.
        pendingLoad = reverse
        Task { [weak self] in self?.loadIfPending() }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard let self, !Task.isCancelled, machine.isActive else { return }
            loadIfPending()
            panel.present()
        }
    }

    private func loadIfPending() {
        guard let reverse = pendingLoad else { return }
        pendingLoad = nil
        loadWindows(reverse: reverse)
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
        guard let target else { return }
        WindowSource.activate(target)
        recent.touch(target.window.id)
    }

    private func close() {
        showTask?.cancel()
        showTask = nil
        pendingLoad = nil
        panel.orderOut(nil)
        machine.deactivate()
        handles = []
        panel.model.items = []
    }
}
