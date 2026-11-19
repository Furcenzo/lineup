// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import OSLog
import LineupCore

/// `log stream --level debug --predicate 'subsystem == "io.github.furcenzo.lineup"'` shows these.
let log = Logger(subsystem: "io.github.furcenzo.lineup", category: "switcher")

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
    private var hoverFilter = HoverFilter()
    private var recent = RecentWindows()
    private let panel = SwitcherPanel()
    private let thumbnails = ThumbnailStore()
    private let remoteWindows = RemoteWindowSearch()
    /// List windows of all Spaces (desktops, fullscreen apps), not just the current one.
    var showsAllSpaces = true
    /// Which windows to leave out (Settings).
    var listOptions = ListOptions()
    var screenChoice = SwitcherScreen.mouse
    private var prefetchTask: Task<Void, Never>?
    /// The window that had the focus last – captured when it loses the focus.
    private var lastFocusedID: CGWindowID?
    private var showTask: Task<Void, Never>?
    /// Set (to the `reverse` flag) while the window list of a just-opened switcher has not been read yet.
    private var pendingLoad: Bool?
    /// Watches mouse clicks in other apps while the switcher is open (a click outside closes it).
    private var outsideClickMonitor: Any?

    init(config: HotkeyConfig) {
        machine = HotkeyStateMachine(config: config)
        thumbnails.onUpdate = { [weak self] windowID, image in self?.panel.model.setThumbnail(image, for: windowID) }
        panel.model.onHover = { [weak self] index, id, inside in self?.hover(index, id: id, inside: inside) }
        panel.model.onClick = { [weak self] index in
            guard let self else { return }
            select(index)
            machine.deactivate()
            confirm()
        }
        panel.model.onCloseWindow = { [weak self] index in self?.closeWindow(at: index) }
        panel.model.onForceQuit = { [weak self] index in self?.forceQuitApp(at: index) }
    }

    var isOpen: Bool { machine.isActive }

    /// Changes the shortcut; closes an open switcher.
    func setHotkey(_ config: HotkeyConfig) {
        close()
        machine = HotkeyStateMachine(config: config)
    }

    /// Window thumbnails instead of app icons (needs the Screen Recording permission).
    var showsPreviews: Bool { thumbnails.isEnabled }

    func setPreviews(_ enabled: Bool) {
        guard enabled != thumbnails.isEnabled else { return }
        close()
        thumbnails.isEnabled = enabled
        panel.model.showsPreviews = enabled
        if !enabled { thumbnails.removeAll() }
    }

    /// A window got the focus (from `FocusTracker`).
    func recordFocus(windowID: CGWindowID) {
        log.debug("focus w\(windowID)")
        recent.touch(SwitcherWindow.id(windowID: windowID))
        // The window that just lost the focus is still visible – a good moment for a fresh thumbnail.
        if let previous = lastFocusedID, previous != windowID { thumbnails.refresh([previous]) }
        lastFocusedID = windowID
    }

    /// Called by the keyboard tap for every key event; returns true to swallow it.
    func handle(_ event: KeyEvent) -> Bool {
        let result = machine.handle(event)
        if let action = result.action { perform(action) }
        if panel.model.isShiftHeld != machine.isShiftHeld { panel.model.isShiftHeld = machine.isShiftHeld }
        return result.swallow
    }

    func perform(_ action: SwitcherAction) {
        switch action {
        case .open(let reverse): open(reverse: reverse)
        case .next: loadIfPending(); selection.next(); updateSelection()
        case .previous: loadIfPending(); selection.previous(); updateSelection()
        case .confirm: loadIfPending(); confirm()
        case .cancel: close()
        case .closeWindow: loadIfPending(); selection.index.map(closeWindow(at:)); showNow()
        case .forceQuitApp: loadIfPending(); selection.index.map(forceQuitApp(at:)); showNow()
        }
    }

    /// Reads the windows of the current Space in most-recently-used order and resets the selection.
    @discardableResult
    func loadWindows(reverse: Bool = false) -> [WindowHandle] {
        let focusedID = NSWorkspace.shared.frontmostApplication
            .flatMap { FocusTracker.focusedWindowID(of: $0.processIdentifier) }
        if let focusedID { recordFocus(windowID: focusedID) }

        let unordered = WindowSource.currentWindows(remote: showsAllSpaces ? remoteWindows : nil, options: listOptions)
        let byID = Dictionary(unordered.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        handles = recent.order(unordered.map(\.window)).compactMap { byID[$0.id] }

        let firstIsCurrent = focusedID != nil && handles.first?.window.windowID == focusedID
        selection = Selection(count: handles.count, reverse: reverse, firstIsCurrent: firstIsCurrent)
        panel.model.items = handles.map {
            SwitcherModel.Item(id: $0.window.id, windowID: $0.window.windowID, title: $0.window.displayTitle,
                               appName: $0.window.appName, icon: $0.icon, isMinimized: $0.window.isMinimized,
                               thumbnail: $0.window.windowID.flatMap(thumbnails.image(for:)))
        }
        updateSelection()
        if thumbnails.isEnabled {
            // Minimized windows and windows of hidden apps can't be captured – they keep their cached thumbnail.
            let capturable = handles.filter { !$0.window.isMinimized && !$0.window.isAppHidden }
                .compactMap(\.window.windowID)
            thumbnails.refresh(capturable)
            thumbnails.prune(keeping: Set(handles.compactMap(\.window.windowID)))
        }
        log.debug("listed \(self.handles.count) windows: \(self.handles.map(\.window.id).joined(separator: " "), privacy: .public)")
        return handles
    }

    var debugPanel: SwitcherPanel { panel }

    /// Looks up windows of other Spaces in the background (after a Space change or at start), so they are
    /// ready when the switcher opens next time.
    func prefetchOtherSpaces() {
        guard showsAllSpaces else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, !machine.isActive else { return }
            _ = WindowSource.currentWindows(remote: remoteWindows, options: listOptions)
        }
    }

    private func open(reverse: Bool) {
        // Reading the windows takes a few tens of milliseconds. Don't do it inside the event tap callback –
        // the keyboard of the whole system waits for it. Any later key event loads it first if needed.
        pendingLoad = reverse
        Task { [weak self] in self?.loadIfPending() }
        // A click anywhere outside the switcher closes it without switching (like Esc). A global monitor only
        // sees events of other apps – exactly the clicks that are not on the panel. The click itself still
        // reaches the app under the pointer.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.machine.isActive else { return }
                    log.debug("click outside – switcher closed")
                    self.close()
                }
            }
        }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard let self, !Task.isCancelled, machine.isActive else { return }
            loadIfPending()
            present()
        }
    }

    /// Shows the panel right away (W pressed before it appeared – the user sees what was closed).
    private func showNow() {
        guard machine.isActive, !panel.isVisible else { return }
        showTask?.cancel()
        showTask = nil
        present()
    }

    /// Sizes, centers and shows the panel. The tile that ends up under a mouse pointer standing still is
    /// not selected by the hover (only by moving to another tile, or by a click).
    private func present() {
        panel.present(on: screenChoice)
        let mouse = NSEvent.mouseLocation
        hoverFilter.reset(x: mouse.x, y: mouse.y)
    }

    private func hover(_ index: Int, id: String, inside: Bool) {
        guard inside else { return hoverFilter.exit(id) }
        // SwiftUI may still report a tile of the list before a window was closed.
        guard handles.indices.contains(index), handles[index].window.id == id else { return }
        let mouse = NSEvent.mouseLocation
        if hoverFilter.enter(id, x: mouse.x, y: mouse.y) { select(index) }
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
        if let id = target.window.windowID { recordFocus(windowID: id) } else { recent.touch(target.window.id) }
    }

    /// Closes one window with its own close button (through accessibility). The switcher stays open.
    /// An app may still ask to save changes – its dialog shows up on that window.
    private func closeWindow(at index: Int) {
        guard handles.indices.contains(index) else { return }
        let handle = handles[index]
        if let button = handle.element.value(kAXCloseButtonAttribute),
           CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
        log.debug("closed \(handle.window.id, privacy: .public)")
        recent.remove(handle.window.id)
        removeItems(at: [index])
    }

    /// Force quits the app that owns the window (⇧ held) – like Force Quit in the Apple menu, unsaved
    /// changes are lost. All of the app's windows leave the list.
    private func forceQuitApp(at index: Int) {
        guard handles.indices.contains(index) else { return }
        let pid = handles[index].window.pid
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        log.debug("force quit \(app.localizedName ?? "?", privacy: .public)")
        app.forceTerminate()
        let indices = handles.indices.filter { handles[$0].window.pid == pid }
        for i in indices { recent.remove(handles[i].window.id) }
        removeItems(at: indices)
    }

    private func removeItems(at indices: [Int]) {
        for index in indices.sorted(by: >) {
            handles.remove(at: index)
            selection.remove(at: index)
        }
        let removed = Set(indices)
        panel.model.items = panel.model.items.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        updateSelection()
        // Fewer tiles – size and center the panel again.
        if panel.isVisible { present() }
    }

    private func close() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        panel.model.isShiftHeld = false
        showTask?.cancel()
        showTask = nil
        pendingLoad = nil
        panel.orderOut(nil)
        machine.deactivate()
        handles = []
        panel.model.items = []
    }
}
