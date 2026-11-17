// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import CPrivate

/// `LINEUP_SPACES=1`: prints what the private Space APIs report (for checking a new macOS version).
@MainActor
enum DebugSpaces {
    /// CGWindowListCreateDescriptionFromArray wants the window IDs stored as the array's raw values.
    static func windowDescriptions(_ ids: [CGWindowID]) -> [[String: Any]] {
        var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &values, values.count, nil) else { return [] }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
    }

    static func run() {
        print("Private APIs available: \(WTPrivateAPIsAvailable())")
        guard let displays = WTCopyManagedDisplaySpaces() as? [[String: Any]] else {
            print("CGSCopyManagedDisplaySpaces: unavailable")
            return
        }
        var allSpaces = [UInt64]()
        for display in displays {
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? UInt64
            print("Display \(display["Display Identifier"] ?? "?") current=\(current.map(String.init) ?? "-")")
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                let id = space["id64"] as? UInt64 ?? 0
                allSpaces.append(id)
                print("  space \(id) type=\(space["type"] ?? "?")")
            }
        }
        guard let ids = WTCopyWindowsOnSpaces(allSpaces as CFArray) as? [UInt32] else {
            print("CGSCopyWindowsWithOptionsAndTags: unavailable")
            return
        }
        let descriptions = windowDescriptions(ids)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var regularPIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier))
        regularPIDs.remove(ownPID)
        print("Windows on all Spaces: \(ids.count), with description: \(descriptions.count)")
        var missingByPID = [pid_t: Set<CGWindowID>]()
        for info in descriptions {
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard regularPIDs.contains(pid), layer == 0 else { continue }
            let id = info[kCGWindowNumber as String] as? UInt32 ?? 0
            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let name = info[kCGWindowName as String] as? String ?? ""
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            print("  w\(id) pid=\(pid) [\(owner)] \"\(name)\" onscreen=\(onScreen) \(bounds["Width"] ?? 0)x\(bounds["Height"] ?? 0)")
            missingByPID[pid, default: []].insert(id)
        }
        // Which of them does kAXWindowsAttribute know? The rest needs the remote token search.
        for (pid, ids) in missingByPID.sorted(by: { $0.key < $1.key }) {
            let app = AXUIElementCreateApplication(pid)
            let known = Set(app.array(kAXWindowsAttribute).compactMap { FocusTracker.windowID(of: $0) })
            let missing = ids.subtracting(known)
            guard !missing.isEmpty else { continue }
            let start = ContinuousClock.now
            var found = [CGWindowID: String]()
            var tried: UInt64 = 0
            for elementID in UInt64(0)..<UInt64(2000) where found.count < missing.count {
                tried = elementID
                guard let element = WTCreateAXElementWithRemoteToken(pid, elementID),
                      let id = FocusTracker.windowID(of: element), missing.contains(id),
                      element.string(kAXRoleAttribute) == kAXWindowRole else { continue }
                found[id] = "\(element.string(kAXSubroleAttribute) ?? "?") \"\(element.string(kAXTitleAttribute) ?? "")\""
            }
            print("pid \(pid): AX knows \(known.count), missing \(missing.sorted()), remote token found \(found) after \(tried + 1) ids in \(ContinuousClock.now - start)")
        }
    }
}
