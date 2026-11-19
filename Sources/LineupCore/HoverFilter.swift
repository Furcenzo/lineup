// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

/// Decides which mouse hovers select a tile. When the switcher appears (or its tiles move) under a mouse
/// pointer that stands still, the tile under the pointer must not grab the selection – the user is using
/// the keyboard. That tile is ignored until the pointer leaves it; every other tile reacts at once.
public struct HoverFilter: Sendable {
    /// Pointer movement smaller than this (points) counts as standing still – touchpads jitter.
    public static let tolerance = 3.0

    /// Where the pointer was when the tiles appeared; nil once the first tile was entered.
    private var anchor: (x: Double, y: Double)?
    /// The tile that was under the pointer when the tiles appeared.
    public private(set) var ignoredID: String?

    public init() {}

    /// The tiles appeared or moved, with the pointer at (x, y).
    public mutating func reset(x: Double, y: Double) {
        anchor = (x, y)
        ignoredID = nil
    }

    /// The pointer entered a tile at (x, y); returns true when that tile should be selected.
    public mutating func enter(_ id: String, x: Double, y: Double) -> Bool {
        if let anchor {
            self.anchor = nil
            if abs(x - anchor.x) <= Self.tolerance && abs(y - anchor.y) <= Self.tolerance {
                ignoredID = id
                return false
            }
        }
        return id != ignoredID
    }

    /// The pointer left a tile.
    public mutating func exit(_ id: String) {
        if id == ignoredID { ignoredID = nil }
    }
}
