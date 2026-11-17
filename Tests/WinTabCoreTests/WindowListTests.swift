// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import WinTabCore

@Suite struct WindowListTests {
    let finder = AppInfo(pid: 10, name: "Finder")
    let safari = AppInfo(pid: 20, name: "Safari")
    let notes = AppInfo(pid: 30, name: "Notes", isHidden: true)
    let wintab = AppInfo(pid: 99, name: "WinTab")

    func frame(_ x: Double) -> Rect { Rect(x: x, y: 0, width: 800, height: 600) }

    func ax(_ token: Int, id: UInt32?, pid: Int32, title: String, subrole: String? = "AXStandardWindow",
            minimized: Bool = false, bounds: Rect? = nil) -> AXWindow {
        AXWindow(token: token, windowID: id, pid: pid, title: title, subrole: subrole, isMinimized: minimized,
                 bounds: bounds)
    }

    @Test func ordersVisibleWindowsFrontToBack() {
        let onScreen = [
            OnScreenWindow(windowID: 2, pid: 20, bounds: frame(0)),
            OnScreenWindow(windowID: 1, pid: 10, bounds: frame(10)),
            OnScreenWindow(windowID: 3, pid: 20, bounds: frame(20)),
        ]
        let axWindows = [
            ax(0, id: 1, pid: 10, title: "Downloads"),
            ax(1, id: 2, pid: 20, title: "GitHub"),
            ax(2, id: 3, pid: 20, title: "Apple"),
        ]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder, safari])
        #expect(list.map(\.title) == ["GitHub", "Downloads", "Apple"])
        #expect(list.map(\.appName) == ["Safari", "Finder", "Safari"])
    }

    @Test func minimizedAndHiddenGoLast() {
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))]
        let axWindows = [
            ax(0, id: 5, pid: 20, title: "Minimized page", minimized: true),
            ax(1, id: 1, pid: 10, title: "Desktop"),
            ax(2, id: 7, pid: 30, title: "Shopping list"),
        ]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder, safari, notes])
        #expect(list.map(\.title) == ["Desktop", "Shopping list", "Minimized page"])
        #expect(list[1].isAppHidden)
        #expect(list[2].isMinimized)
    }

    @Test func skipsWindowsOnOtherSpaces() {
        // Not on screen, not minimized, app not hidden → another Space (milestone 4).
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))]
        let axWindows = [ax(0, id: 1, pid: 10, title: "Here"), ax(1, id: 2, pid: 10, title: "Elsewhere")]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder])
        #expect(list.map(\.title) == ["Here"])
    }

    @Test func skipsNonStandardWindowsAndOwnWindows() {
        let onScreen = [
            OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0)),
            OnScreenWindow(windowID: 2, pid: 10, bounds: frame(10)),
            OnScreenWindow(windowID: 3, pid: 99, bounds: frame(20)),
            OnScreenWindow(windowID: 4, pid: 10, bounds: frame(30)),
        ]
        let axWindows = [
            ax(0, id: 1, pid: 10, title: "Inspector", subrole: "AXFloatingWindow"),
            ax(1, id: 2, pid: 10, title: "Copy", subrole: "AXDialog"),
            ax(2, id: 3, pid: 99, title: "Switcher"),
            ax(3, id: 4, pid: 10, title: "No subrole", subrole: nil),
        ]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder, wintab],
                                           excludedPID: 99)
        #expect(list.map(\.title) == ["Copy"])
    }

    @Test func ignoresOverlaysAndTinyWindows() {
        let onScreen = [
            OnScreenWindow(windowID: 1, pid: 10, layer: 25, bounds: frame(0)),
            OnScreenWindow(windowID: 2, pid: 10, bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
            OnScreenWindow(windowID: 3, pid: 10, bounds: frame(0), alpha: 0),
        ]
        let axWindows = [ax(0, id: 1, pid: 10, title: "A"), ax(1, id: 2, pid: 10, title: "B"),
                         ax(2, id: 3, pid: 10, title: "C")]
        #expect(WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder]).isEmpty)
    }

    @Test func matchesByFrameWhenWindowIDUnknown() {
        let onScreen = [
            OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0)),
            OnScreenWindow(windowID: 2, pid: 10, bounds: frame(100)),
        ]
        let axWindows = [
            ax(0, id: nil, pid: 10, title: "Back", bounds: frame(100.4)),
            ax(1, id: nil, pid: 10, title: "Front", bounds: frame(0)),
            ax(2, id: nil, pid: 10, title: "Same frame as front", bounds: frame(0)),
        ]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder])
        #expect(list.map(\.title) == ["Front", "Back"])
    }

    @Test func emptyTitleFallsBackToAppName() {
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: [ax(0, id: 1, pid: 10, title: "  ")],
                                           apps: [finder])
        #expect(list.first?.displayTitle == "Finder")
        #expect(list.first?.token == 0)
    }

    @Test func duplicateIDsAreListedOnce() {
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))]
        let axWindows = [ax(0, id: 1, pid: 10, title: "A"), ax(1, id: 1, pid: 10, title: "A again")]
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder])
        #expect(list.map(\.title) == ["A"])
    }
}
