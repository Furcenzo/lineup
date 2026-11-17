// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import WinTabCore

@Suite struct RecentWindowsTests {
    func window(_ id: UInt32, minimized: Bool = false) -> SwitcherWindow {
        SwitcherWindow(token: Int(id), windowID: id, pid: 1, appName: "App", title: "W\(id)", isMinimized: minimized)
    }

    func titles(_ windows: [SwitcherWindow]) -> [String] { windows.map(\.title) }

    @Test func firstListingKeepsOnScreenOrder() {
        var recent = RecentWindows()
        let list = [window(3), window(1), window(2)]
        #expect(titles(recent.order(list)) == ["W3", "W1", "W2"])
        #expect(recent.keys == ["w3", "w1", "w2"])
    }

    @Test func touchedWindowsComeFirst() {
        var recent = RecentWindows()
        _ = recent.order([window(1), window(2), window(3)])
        recent.touch("w3")
        recent.touch("w2")
        #expect(titles(recent.order([window(1), window(2), window(3)])) == ["W2", "W3", "W1"])
    }

    @Test func touchingBeforeFirstListingStillWorks() {
        var recent = RecentWindows()
        recent.touch("w2")
        #expect(titles(recent.order([window(1), window(2), window(3)])) == ["W2", "W1", "W3"])
    }

    @Test func newWindowsGoAfterKnownOnes() {
        var recent = RecentWindows()
        _ = recent.order([window(1), window(2)])
        // Window 9 appeared in front on screen but was never seen focused.
        #expect(titles(recent.order([window(9), window(1), window(2)])) == ["W1", "W2", "W9"])
    }

    @Test func minimizedWindowsGoLast() {
        var recent = RecentWindows()
        recent.touch("w3")
        recent.touch("w2")
        recent.touch("w1")
        let list = [window(1, minimized: true), window(2), window(3)]
        #expect(titles(recent.order(list)) == ["W2", "W3", "W1"])
    }

    @Test func windowsWithoutIDKeepTheirPlaceAmongNewOnes() {
        var recent = RecentWindows()
        recent.touch("w5")
        let noID = SwitcherWindow(token: 7, windowID: nil, pid: 4, appName: "Old app", title: "No ID")
        #expect(titles(recent.order([noID, window(5)])) == ["W5", "No ID"])
    }

    @Test func removeAndCapacity() {
        var recent = RecentWindows(capacity: 3)
        for id in 1...5 { recent.touch("w\(id)") }
        #expect(recent.keys == ["w5", "w4", "w3"])
        recent.remove("w4")
        #expect(recent.keys == ["w5", "w3"])
        recent.touch("w3")
        #expect(recent.keys == ["w3", "w5"])
    }

    @Test func idHelperMatchesWindowID() {
        #expect(window(42).id == SwitcherWindow.id(windowID: 42))
    }
}
