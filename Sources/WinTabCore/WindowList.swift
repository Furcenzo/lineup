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

    public init(pid: Int32, name: String, isHidden: Bool = false) {
        self.pid = pid; self.name = name; self.isHidden = isHidden
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

    public init(token: Int, windowID: UInt32?, pid: Int32, appName: String, title: String,
                isMinimized: Bool = false, isAppHidden: Bool = false) {
        self.token = token; self.windowID = windowID; self.pid = pid; self.appName = appName; self.title = title
        self.isMinimized = isMinimized; self.isAppHidden = isAppHidden
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

    /// Builds the list of windows on the current Space in the order the switcher shows them:
    /// 1. visible windows, front to back (the order of `onScreen`),
    /// 2. windows of hidden apps,
    /// 3. minimized windows,
    /// (2 and 3 keep the order of `apps`, then the app's own window order).
    /// Windows without a switchable subrole, windows of `excludedPID` (WinTab itself) and AX windows
    /// that are neither on screen, minimized nor hidden (they belong to another Space) are left out.
    public static func build(onScreen: [OnScreenWindow], axWindows: [AXWindow], apps: [AppInfo],
                             excludedPID: Int32? = nil) -> [SwitcherWindow] {
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let appRank = Dictionary(apps.enumerated().map { ($1.pid, $0) }, uniquingKeysWith: { first, _ in first })

        let candidates = onScreen.filter {
            $0.layer == 0 && $0.alpha > 0 && $0.pid != excludedPID
                && $0.bounds.width >= minimumSize && $0.bounds.height >= minimumSize
        }
        var zIndexByID = [UInt32: Int]()
        for (index, window) in candidates.enumerated() where zIndexByID[window.windowID] == nil {
            zIndexByID[window.windowID] = index
        }

        var visible = [(z: Int, window: SwitcherWindow)]()
        var hidden = [(rank: Int, order: Int, window: SwitcherWindow)]()
        var minimized = [(rank: Int, order: Int, window: SwitcherWindow)]()
        var usedZ = Set<Int>()

        for (order, ax) in axWindows.enumerated() {
            guard ax.pid != excludedPID, let subrole = ax.subrole, switchableSubroles.contains(subrole),
                  let app = appsByPID[ax.pid] else { continue }
            let item = SwitcherWindow(token: ax.token, windowID: ax.windowID, pid: ax.pid, appName: app.name,
                                      title: ax.title, isMinimized: ax.isMinimized, isAppHidden: app.isHidden)
            let rank = appRank[ax.pid] ?? Int.max
            if ax.isMinimized {
                minimized.append((rank, order, item))
            } else if app.isHidden {
                hidden.append((rank, order, item))
            } else if let z = zIndex(of: ax, in: candidates, byID: zIndexByID, used: usedZ) {
                usedZ.insert(z)
                visible.append((z, item))
            }
        }

        let byAppThenOrder = { (a: (rank: Int, order: Int, window: SwitcherWindow),
                                b: (rank: Int, order: Int, window: SwitcherWindow)) in
            (a.rank, a.order) < (b.rank, b.order)
        }
        return visible.sorted { $0.z < $1.z }.map(\.window)
            + hidden.sorted(by: byAppThenOrder).map(\.window)
            + minimized.sorted(by: byAppThenOrder).map(\.window)
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
