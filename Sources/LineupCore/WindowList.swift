// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

/// A rectangle in global screen coordinates (top-left origin, like CGWindowList and AX).
public struct Rect: Sendable, Equatable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// Equal up to `tolerance` points on every edge (AX and CGWindowList round differently).
    public func isClose(to other: Rect, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

/// One entry of `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` – the windows visible on the current
/// Space, front to back.
public struct OnScreenWindow: Sendable, Equatable {
    public var windowID: UInt32
    public var pid: Int32
    /// Window level; normal app windows are on layer 0 (menus, the Dock, overlays are above).
    public var layer: Int
    public var bounds: Rect
    public var alpha: Double

    public init(windowID: UInt32, pid: Int32, layer: Int = 0, bounds: Rect, alpha: Double = 1) {
        self.windowID = windowID; self.pid = pid; self.layer = layer; self.bounds = bounds; self.alpha = alpha
    }
}

/// A window reported by the Accessibility API (`kAXWindowsAttribute` of an application).
public struct AXWindow: Sendable, Equatable {
    /// Opaque number the caller uses to find its `AXUIElement` again (e.g. an index into an array).
    public var token: Int
    /// From `_AXUIElementGetWindow`; nil when the private call is unavailable or failed.
    public var windowID: UInt32?
    public var pid: Int32
    public var title: String
    /// `kAXSubroleAttribute`, e.g. "AXStandardWindow", "AXDialog", "AXFloatingWindow".
    public var subrole: String?
    public var isMinimized: Bool
    public var bounds: Rect?

    public init(token: Int, windowID: UInt32?, pid: Int32, title: String, subrole: String?,
                isMinimized: Bool, bounds: Rect?) {
        self.token = token; self.windowID = windowID; self.pid = pid; self.title = title
        self.subrole = subrole; self.isMinimized = isMinimized; self.bounds = bounds
    }
}

/// A running application with a user interface.
public struct AppInfo: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var isHidden: Bool
    public var bundleID: String?

    public init(pid: Int32, name: String, isHidden: Bool = false, bundleID: String? = nil) {
        self.pid = pid; self.name = name; self.isHidden = isHidden; self.bundleID = bundleID
    }
}

/// What the user chose to see in the switcher (Settings).
public struct ListOptions: Sendable, Equatable {
    public var includeMinimized: Bool
    public var includeHiddenApps: Bool
    /// Apps whose windows are never listed.
    public var excludedBundleIDs: Set<String>
    /// When set, only these apps are listed (used for demo screenshots).
    public var onlyBundleIDs: Set<String>?

    public init(includeMinimized: Bool = true, includeHiddenApps: Bool = true, excludedBundleIDs: Set<String> = []) {
        self.includeMinimized = includeMinimized; self.includeHiddenApps = includeHiddenApps
        self.excludedBundleIDs = excludedBundleIDs
    }

    /// Whether the app's windows may be listed at all.
    public func includes(_ app: AppInfo) -> Bool {
        if let onlyBundleIDs { return app.bundleID.map(onlyBundleIDs.contains) ?? false }
        guard let bundleID = app.bundleID else { return true }
        return !excludedBundleIDs.contains(bundleID)
    }
}

/// A window offered in the switcher.
public struct SwitcherWindow: Sendable, Equatable, Identifiable {
    public var token: Int
    public var windowID: UInt32?
    public var pid: Int32
    public var appName: String
    public var title: String
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// On another Space (desktop) or a fullscreen Space – switching to it switches the Space.
    public var isOnOtherSpace: Bool

    public init(token: Int, windowID: UInt32?, pid: Int32, appName: String, title: String,
                isMinimized: Bool = false, isAppHidden: Bool = false, isOnOtherSpace: Bool = false) {
        self.token = token; self.windowID = windowID; self.pid = pid; self.appName = appName; self.title = title
        self.isMinimized = isMinimized; self.isAppHidden = isAppHidden; self.isOnOtherSpace = isOnOtherSpace
    }

    /// Stable while the window exists (CGWindowID); windows without a known ID get a per-listing fallback.
    public var id: String { windowID.map(Self.id(windowID:)) ?? "p\(pid)t\(token)" }
    /// The window title, or the app name for windows without one.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}

public enum WindowListBuilder {
    /// Subroles of windows a user switches to; panels, sheets, tooltips etc. are left out.
    public static let switchableSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]
    /// Smaller on-screen windows are helper windows (status items, invisible trackers…).
    public static let minimumSize: Double = 30

