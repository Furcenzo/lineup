// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import WinTabCore

@Suite struct GridLayoutTests {
    func fit(_ count: Int, width: Double = 1000, height: Double = 1000) -> GridLayout {
        GridLayout.fit(count: count, tileWidth: 100, tileHeight: 100, spacing: 0,
                       availableWidth: width, availableHeight: height)
    }

    @Test func noTiles() {
        #expect(fit(0) == GridLayout(columns: 1, rows: 0, scale: 1))
    }

    @Test func fewTilesInOneRow() {
        #expect(fit(3) == GridLayout(columns: 3, rows: 1, scale: 1))
    }

    @Test func rowsAreBalanced() {
        // 10 columns fit; 13 tiles → 2 rows of 7 + 6 instead of 10 + 3.
        #expect(fit(13) == GridLayout(columns: 7, rows: 2, scale: 1))
    }

    @Test func shrinksWhenTooManyRows() {
        // 5 columns × 2 rows fit at full size; 15 tiles need smaller tiles.
        let layout = fit(15, width: 500, height: 200)
        #expect(layout.scale < 1)
        #expect(Double(layout.rows) * 100 * layout.scale <= 200)
        #expect(layout.columns * layout.rows >= 15)
    }

    @Test func neverBelowMinimumScale() {
        let layout = fit(500, width: 500, height: 200)
        #expect(layout.scale == 0.5)
        #expect(layout.columns * layout.rows >= 500)
    }

    @Test func spacingCounts() {
        // 3 tiles of 100 + 2 gaps of 10 = 320 > 300 → only 2 columns fit.
        let layout = GridLayout.fit(count: 3, tileWidth: 100, tileHeight: 100, spacing: 10,
                                    availableWidth: 300, availableHeight: 1000)
        #expect(layout == GridLayout(columns: 2, rows: 2, scale: 1))
    }

    @Test func aspectFitKeepsRatio() {
        #expect(aspectFit(width: 1600, height: 1000, maxWidth: 400, maxHeight: 400) == (400, 250))
        #expect(aspectFit(width: 500, height: 1000, maxWidth: 400, maxHeight: 250) == (125, 250))
        #expect(aspectFit(width: 0, height: 1000, maxWidth: 400, maxHeight: 250) == (1, 1))
        #expect(aspectFit(width: 10000, height: 1, maxWidth: 400, maxHeight: 250) == (400, 1))
    }
}
