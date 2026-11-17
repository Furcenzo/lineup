// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ApplicationServices
import CPrivate
import WinTabCore

/// Windows on other Spaces (desktops and fullscreen apps), from the WindowServer's private Space APIs.
enum Spaces {
    /// Windows on all Spaces of all displays (also the current ones – the switcher prefers its own on-screen
    /// list for those), front to back per Space. Empty when the private APIs are unavailable.
    static func windowsOnAllSpaces() -> [OnScreenWindow] {
        guard let displays = WTCopyManagedDisplaySpaces() as? [[String: Any]] else { return [] }
        let spaceIDs = displays.flatMap { ($0["Spaces"] as? [[String: Any]] ?? []).compactMap { $0["id64"] as? UInt64 } }
        guard !spaceIDs.isEmpty, let windowIDs = WTCopyWindowsOnSpaces(spaceIDs as CFArray) as? [UInt32],
              !windowIDs.isEmpty else { return [] }
        // CGWindowListCreateDescriptionFromArray wants the window IDs stored as the array's raw values.
        var values = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &values, values.count, nil),
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [] }
        return descriptions.compactMap(WindowSource.onScreenWindow(from:))
    }
}

/// Finds the accessibility elements of windows on other Spaces. `kAXWindowsAttribute` only lists windows
/// of the current Space (and minimized ones), so the elements are searched by building elements from
/// "remote tokens" with increasing element IDs until the wanted windows turn up (AltTab's technique).
///
/// One search costs up to `budget` per app, so it runs on a background queue; found elements are cached
/// per window ID and used from the next switcher opening on. Elements stay valid while the window exists.
@MainActor
final class RemoteWindowSearch {
    /// Longest time one search may spend on one app.
    nonisolated static let budget: Duration = .milliseconds(200)
    /// The same app is searched again at most this often (windows that are no windows – toolbars, helper
    /// windows of fullscreen apps – are never found and would otherwise be searched on every opening).
    static let retryInterval: Duration = .seconds(5)

    private var elements = [CGWindowID: AXUIElement]()
    /// Where the next search of an app continues (element IDs of long-running apps can be large).
    private var nextElementID = [pid_t: UInt64]()
    private var lastSearch = [pid_t: ContinuousClock.Instant]()
    /// The windows the last search of an app was looking for.
    private var lastWanted = [pid_t: Set<CGWindowID>]()
    private var inFlight = Set<pid_t>()
    private let queue = DispatchQueue(label: "io.github.furcenzo.wintab.remote-window-search", qos: .userInitiated)

    func element(for windowID: CGWindowID) -> AXUIElement? { elements[windowID] }
    var knownWindowIDs: Set<CGWindowID> { Set(elements.keys) }

    /// Forgets elements of windows that are on no Space any more (closed, or moved to the current Space).
    func prune(keeping windowIDs: Set<CGWindowID>) {
        elements = elements.filter { windowIDs.contains($0.key) }
    }

    /// Starts background searches for the given windows (app → window IDs).
    func search(_ wanted: [pid_t: Set<CGWindowID>]) {
        let now = ContinuousClock.now
        for (pid, windowIDs) in wanted where !inFlight.contains(pid) {
            if let last = lastSearch[pid], now - last < Self.retryInterval { continue }
            inFlight.insert(pid)
            lastSearch[pid] = now
            // New windows to look for may have any element ID – start from the beginning. Only a search for
            // the same windows continues where the last one stopped.
            let isSameSearch = windowIDs.isSubset(of: lastWanted[pid] ?? [])
            lastWanted[pid] = windowIDs
            let startID = isSameSearch ? nextElementID[pid] ?? 0 : 0
            let request = SearchRequest(pid: pid, windowIDs: windowIDs, startID: startID)
            queue.async {
                let result = request.run()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.finish(pid: pid, result: result) }
                }
            }
        }
    }

    private func finish(pid: pid_t, result: SearchResult) {
        inFlight.remove(pid)
        nextElementID[pid] = result.nextID
        for (windowID, box) in result.found { elements[windowID] = box.element }
        log.debug("remote search pid \(pid): found \(result.found.count), next id \(result.nextID), \(result.duration, privacy: .public)")
    }
}

/// Wraps an AXUIElement to move it between threads (AXUIElement is a thread-safe CF type).
private struct ElementBox: @unchecked Sendable {
    let element: AXUIElement
}

private struct SearchResult: Sendable {
    var found: [CGWindowID: ElementBox]
    var nextID: UInt64
    var duration: Duration
}

private struct SearchRequest: Sendable {
    /// Element IDs are tried up to here, then the search starts at 0 again.
    static let maxElementID: UInt64 = 2_000_000

    let pid: pid_t
    let windowIDs: Set<CGWindowID>
    let startID: UInt64

    func run() -> SearchResult {
        let start = ContinuousClock.now
        var remaining = windowIDs
        var found = [CGWindowID: ElementBox]()
        var id = startID
        var wrapped = false
        while !remaining.isEmpty {
            if id & 63 == 0, ContinuousClock.now - start > RemoteWindowSearch.budget { break }
            if let element = WTCreateAXElementWithRemoteToken(pid, id) {
                AXUIElementSetMessagingTimeout(element, 0.1)
                var windowID: CGWindowID = 0
                // Child elements report their window's ID too – only the AXWindow itself counts.
                if _AXUIElementGetWindow(element, &windowID) == .success, remaining.contains(windowID),
                   element.string(kAXRoleAttribute) == kAXWindowRole {
                    found[windowID] = ElementBox(element: element)
                    remaining.remove(windowID)
                }
            }
            id += 1
            if id > Self.maxElementID {
                if wrapped { break }
                wrapped = true
                id = 0
            }
        }
        // Everything found: the next search (for other windows) may as well start from the beginning.
        return SearchResult(found: found, nextID: remaining.isEmpty ? 0 : id, duration: ContinuousClock.now - start)
    }
}
