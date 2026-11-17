// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ApplicationServices
import CPrivate
import WinTabCore

/// A window in the switcher together with what is needed to show it and switch to it.
struct WindowHandle {
    let window: SwitcherWindow
    let element: AXUIElement
    let icon: NSImage?
}

/// Reads the windows of the current Space through the Accessibility API and CGWindowList,
/// and brings a chosen window to the front.
@MainActor
enum WindowSource {
    /// How long one AX request to an app may take; a hung app must not freeze the switcher.
    private static let axTimeout: Float = 0.25

    /// The windows to offer: the current Space (+ minimized and hidden windows), and with `remote` also the
    /// windows on other Spaces whose elements `remote` has found; the rest is handed to `remote` to look up.
    static func currentWindows(remote: RemoteWindowSearch? = nil) -> [WindowHandle] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var elements = [AXUIElement]()
        var axWindows = [AXWindow]()
        var appInfos = [AppInfo]()
        var icons = [Int32: NSImage]()
        for app in apps where app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            appInfos.append(AppInfo(pid: pid, name: app.localizedName ?? app.bundleIdentifier ?? "?",
                                    isHidden: app.isHidden))
            icons[pid] = app.icon
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, axTimeout)
            for element in appElement.array(kAXWindowsAttribute) {
                AXUIElementSetMessagingTimeout(element, axTimeout)
                var windowID: CGWindowID = 0
                let hasID = _AXUIElementGetWindow(element, &windowID) == .success && windowID != 0
                // One request for all attributes instead of one per attribute (each is a round trip to the app).
                let values = element.values([kAXTitleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute,
                                             kAXPositionAttribute, kAXSizeAttribute])
                axWindows.append(AXWindow(
                    token: elements.count,
                    windowID: hasID ? windowID : nil,
                    pid: pid,
                    title: values[0] as? String ?? "",
                    subrole: values[1] as? String,
                    isMinimized: (values[2] as? NSNumber)?.boolValue ?? false,
                    bounds: AXUIElement.frame(position: values[3], size: values[4])))
                elements.append(element)
            }
        }

        var otherSpaces = [OnScreenWindow]()
        if let remote {
            otherSpaces = Spaces.windowsOnAllSpaces()
            let onAnySpace = Set(otherSpaces.map(\.windowID))
            remote.prune(keeping: onAnySpace)
            let listed = Set(axWindows.compactMap(\.windowID))
            for windowID in remote.knownWindowIDs.subtracting(listed) {
                guard let element = remote.element(for: windowID),
                      let window = otherSpaces.first(where: { $0.windowID == windowID }) else { continue }
                let values = element.values([kAXTitleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute])
                axWindows.append(AXWindow(
                    token: elements.count, windowID: windowID, pid: window.pid, title: values[0] as? String ?? "",
                    subrole: values[1] as? String, isMinimized: (values[2] as? NSNumber)?.boolValue ?? false,
                    bounds: window.bounds))
                elements.append(element)
            }
            remote.search(WindowListBuilder.windowsToLookUp(
                otherSpaces: otherSpaces, knownIDs: Set(axWindows.compactMap(\.windowID)),
                appPIDs: Set(appInfos.map(\.pid)), excludedPID: ownPID))
        }

        let windows = WindowListBuilder.build(onScreen: onScreenWindows(), otherSpaces: otherSpaces,
                                              axWindows: axWindows, apps: appInfos, excludedPID: ownPID)
        return windows.map { WindowHandle(window: $0, element: elements[$0.token], icon: icons[$0.pid]) }
    }

    /// Visible windows of the current Space, front to back.
    static func onScreenWindows() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(onScreenWindow(from:))
    }

    /// One CGWindowList dictionary as an `OnScreenWindow`.
    nonisolated static func onScreenWindow(from info: [String: Any]) -> OnScreenWindow? {
        guard let id = info[kCGWindowNumber as String] as? UInt32,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        return OnScreenWindow(
            windowID: id, pid: pid,
            layer: info[kCGWindowLayer as String] as? Int ?? 0,
            bounds: Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
            alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
    }

    /// Brings the window to the front: un-minimizes it, unhides its app, then focuses exactly this window
    /// with the private `_SLPSSetFrontProcessWithOptions` + key-window event (switches the Space when the
    /// window is on another one) and raises it. Without the private API: raise + make the app frontmost
    /// through accessibility, which can leave a window behind a sibling of the same app.
    static func activate(_ handle: WindowHandle) {
        let window = handle.window
        let app = NSRunningApplication(processIdentifier: window.pid)
        if window.isAppHidden { app?.unhide() }
        if window.isMinimized {
            AXUIElementSetAttributeValue(handle.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if let windowID = window.windowID, WTFocusWindow(window.pid, windowID) {
            AXUIElementPerformAction(handle.element, kAXRaiseAction as CFString)
            return
        }
        AXUIElementSetAttributeValue(handle.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(handle.element, kAXRaiseAction as CFString)
        // Setting kAXFrontmostAttribute is not subject to the "cooperative activation" rules of macOS 14+
        // that make NSRunningApplication.activate() fail for apps in the background, like WinTab.
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app?.activate()
        // The app may bring its own key window forward while activating – raise ours again.
        AXUIElementPerformAction(handle.element, kAXRaiseAction as CFString)
    }
}

// MARK: - Small AXUIElement helpers

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }

    func array(_ attribute: String) -> [AXUIElement] {
        guard let value = value(attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [AnyObject]).compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
    }

    /// Several attributes in one request; missing attributes and errors are nil.
    func values(_ attributes: [String]) -> [CFTypeRef?] {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, attributes as CFArray, AXCopyMultipleAttributeOptions(),
                                                     &result) == .success,
              let array = result as? [AnyObject], array.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return array.map { value in
            // Failed attributes come back as an AXValue holding the AXError.
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
            return value
        }
    }

    /// Position and size in global screen coordinates (top-left origin).
    var frame: Rect? { Self.frame(position: value(kAXPositionAttribute), size: value(kAXSizeAttribute)) }

    static func frame(position: CFTypeRef?, size: CFTypeRef?) -> Rect? {
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return Rect(x: point.x, y: point.y, width: extent.width, height: extent.height)
    }
}
