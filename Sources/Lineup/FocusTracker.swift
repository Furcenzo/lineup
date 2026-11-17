// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ApplicationServices
import CPrivate
import LineupCore

/// Watches which window has the focus, for the most-recently-used order:
/// - `NSWorkspace.didActivateApplicationNotification` – another app came to the front,
/// - an `AXObserver` per app for `kAXFocusedWindowChangedNotification` – another window of the front app
///   got the focus (also new windows, which get the focus when they open).
/// Needs the Accessibility permission; call `start()` once it is granted.
@MainActor
final class FocusTracker {
    /// Called with the ID of the window that just got the focus.
    private let onFocus: (CGWindowID) -> Void
    private var observers = [pid_t: AXObserver]()
    private var workspaceTokens = [NSObjectProtocol]()
    private(set) var isRunning = false

    init(onFocus: @escaping (CGWindowID) -> Void) {
        self.onFocus = onFocus
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { self?.recordFocusedWindow(of: pid) } }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let isRegular = app?.activationPolicy == .regular
                MainActor.assumeIsolated { if let pid, isRegular { self?.observe(pid, attempt: 0) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { self?.stopObserving(pid) } }
            },
        ]
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            observe(app.processIdentifier, attempt: 0)
        }
        recordCurrentFocus()
    }

    func stop() {
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceTokens = []
        for pid in Array(observers.keys) { stopObserving(pid) }
        isRunning = false
    }

    /// Records the focused window of the frontmost app (e.g. right before the switcher opens, in case a
    /// notification was missed).
    func recordCurrentFocus() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { recordFocusedWindow(of: pid) }
    }

    /// The window ID of the focused window of an app, if it has one.
    nonisolated static func focusedWindowID(of pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = app.value(kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return windowID(of: window as! AXUIElement)
    }

    nonisolated static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    private func recordFocusedWindow(of pid: pid_t) {
        if let id = Self.focusedWindowID(of: pid) { onFocus(id) }
    }

    fileprivate func focusedWindowChanged(pid: pid_t, windowID: CGWindowID?) {
        // A background app moving the focus between its own windows is not the user's focus.
        guard let windowID, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        onFocus(windowID)
    }

    private func observe(_ pid: pid_t, attempt: Int) {
        guard isRunning, observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusTrackerCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let result = AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString,
                                               Unmanaged.passUnretained(self).toOpaque())
        guard result == .success || result == .notificationAlreadyRegistered else {
            // A freshly launched app often isn't ready for accessibility yet – try again a bit later.
            if attempt < 5 {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500 << attempt))
                    self?.observe(pid, attempt: attempt + 1)
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

private func focusTrackerCallback(observer: AXObserver, element: AXUIElement, notification: CFString,
                                  refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let windowID = FocusTracker.windowID(of: element)
    let trackerAddress = UInt(bitPattern: refcon)
    // The observer's run loop source is on the main run loop.
    MainActor.assumeIsolated {
        Unmanaged<FocusTracker>.fromOpaque(UnsafeRawPointer(bitPattern: trackerAddress)!).takeUnretainedValue()
            .focusedWindowChanged(pid: pid, windowID: windowID)
    }
}
