// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import WinTabCore

@Suite struct SelectionTests {
    @Test func emptyListSelectsNothing() {
        var selection = Selection(count: 0)
        #expect(selection.index == nil)
        selection.next()
        selection.previous()
        #expect(selection.index == nil)
    }

    @Test func singleWindowIsSelected() {
        var selection = Selection(count: 1)
        #expect(selection.index == 0)
        selection.next()
        #expect(selection.index == 0)
        #expect(Selection(count: 1, reverse: true).index == 0)
    }

    @Test func forwardStartsOnPreviousWindow() {
        #expect(Selection(count: 4).index == 1)
    }

    @Test func forwardStartsOnFirstWhenNoWindowIsFocused() {
        #expect(Selection(count: 4, firstIsCurrent: false).index == 0)
        #expect(Selection(count: 4, reverse: true, firstIsCurrent: false).index == 3)
    }

    @Test func reverseStartsOnLastWindow() {
        #expect(Selection(count: 4, reverse: true).index == 3)
    }

    @Test func wrapsAroundBothWays() {
        var selection = Selection(count: 3)
        selection.next()
        #expect(selection.index == 2)
        selection.next()
        #expect(selection.index == 0)
        selection.previous()
        #expect(selection.index == 2)
    }

    @Test func directSelectionIgnoresOutOfRange() {
        var selection = Selection(count: 3)
        selection.select(2)
        #expect(selection.index == 2)
        selection.select(3)
        selection.select(-1)
        #expect(selection.index == 2)
    }
}
