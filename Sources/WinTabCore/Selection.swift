// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

/// The highlighted item in the switcher. Moving past either end wraps around, like Alt+Tab on Windows.
public struct Selection: Sendable, Equatable {
    public private(set) var count: Int
    /// nil when there is nothing to select.
    public private(set) var index: Int?

    /// Forward (⌥Tab) starts on the second item – the previously used window – so a quick
    /// ⌥Tab flips between the two most recent windows. Backward (⌥⇧Tab) starts on the last item.
    /// When the first item is not the window that has the focus now (e.g. the desktop is focused),
    /// forward starts on the first item – the most recent window.
    public init(count: Int, reverse: Bool = false, firstIsCurrent: Bool = true) {
        self.count = max(0, count)
        switch self.count {
        case 0: index = nil
        case 1: index = 0
        default: index = reverse ? self.count - 1 : (firstIsCurrent ? 1 : 0)
        }
    }

    public mutating func next() { move(by: 1) }
    public mutating func previous() { move(by: -1) }

    /// Selects an item directly (mouse hover / click); out-of-range values are ignored.
    public mutating func select(_ newIndex: Int) {
        guard (0..<count).contains(newIndex) else { return }
        index = newIndex
    }

    private mutating func move(by offset: Int) {
        guard let current = index, count > 0 else { return }
        index = ((current + offset) % count + count) % count
    }
}
