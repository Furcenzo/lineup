// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

/// Most-recently-used order of windows, keyed by `SwitcherWindow.id`.
///
/// Windows WinTab has seen focused are ordered by recency. Windows it has never seen focused (WinTab just
/// started, or a window opened in the background) are added behind them in the order they were first
/// listed – which is the on-screen front-to-back order, the best guess there is.
public struct RecentWindows: Sendable, Equatable {
    /// Most recent first.
    public private(set) var keys = [String]()
    /// Keys of closed windows are never reported, so the list is capped instead.
    public let capacity: Int

    public init(capacity: Int = 1000) {
        self.capacity = max(1, capacity)
    }

    /// The window got the focus – it moves to the front.
    public mutating func touch(_ key: String) {
        if let index = keys.firstIndex(of: key) {
            if index == 0 { return }
            keys.remove(at: index)
        }
        keys.insert(key, at: 0)
        if keys.count > capacity { keys.removeLast(keys.count - capacity) }
    }

    public mutating func remove(_ key: String) {
        keys.removeAll { $0 == key }
    }

    /// Orders the windows for the switcher and remembers windows seen for the first time:
    /// 1. windows that are not minimized, most recent first,
    /// 2. minimized windows, most recent first (like Windows, where minimizing sends a window to the back).
    /// Windows not seen before keep their relative order and go after the known ones of their group.
    public mutating func order(_ windows: [SwitcherWindow]) -> [SwitcherWindow] {
        var known = Set(keys)
        for window in windows where !known.contains(window.id) && keys.count < capacity {
            keys.append(window.id)
            known.insert(window.id)
        }
        let rank = Dictionary(keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return windows.enumerated().sorted { a, b in
            let keyA = (a.element.isMinimized ? 1 : 0, rank[a.element.id] ?? Int.max, a.offset)
            let keyB = (b.element.isMinimized ? 1 : 0, rank[b.element.id] ?? Int.max, b.offset)
            return keyA < keyB
        }.map(\.element)
    }
}

extension SwitcherWindow {
    /// The `id` of the window with this CGWindowID – what focus tracking passes to `RecentWindows.touch`.
    public static func id(windowID: UInt32) -> String { "w\(windowID)" }
}