    /// Builds the list of windows in the order the switcher shows them (before the most-recently-used order
    /// is applied – for windows never seen focused this is the order they keep):
    /// 1. visible windows of the current Space, front to back (the order of `onScreen`),
    /// 2. windows on other Spaces (the order of `otherSpaces`),
    /// 3. windows of hidden apps,
    /// 4. minimized windows,
    /// (3 and 4 keep the order of `apps`, then the app's own window order).
    /// Windows without a switchable subrole, windows of `excludedPID` (Lineup itself) and AX windows found
    /// in none of these groups are left out. With `otherSpaces` empty, only the current Space is listed.
    /// `options` leaves out minimized windows, hidden apps and excluded apps as the user chose.
    public static func build(onScreen: [OnScreenWindow], otherSpaces: [OnScreenWindow] = [], axWindows: [AXWindow],
                             apps: [AppInfo], excludedPID: Int32? = nil, options: ListOptions = ListOptions())
                             -> [SwitcherWindow] {
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let appRank = Dictionary(apps.enumerated().map { ($1.pid, $0) }, uniquingKeysWith: { first, _ in first })

        let candidates = switchCandidates(onScreen, excludedPID: excludedPID)
        var zIndexByID = [UInt32: Int]()
        for (index, window) in candidates.enumerated() where zIndexByID[window.windowID] == nil {
            zIndexByID[window.windowID] = index
        }
        var otherIndexByID = [UInt32: Int]()
        for (index, window) in switchCandidates(otherSpaces, excludedPID: excludedPID).enumerated()
        where zIndexByID[window.windowID] == nil && otherIndexByID[window.windowID] == nil {
            otherIndexByID[window.windowID] = index
        }

        var visible = [(z: Int, window: SwitcherWindow)]()
        var elsewhere = [(z: Int, window: SwitcherWindow)]()
        var hidden = [(rank: Int, order: Int, window: SwitcherWindow)]()
        var minimized = [(rank: Int, order: Int, window: SwitcherWindow)]()
        var usedZ = Set<Int>()
        var usedOther = Set<Int>()

        for (order, ax) in axWindows.enumerated() {
            guard ax.pid != excludedPID, let subrole = ax.subrole, switchableSubroles.contains(subrole),
                  let app = appsByPID[ax.pid], options.includes(app) else { continue }
            var item = SwitcherWindow(token: ax.token, windowID: ax.windowID, pid: ax.pid, appName: app.name,
                                      title: ax.title, isMinimized: ax.isMinimized, isAppHidden: app.isHidden)
            let rank = appRank[ax.pid] ?? Int.max
            if ax.isMinimized {
                if options.includeMinimized { minimized.append((rank, order, item)) }
            } else if app.isHidden {
                if options.includeHiddenApps { hidden.append((rank, order, item)) }
            } else if let z = zIndex(of: ax, in: candidates, byID: zIndexByID, used: usedZ) {
                usedZ.insert(z)
                visible.append((z, item))
            } else if let id = ax.windowID, let z = otherIndexByID[id], !usedOther.contains(z) {
                usedOther.insert(z)
                item.isOnOtherSpace = true
                elsewhere.append((z, item))
            }
        }

        let byAppThenOrder = { (a: (rank: Int, order: Int, window: SwitcherWindow),
                                b: (rank: Int, order: Int, window: SwitcherWindow)) in
            (a.rank, a.order) < (b.rank, b.order)
        }
        return visible.sorted { $0.z < $1.z }.map(\.window)
            + elsewhere.sorted { $0.z < $1.z }.map(\.window)
            + hidden.sorted(by: byAppThenOrder).map(\.window)
            + minimized.sorted(by: byAppThenOrder).map(\.window)
    }

    /// Windows on other Spaces whose accessibility element is not known yet, grouped by app – they have to
    /// be looked up (remote token search) before they can be listed. Only apps in `appPIDs` count.
    public static func windowsToLookUp(otherSpaces: [OnScreenWindow], knownIDs: Set<UInt32>, appPIDs: Set<Int32>,
                                       excludedPID: Int32? = nil) -> [Int32: Set<UInt32>] {
        var result = [Int32: Set<UInt32>]()
        for window in switchCandidates(otherSpaces, excludedPID: excludedPID)
        where appPIDs.contains(window.pid) && !knownIDs.contains(window.windowID) {
            result[window.pid, default: []].insert(window.windowID)
        }
        return result
    }

    /// Normal app windows: layer 0, visible, not tiny, not Lineup's own.
    private static func switchCandidates(_ windows: [OnScreenWindow], excludedPID: Int32?) -> [OnScreenWindow] {
        windows.filter {
            $0.layer == 0 && $0.alpha > 0 && $0.pid != excludedPID
                && $0.bounds.width >= minimumSize && $0.bounds.height >= minimumSize
        }
    }

    /// Position of the AX window in the on-screen list: by window ID, or – when the ID is unknown – the
    /// first unused on-screen window of the same app with (almost) the same frame.
    private static func zIndex(of ax: AXWindow, in candidates: [OnScreenWindow], byID: [UInt32: Int],
                               used: Set<Int>) -> Int? {
        if let id = ax.windowID {
            guard let z = byID[id], !used.contains(z) else { return nil }
            return z
        }
        guard let bounds = ax.bounds else { return nil }
        return candidates.indices.first {
            !used.contains($0) && candidates[$0].pid == ax.pid && candidates[$0].bounds.isClose(to: bounds)
        }
    }
}
