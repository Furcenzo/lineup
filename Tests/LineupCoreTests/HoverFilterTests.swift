// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import LineupCore

@Suite struct HoverFilterTests {
    @Test func tileUnderStillPointerIsIgnoredUntilLeft() {
        var f = HoverFilter()
        f.reset(x: 100, y: 100)
        let selects1 = f.enter("a", x: 100, y: 101)   // appeared under the pointer (small jitter)
        #expect(!selects1)
        #expect(f.ignoredID == "a")
        let selects2 = f.enter("b", x: 300, y: 100)    // the next tile reacts
        #expect(selects2)
        f.exit("a")
        let selects3 = f.enter("a", x: 120, y: 100)    // back on the first tile after leaving it
        #expect(selects3)
    }

    @Test func movingWithinIgnoredTileDoesNothing() {
        var f = HoverFilter()
        f.reset(x: 0, y: 0)
        let selects4 = f.enter("a", x: 0, y: 0)
        #expect(!selects4)
        let selects5 = f.enter("a", x: 40, y: 0)      // a repeated enter of the same tile stays ignored
        #expect(!selects5)
        f.exit("b")
        #expect(f.ignoredID == "a")
    }

    @Test func pointerAlreadyMovingSelects() {
        var f = HoverFilter()
        f.reset(x: 0, y: 0)
        let selects6 = f.enter("a", x: 50, y: 0)
        #expect(selects6)
        #expect(f.ignoredID == nil)
    }

    @Test func resetForgetsTheIgnoredTile() {
        var f = HoverFilter()
        f.reset(x: 0, y: 0)
        let selects7 = f.enter("a", x: 0, y: 0)
        #expect(!selects7)
        f.reset(x: 0, y: 0)                      // tiles moved (a window was closed)
        let selects8 = f.enter("b", x: 0, y: 0)
        #expect(!selects8)
        let selects9 = f.enter("a", x: 200, y: 0)
        #expect(selects9)
    }
}
