// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ServiceManagement
import WinTabCore

/// Where the switcher appears.
enum SwitcherScreen: String, CaseIterable {
    /// The screen with the mouse pointer (default).
    case mouse
    /// The primary screen (the one with the menu bar in Displays settings).
    case primary
}

/// The user's choices, stored in UserDefaults. `onChange` is called after every change.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let shortcut = "shortcut"
        static let previews = "previews"
        static let allSpaces = "allSpaces"
        static let showMinimized = "showMinimized"
        static let showHidden = "showHiddenApps"
        static let excluded = "excludedBundleIDs"
        static let screen = "screen"
    }

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults = UserDefaults.standard

    var shortcut: ShortcutChoice {
        didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut); onChange() }
    }
    /// Window thumbnails (also need the Screen Recording permission).
    var previews: Bool {
        didSet { defaults.set(previews, forKey: Key.previews); onChange() }
    }
    var allSpaces: Bool {
        didSet { defaults.set(allSpaces, forKey: Key.allSpaces); onChange() }
    }
    var showMinimized: Bool {
        didSet { defaults.set(showMinimized, forKey: Key.showMinimized); onChange() }
    }
    var showHiddenApps: Bool {
        didSet { defaults.set(showHiddenApps, forKey: Key.showHidden); onChange() }
    }
    /// Bundle IDs of apps whose windows are never listed, in the order they were added.
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excluded); onChange() }
    }
    var screen: SwitcherScreen {
        didSet { defaults.set(screen.rawValue, forKey: Key.screen); onChange() }
    }

    init() {
        shortcut = ShortcutChoice(storedValue: defaults.string(forKey: Key.shortcut))
        previews = defaults.object(forKey: Key.previews) as? Bool ?? true
        allSpaces = defaults.object(forKey: Key.allSpaces) as? Bool ?? true
        showMinimized = defaults.object(forKey: Key.showMinimized) as? Bool ?? true
        showHiddenApps = defaults.object(forKey: Key.showHidden) as? Bool ?? true
        excludedBundleIDs = defaults.stringArray(forKey: Key.excluded) ?? []
        screen = defaults.string(forKey: Key.screen).flatMap(SwitcherScreen.init(rawValue:)) ?? .mouse
    }

    var listOptions: ListOptions {
        ListOptions(includeMinimized: showMinimized, includeHiddenApps: showHiddenApps,
                    excludedBundleIDs: Set(excludedBundleIDs))
    }
}

/// Live state shown in the Settings and Permissions windows, refreshed once a second by the app delegate.
@MainActor @Observable
final class SystemStatus {
    var accessibility = AccessibilityPermission.isGranted
    var screenRecording = ScreenRecordingPermission.isGranted
    var loginItem = LoginItem.status
    /// Secure input is on and the system ⌘Tab took over meanwhile.
    var secureInput = false

    func refresh() {
        // Assign only changes – every assignment would redraw the observing views.
        if accessibility != AccessibilityPermission.isGranted { accessibility.toggle() }
        if screenRecording != ScreenRecordingPermission.isGranted { screenRecording.toggle() }
        let login = LoginItem.status
        if loginItem != login { loginItem = login }
    }
}

/// "Open at Login" through SMAppService (macOS 13+). The user may have to allow it in
/// System Settings → General → Login Items.
enum LoginItem {
    enum Status: Equatable {
        case off, on, needsApproval
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        if enabled && status == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
