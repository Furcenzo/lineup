// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import CPrivate
import SwiftUI
import WinTabCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let status = SystemStatus()
    private lazy var switcher = SwitcherController(config: settings.shortcut.config)
    private lazy var keyboardTap = KeyboardTap { [unowned self] event in switcher.handle(event) }
    private lazy var focusTracker = FocusTracker { [unowned self] windowID in switcher.recordFocus(windowID: windowID) }
    private let commandTabGuard = CommandTabGuard()
    private lazy var permissionsWindow: HostingWindow<PermissionsView> = HostingWindow(title: { String(localized: "WinTab – Permissions") }) {
        [unowned self] in
        PermissionsView(status: status) { [unowned self] in permissionsWindow.close() }
    }
    private lazy var settingsWindow: HostingWindow<SettingsView> = HostingWindow(title: { String(localized: "WinTab Settings") }) {
        [unowned self] in SettingsView(settings: settings, status: status)
    }
    /// The permissions window was shown once (on the very first launch).
    private static let onboardedKey = "onboardingShown"
    private var appliedShortcut: ShortcutChoice?
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?
    private var monitorTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no app menu (LSUIElement in Info.plist does the same for the bundle;
        // this also covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
        // WinTab has no windows most of the time; macOS must not quit it for that ("automatic termination").
        ProcessInfo.processInfo.disableAutomaticTermination("WinTab listens for its keyboard shortcut")
        applySettings()
        settings.onChange = { [unowned self] in applySettings() }
        if runDebugCommand() { return }
        SystemAppSwitcher.installSignalHandlers()
        SystemAppSwitcher.startWatchdog()
        setUpStatusItem()
        refreshState()

        let firstLaunch = !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        if !status.accessibility || (firstLaunch && settings.previews && !status.screenRecording) {
            permissionsWindow.show()
        }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.switcher.prefetchOtherSpaces() }
        }
        // There are no notifications for a changed permission or secure input – check once a second.
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshState()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardTap.stop()
        SystemAppSwitcher.setEnabled(true)
    }

    // MARK: - State

    /// Hands the settings to the switcher (called at launch and after every change in Settings).
    private func applySettings() {
        if appliedShortcut != settings.shortcut {
            appliedShortcut = settings.shortcut
            switcher.setHotkey(settings.shortcut.config)
        }
        switcher.showsAllSpaces = settings.allSpaces
        switcher.listOptions = settings.listOptions
        switcher.screenChoice = settings.screen
        refreshState()
        switcher.prefetchOtherSpaces()
    }

    /// Follows the permissions: starts or stops the keyboard tap and focus tracking, decides whether the system
    /// ⌘Tab has to be off and whether previews are possible.
    private func refreshState() {
        let wasComplete = permissionsComplete
        status.refresh()
        if status.accessibility {
            if !keyboardTap.isInstalled { keyboardTap.start() }
            if keyboardTap.isInstalled, !focusTracker.isRunning {
                focusTracker.start()
                switcher.prefetchOtherSpaces()
            }
        } else if keyboardTap.isInstalled {
            // The permission was taken away while WinTab runs.
            switcher.perform(.cancel)
            keyboardTap.stop()
            focusTracker.stop()
            permissionsWindow.show()
        }
        // Everything the user wanted is allowed now – the onboarding has done its job.
        if !wasComplete && permissionsComplete { permissionsWindow.close() }

        commandTabGuard.wantsCommandTab = settings.shortcut.replacesSystemSwitcher && keyboardTap.isInstalled
        commandTabGuard.refreshSecureInput()
        let secureInputTakesOver = commandTabGuard.isSecureInputOn && commandTabGuard.wantsCommandTab
        if status.secureInput != secureInputTakesOver { status.secureInput = secureInputTakesOver }
        switcher.setPreviews(settings.previews && status.screenRecording)
    }

    private var permissionsComplete: Bool {
        status.accessibility && (status.screenRecording || !settings.previews)
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
        if keyboardTap.isInstalled {
            let name = settings.shortcut == .commandTab ? "⌘Tab" : "⌥Tab"
            menu.addItem(disabled: String(localized: "Press \(name) to switch windows"))
            if status.secureInput {
                menu.addItem(disabled: String(localized: "Secure input is on – ⌘Tab shows the system app switcher for now"))
            }
        } else {
            menu.addItem(disabled: String(localized: "Waiting for the Accessibility permission"))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        if !permissionsComplete {
            menu.addItem(withTitle: String(localized: "Permissions…"), action: #selector(showPermissions),
                         keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "About WinTab"), action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Quit WinTab"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    @objc private func showSettings() {
        status.refresh()
        settingsWindow.show()
    }

    @objc private func showPermissions() {
        permissionsWindow.show()
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
        if let view = env["WINTAB_VIEW"], let path = env["WINTAB_SNAPSHOT"] {
            // `WINTAB_VIEW=settings|permissions WINTAB_SNAPSHOT=/x.png`: image of that window's content.
            // An opaque window background, so the text is readable in light and dark mode.
            let content: NSView = view == "settings"
                ? NSHostingView(rootView: SettingsView(settings: settings, status: status)
                    .background(Color(nsColor: .windowBackgroundColor)))
                : NSHostingView(rootView: PermissionsView(status: status) {}
                    .background(Color(nsColor: .windowBackgroundColor)))
            content.setFrameSize(content.fittingSize)
            content.layoutSubtreeIfNeeded()
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
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
        // `WINTAB_ONLY_APPS=com.apple.Safari,…`: list only these apps (screenshots with demo windows only).
        if let only = env["WINTAB_ONLY_APPS"] {
            switcher.listOptions.onlyBundleIDs = Set(only.split(separator: ",").map(String.init))
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
