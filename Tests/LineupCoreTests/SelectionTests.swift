// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import LineupCore

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

    @Test func removingItemsKeepsAValidSelection() {
        var selection = Selection(count: 4)
        selection.select(2)
        selection.remove(at: 0)       // before the selection → it follows its item
        #expect(selection.index == 1)
        #expect(selection.count == 3)
        selection.remove(at: 2)       // after → unchanged
        #expect(selection.index == 1)
        selection.remove(at: 1)       // the selected one, now the last → previous item
        #expect(selection.index == 0)
        selection.remove(at: 5)       // out of range → ignored
        #expect(selection.count == 1)
        selection.remove(at: 0)
        #expect(selection.index == nil)
        #expect(selection.count == 0)
    }

    @Test func removingTheSelectedItemSelectsTheNextOne() {
        var selection = Selection(count: 3)
        selection.select(1)
        selection.remove(at: 1)
        #expect(selection.index == 1)
    }
}
