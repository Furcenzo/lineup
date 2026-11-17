// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import Carbon.HIToolbox
import CPrivate

/// The system app switcher (⌘Tab / ⌘⇧Tab). The WindowServer handles these shortcuts before any event tap,
/// so WinTab can only get ⌘Tab by turning them off (private `CGSSetSymbolicHotKeyEnabled`, like AltTab).
///
/// The off state is global and outlives WinTab, so it is always turned back on:
/// - when WinTab quits normally (`AppDelegate.applicationWillTerminate`),
/// - from signal handlers (Ctrl-C, `kill`, crashes),
/// - by a watchdog process that waits for WinTab to exit by any means – also force quit (SIGKILL).
enum SystemAppSwitcher {
    /// ⌘Tab and ⌘⇧Tab. ⌘` (next window of the same app, 6) stays with the system.
    nonisolated static let hotKeys: [CGSSymbolicHotKey] = [1, 2]

    static var isEnabled: Bool { hotKeys.allSatisfy { CGSIsSymbolicHotKeyEnabled($0) } }

    static func setEnabled(_ enabled: Bool) {
        for hotKey in hotKeys { _ = CGSSetSymbolicHotKeyEnabled(hotKey, enabled) }
    }

    // MARK: - Safety nets

    /// Signal handlers that turn the system switcher back on before the process dies.
    static func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { sig in
                // Only plain C calls here. ⌘Tab = 1, ⌘⇧Tab = 2 (see hotKeys).
                _ = CGSSetSymbolicHotKeyEnabled(1, true)
                _ = CGSSetSymbolicHotKeyEnabled(2, true)
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }

    static let watchdogArgument = "--watchdog"

    /// Starts `WinTab --watchdog <pid>`: a second process without UI that turns the system switcher back on
    /// when this process exits for any reason.
    static func startWatchdog() {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = [watchdogArgument, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
    }

    /// Body of the watchdog process (see `startWatchdog`); never returns.
    static func runWatchdog(parentPID: pid_t) -> Never {
        let source = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
        source.setEventHandler {
            // A newly started WinTab (e.g. after a rebuild) has already taken over ⌘Tab – leave it alone.
            let others = bundleIDs.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:)).filter {
                $0.processIdentifier != parentPID && !$0.isTerminated
            }
            if others.isEmpty { setEnabled(true) }
            exit(0)
        }
        source.resume()
        // The parent may already be gone (the process source would then never fire).
        if kill(parentPID, 0) != 0 && errno == ESRCH {
            setEnabled(true)
            exit(0)
        }
        dispatchMain()
    }

    static let bundleID = "io.github.furcenzo.wintab"
    /// The installed app and development builds ("WinTab Dev") – any of them may hold ⌘Tab.
    static let bundleIDs = [bundleID, bundleID + ".dev"]
}

/// Decides whether the system switcher is on or off, and keeps it that way.
@MainActor
final class CommandTabGuard {
    /// True when WinTab is set to ⌘Tab and its keyboard tap runs.
    var wantsCommandTab = false {
        didSet { apply() }
    }
    /// With "secure input" on (a password field, Terminal's Secure Keyboard Entry), no event tap receives
    /// keys – the system switcher is turned back on meanwhile, so ⌘Tab keeps working there.
    private(set) var isSecureInputOn = false

    func refreshSecureInput() {
        isSecureInputOn = IsSecureEventInputEnabled()
        apply()
    }

    private func apply() {
        let systemShouldBeOn = !wantsCommandTab || isSecureInputOn
        if SystemAppSwitcher.isEnabled != systemShouldBeOn { SystemAppSwitcher.setEnabled(systemShouldBeOn) }
    }
}
