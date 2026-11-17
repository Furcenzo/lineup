// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import LineupCore

@Suite struct WindowListTests {
    let finder = AppInfo(pid: 10, name: "Finder")
    let safari = AppInfo(pid: 20, name: "Safari")
    let notes = AppInfo(pid: 30, name: "Notes", isHidden: true)
    let lineup = AppInfo(pid: 99, name: "Lineup")

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
        let list = WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: [finder, lineup],
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

    @Test func windowsOnOtherSpacesComeAfterVisibleOnes() {
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))]
        let otherSpaces = [
            OnScreenWindow(windowID: 8, pid: 20, bounds: frame(0)),
            OnScreenWindow(windowID: 9, pid: 10, bounds: frame(0)),
        ]
        let axWindows = [
            ax(0, id: 9, pid: 10, title: "Finder elsewhere"),
            ax(1, id: 1, pid: 10, title: "Here"),
            ax(2, id: 8, pid: 20, title: "Fullscreen video"),
            ax(3, id: 5, pid: 20, title: "Minimized", minimized: true),
        ]
        let list = WindowListBuilder.build(onScreen: onScreen, otherSpaces: otherSpaces, axWindows: axWindows,
                                           apps: [finder, safari])
        #expect(list.map(\.title) == ["Here", "Fullscreen video", "Finder elsewhere", "Minimized"])
        #expect(list.map(\.isOnOtherSpace) == [false, true, true, false])
    }

    @Test func otherSpaceWindowsNeedTheirID() {
        // Without a window ID there is no way to tell which Space a window is on.
        let otherSpaces = [OnScreenWindow(windowID: 8, pid: 20, bounds: frame(0))]
        let list = WindowListBuilder.build(onScreen: [], otherSpaces: otherSpaces,
                                           axWindows: [ax(0, id: nil, pid: 20, title: "?", bounds: frame(0))],
                                           apps: [safari])
        #expect(list.isEmpty)
    }

    @Test func windowOnScreenWinsOverOtherSpaceEntry() {
        // An app assigned to all Spaces shows up in both lists.
        let window = OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0))
        let list = WindowListBuilder.build(onScreen: [window], otherSpaces: [window],
                                           axWindows: [ax(0, id: 1, pid: 10, title: "Everywhere")], apps: [finder])
        #expect(list.count == 1)
        #expect(list[0].isOnOtherSpace == false)
    }

    @Test func windowsToLookUpSkipsKnownHelperAndForeignWindows() {
        let otherSpaces = [
            OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0)),
            OnScreenWindow(windowID: 2, pid: 10, bounds: frame(0)),
            OnScreenWindow(windowID: 3, pid: 10, layer: 25, bounds: frame(0)),
            OnScreenWindow(windowID: 4, pid: 77, bounds: frame(0)),
            OnScreenWindow(windowID: 5, pid: 20, bounds: Rect(x: 0, y: 0, width: 1470, height: 20)),
            OnScreenWindow(windowID: 6, pid: 20, bounds: frame(0)),
        ]
        let result = WindowListBuilder.windowsToLookUp(otherSpaces: otherSpaces, knownIDs: [1],
                                                       appPIDs: [10, 20])
        #expect(result == [10: [2], 20: [6]])
    }

    @Test func optionsLeaveOutMinimizedHiddenAndExcluded() {
        let finder = AppInfo(pid: 10, name: "Finder", bundleID: "com.apple.finder")
        let notes = AppInfo(pid: 30, name: "Notes", isHidden: true, bundleID: "com.apple.Notes")
        let mail = AppInfo(pid: 40, name: "Mail", bundleID: "com.apple.mail")
        let onScreen = [OnScreenWindow(windowID: 1, pid: 10, bounds: frame(0)),
                        OnScreenWindow(windowID: 4, pid: 40, bounds: frame(0))]
        let axWindows = [
            ax(0, id: 1, pid: 10, title: "Desktop"),
            ax(1, id: 2, pid: 10, title: "Minimized", minimized: true),
            ax(2, id: 3, pid: 30, title: "Hidden"),
            ax(3, id: 4, pid: 40, title: "Inbox"),
        ]
        let apps = [finder, notes, mail]
        func titles(_ options: ListOptions) -> [String] {
            WindowListBuilder.build(onScreen: onScreen, axWindows: axWindows, apps: apps, options: options).map(\.title)
        }
        #expect(titles(ListOptions()) == ["Desktop", "Inbox", "Hidden", "Minimized"])
        #expect(titles(ListOptions(includeMinimized: false)) == ["Desktop", "Inbox", "Hidden"])
        #expect(titles(ListOptions(includeHiddenApps: false)) == ["Desktop", "Inbox", "Minimized"])
        #expect(titles(ListOptions(excludedBundleIDs: ["com.apple.mail"])) == ["Desktop", "Hidden", "Minimized"])
    }

    @Test func appsWithoutBundleIDAreNeverExcluded() {
        #expect(ListOptions(excludedBundleIDs: ["x"]).includes(AppInfo(pid: 1, name: "Script")))
    }

    @Test func onlyBundleIDsListsJustThoseApps() {
        var options = ListOptions()
        options.onlyBundleIDs = ["com.apple.Safari"]
        #expect(options.includes(AppInfo(pid: 1, name: "Safari", bundleID: "com.apple.Safari")))
        #expect(!options.includes(AppInfo(pid: 2, name: "Mail", bundleID: "com.apple.mail")))
        #expect(!options.includes(AppInfo(pid: 3, name: "Script")))
    }
}
