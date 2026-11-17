// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import WinTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = SwitcherController()
    private lazy var keyboardTap = KeyboardTap { [unowned self] event in switcher.handle(event) }
    private let permissionWindow = PermissionWindowController()
    private var statusItem: NSStatusItem?
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no app menu (LSUIElement in Info.plist does the same for the bundle;
        // this also covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        // WinTab has no windows most of the time; macOS must not quit it for that ("automatic termination").
        ProcessInfo.processInfo.disableAutomaticTermination("WinTab listens for its keyboard shortcut")
        if runDebugCommand() { return }
        setUpStatusItem()
        startWhenPermitted()
    }

    // MARK: - Permission

    private func startWhenPermitted() {
        if AccessibilityPermission.isGranted, keyboardTap.start() {
            permissionWindow.close()
            return
        }
        permissionWindow.show()
        // There is no notification for a changed permission – check once a second.
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if AccessibilityPermission.isGranted, keyboardTap.start() {
                    permissionWindow.close()
                    permissionTask = nil
                    return
                }
            }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WinTab")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if keyboardTap.isRunning {
            menu.addItem(disabled: String(localized: "Press ⌥Tab to switch windows"))
        } else {
            menu.addItem(disabled: String(localized: "Waiting for the Accessibility permission"))
            menu.addItem(withTitle: String(localized: "Grant Accessibility Permission…"),
                         action: #selector(showPermission), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "About WinTab"), action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Quit WinTab"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    @objc private func showPermission() {
        startWhenPermitted()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: String(localized: "A window switcher like Alt+Tab on Windows. Free software under the GNU GPL v3 or later."))
        ])
    }

    // MARK: - Debugging

    /// Debugging without the keyboard (results are printed to stdout; with `open`, use `--stdout <file>`):
    /// - `WINTAB_LIST=1` prints the windows the switcher would offer and quits,
    /// - `WINTAB_SNAPSHOT=/path.png` saves an image of the switcher overlay and quits (no screen recording
    ///   permission needed),
    /// - `WINTAB_SWITCH=<n>` switches to the n-th window of the list (0 = frontmost), prints the frontmost
    ///   app and its focused window afterwards and quits.
    private func runDebugCommand() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let cycles = env["WINTAB_CYCLE"].flatMap(Int.init) {
            runOpenCloseCycles(cycles)
            return true
        }
        guard env["WINTAB_LIST"] != nil || env["WINTAB_SNAPSHOT"] != nil || env["WINTAB_SWITCH"] != nil else {
            return false
        }
        print("Accessibility permission: \(AccessibilityPermission.isGranted)")
        let handles = switcher.loadWindows()
        for (index, handle) in handles.enumerated() {
            let w = handle.window
            print("\(index): [\(w.appName)] \(w.displayTitle) id=\(w.windowID.map(String.init) ?? "-")"
                + (w.isMinimized ? " minimized" : "") + (w.isAppHidden ? " hidden" : ""))
        }
        if let path = env["WINTAB_SNAPSHOT"] {
            do {
                try switcher.debugPanel.snapshot(to: URL(fileURLWithPath: path))
                print("Snapshot: \(path)")
            } catch {
                print("Snapshot failed: \(error)")
            }
        }
        if let n = env["WINTAB_SWITCH"].flatMap(Int.init), handles.indices.contains(n) {
            print("Switching to \(n): \(handles[n].window.displayTitle)")
            WindowSource.activate(handles[n])
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                let front = NSWorkspace.shared.frontmostApplication
                let focused = front.map { AXUIElementCreateApplication($0.processIdentifier) }?
                    .value(kAXFocusedWindowAttribute)
                let title = focused.map { ($0 as! AXUIElement).string(kAXTitleAttribute) ?? "" } ?? "-"
                print("Frontmost: \(front?.localizedName ?? "-") – focused window: \(title)")
                fflush(stdout)
                exit(0)
            }
            return true
        }
        fflush(stdout)
        exit(0)
    }

    /// `WINTAB_CYCLE=<n>`: opens the overlay on screen, moves the selection and closes it (without
    /// switching) n times – a smoke test for the panel's open/close cycle. Exits with 0 when done.
    private func runOpenCloseCycles(_ cycles: Int) {
        Task { @MainActor in
            for cycle in 1...max(1, cycles) {
                let count = switcher.loadWindows(reverse: cycle.isMultiple(of: 2)).count
                switcher.debugPanel.present()
                for _ in 0..<3 {
                    try? await Task.sleep(for: .milliseconds(40))
                    switcher.perform(.next)
                }
                try? await Task.sleep(for: .milliseconds(40))
                switcher.perform(.cancel)
                try? await Task.sleep(for: .milliseconds(40))
                print("cycle \(cycle): \(count) windows")
            }
            fflush(stdout)
            exit(0)
        }
    }
}

extension NSMenu {
    func addItem(disabled title: String) {
        let item = addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
