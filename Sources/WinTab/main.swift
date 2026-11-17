// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import CPrivate
import WinTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let shortcutDefaultsKey = "shortcut"
    private var shortcut = ShortcutChoice(storedValue: UserDefaults.standard.string(forKey: shortcutDefaultsKey))
    private lazy var switcher = SwitcherController(config: shortcut.config)
    private lazy var keyboardTap = KeyboardTap { [unowned self] event in switcher.handle(event) }
    private lazy var focusTracker = FocusTracker { [unowned self] windowID in switcher.recordFocus(windowID: windowID) }
    private static let previewsDefaultsKey = "previews"
    private static let askedScreenRecordingKey = "askedForScreenRecording"
    /// Window previews switched on in the menu (default on); they also need the Screen Recording permission.
    private var previewsWanted = UserDefaults.standard.object(forKey: previewsDefaultsKey) as? Bool ?? true
    private static let allSpacesDefaultsKey = "allSpaces"
    private var spaceObserver: NSObjectProtocol?
    private let commandTabGuard = CommandTabGuard()
    private let permissionWindow = PermissionWindowController()
    private var statusItem: NSStatusItem?
    private var monitorTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no app menu (LSUIElement in Info.plist does the same for the bundle;
        // this also covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        // WinTab has no windows most of the time; macOS must not quit it for that ("automatic termination").
        ProcessInfo.processInfo.disableAutomaticTermination("WinTab listens for its keyboard shortcut")
        switcher.setPreviews(previewsWanted && ScreenRecordingPermission.isGranted)
        switcher.showsAllSpaces = UserDefaults.standard.object(forKey: Self.allSpacesDefaultsKey) as? Bool ?? true
        if runDebugCommand() { return }
        SystemAppSwitcher.installSignalHandlers()
        SystemAppSwitcher.startWatchdog()
        setUpStatusItem()
        refreshState(showPermissionWindow: true)
        askForScreenRecordingOnce()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.switcher.prefetchOtherSpaces() }
        }
        // There are no notifications for a changed permission or secure input – check once a second.
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshState(showPermissionWindow: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardTap.stop()
        SystemAppSwitcher.setEnabled(true)
    }

    // MARK: - State

    /// Starts or stops the keyboard tap and focus tracking with the Accessibility permission and decides
    /// whether the system ⌘Tab has to be off.
    private func refreshState(showPermissionWindow: Bool) {
        if AccessibilityPermission.isGranted {
            if !keyboardTap.isInstalled, keyboardTap.start() { permissionWindow.close() }
            if keyboardTap.isInstalled, !focusTracker.isRunning {
                focusTracker.start()
                switcher.prefetchOtherSpaces()
            }
        } else if keyboardTap.isInstalled {
            // The permission was taken away while WinTab runs.
            switcher.perform(.cancel)
            keyboardTap.stop()
            focusTracker.stop()
            permissionWindow.show()
        } else if showPermissionWindow {
            permissionWindow.show()
        }
        commandTabGuard.wantsCommandTab = shortcut.replacesSystemSwitcher && keyboardTap.isInstalled
        commandTabGuard.refreshSecureInput()
        switcher.setPreviews(previewsWanted && ScreenRecordingPermission.isGranted)
    }

    /// The first time previews are wanted without the permission, show the system prompt once
    /// (once Accessibility is granted, so a new user doesn't get two permission requests at the same time).
    private func askForScreenRecordingOnce() {
        guard previewsWanted, !ScreenRecordingPermission.isGranted,
              !UserDefaults.standard.bool(forKey: Self.askedScreenRecordingKey) else { return }
        Task { [weak self] in
            while !AccessibilityPermission.isGranted {
                try? await Task.sleep(for: .seconds(2))
                if self == nil { return }
            }
            UserDefaults.standard.set(true, forKey: Self.askedScreenRecordingKey)
            ScreenRecordingPermission.request()
        }
    }

    private func setPreviewsWanted(_ wanted: Bool) {
        previewsWanted = wanted
        UserDefaults.standard.set(wanted, forKey: Self.previewsDefaultsKey)
        if wanted && !ScreenRecordingPermission.isGranted { allowScreenRecording() }
        refreshState(showPermissionWindow: false)
    }

    private func setShortcut(_ choice: ShortcutChoice) {
        guard choice != shortcut else { return }
        shortcut = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.shortcutDefaultsKey)
        switcher.setHotkey(choice.config)
        refreshState(showPermissionWindow: false)
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

    private static func name(of choice: ShortcutChoice) -> String {
        switch choice {
        case .commandTab: "⌘Tab"
        case .optionTab: "⌥Tab"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if keyboardTap.isInstalled {
            menu.addItem(disabled: String(localized: "Press \(Self.name(of: shortcut)) to switch windows"))
            if shortcut.replacesSystemSwitcher && commandTabGuard.isSecureInputOn {
                menu.addItem(disabled: String(localized: "Secure input is on – ⌘Tab shows the system app switcher for now"))
            }
        } else {
            menu.addItem(disabled: String(localized: "Waiting for the Accessibility permission"))
            menu.addItem(withTitle: String(localized: "Grant Accessibility Permission…"),
                         action: #selector(showPermission), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())

        let shortcutMenu = NSMenu()
        for choice in ShortcutChoice.allCases {
            let title = switch choice {
            case .commandTab: String(localized: "⌘Tab – replaces the system app switcher")
            case .optionTab: String(localized: "⌥Tab – keeps the system ⌘Tab")
            }
            let item = shortcutMenu.addItem(withTitle: title, action: #selector(chooseShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == shortcut ? .on : .off
        }
        let shortcutItem = menu.addItem(withTitle: String(localized: "Shortcut"), action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu

        let previewsItem = menu.addItem(withTitle: String(localized: "Window Previews"),
                                        action: #selector(togglePreviews), keyEquivalent: "")
        previewsItem.target = self
        previewsItem.state = previewsWanted ? .on : .off
        if previewsWanted && !ScreenRecordingPermission.isGranted {
            menu.addItem(withTitle: String(localized: "Allow Screen Recording for Previews…"),
                         action: #selector(allowScreenRecording), keyEquivalent: "").target = self
        }
        let allSpacesItem = menu.addItem(withTitle: String(localized: "Windows from All Desktops"),
                                         action: #selector(toggleAllSpaces), keyEquivalent: "")
        allSpacesItem.target = self
        allSpacesItem.state = switcher.showsAllSpaces ? .on : .off
        menu.addItem(.separator())

        menu.addItem(withTitle: String(localized: "About WinTab"), action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Quit WinTab"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    @objc private func chooseShortcut(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = ShortcutChoice(rawValue: raw) {
            setShortcut(choice)
        }
    }

    @objc private func toggleAllSpaces() {
        switcher.showsAllSpaces.toggle()
        UserDefaults.standard.set(switcher.showsAllSpaces, forKey: Self.allSpacesDefaultsKey)
        switcher.prefetchOtherSpaces()
    }

    @objc private func togglePreviews() {
        setPreviewsWanted(!previewsWanted)
    }

    @objc private func allowScreenRecording() {
        ScreenRecordingPermission.request()
        ScreenRecordingPermission.openSettings()
    }

    @objc private func showPermission() {
        permissionWindow.show()
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
        if env["WINTAB_SPACES"] != nil {
            DebugSpaces.run()
            fflush(stdout)
            exit(0)
        }
        if let cycles = env["WINTAB_CYCLE"].flatMap(Int.init) {
            runOpenCloseCycles(cycles)
            return true
        }
        guard env["WINTAB_LIST"] != nil || env["WINTAB_SNAPSHOT"] != nil || env["WINTAB_SWITCH"] != nil else {
            return false
        }
        Task { @MainActor in
            print("Accessibility permission: \(AccessibilityPermission.isGranted)")
            print("System ⌘Tab enabled: \(SystemAppSwitcher.isEnabled)")
            print("Screen Recording permission: \(ScreenRecordingPermission.isGranted), previews: \(switcher.showsPreviews)")
            print("Private APIs available: \(WTPrivateAPIsAvailable()), all Spaces: \(switcher.showsAllSpaces)")
            if switcher.showsAllSpaces {
                // The first listing starts the background search for windows on other Spaces.
                switcher.loadWindows()
                try? await Task.sleep(for: .milliseconds(600))
            }
            let start = ContinuousClock.now
            let handles = switcher.loadWindows()
            print("Window list built in \(ContinuousClock.now - start)")
            for (index, handle) in handles.enumerated() {
                let w = handle.window
                print("\(index): [\(w.appName)] \(w.displayTitle) id=\(w.windowID.map(String.init) ?? "-")"
                    + (w.isMinimized ? " minimized" : "") + (w.isAppHidden ? " hidden" : "")
                    + (w.isOnOtherSpace ? " other-space" : ""))
            }
            if let path = env["WINTAB_SNAPSHOT"] {
                // Thumbnails arrive asynchronously.
                if switcher.showsPreviews { try? await Task.sleep(for: .seconds(1.5)) }
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
                try? await Task.sleep(for: .milliseconds(900))
                let front = NSWorkspace.shared.frontmostApplication
                let focused = front.map { AXUIElementCreateApplication($0.processIdentifier) }?
                    .value(kAXFocusedWindowAttribute)
                let title = focused.map { ($0 as! AXUIElement).string(kAXTitleAttribute) ?? "" } ?? "-"
                let id = focused.flatMap { FocusTracker.windowID(of: $0 as! AXUIElement) }
                print("Frontmost: \(front?.localizedName ?? "-") – focused window: \(title) id=\(id.map(String.init) ?? "-")")
            }
            fflush(stdout)
            exit(0)
        }
        return true
    }

    /// `WINTAB_CYCLE=<n>`: opens the overlay on screen, moves the selection and closes it (without
    /// switching) n times – a smoke test for the panel's open/close cycle. Exits with 0 when done.
    private func runOpenCloseCycles(_ cycles: Int) {
        Task { @MainActor in
            for cycle in 1...max(1, cycles) {
                let start = ContinuousClock.now
                let count = switcher.loadWindows(reverse: cycle.isMultiple(of: 2)).count
                let elapsed = ContinuousClock.now - start
                switcher.debugPanel.present()
                for _ in 0..<3 {
                    try? await Task.sleep(for: .milliseconds(40))
                    switcher.perform(.next)
                }
                try? await Task.sleep(for: .milliseconds(40))
                switcher.perform(.cancel)
                try? await Task.sleep(for: .milliseconds(40))
                print("cycle \(cycle): \(count) windows, listed in \(elapsed)")
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

// `WinTab --watchdog <pid>`: the helper process started by SystemAppSwitcher.startWatchdog().
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == SystemAppSwitcher.watchdogArgument,
   let parentPID = pid_t(CommandLine.arguments[2]) {
    SystemAppSwitcher.runWatchdog(parentPID: parentPID)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
