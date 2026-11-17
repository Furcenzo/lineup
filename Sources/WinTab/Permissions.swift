// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ApplicationServices
import SwiftUI

/// The Accessibility permission (System Settings → Privacy & Security → Accessibility). WinTab needs it
/// to read other apps' windows, raise them and watch the keyboard for the hotkey.
@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Adds WinTab to the Accessibility list in System Settings (switched off) and opens the settings page.
    static func request() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt (a global var Swift 6
        // refuses to read). Asking with the prompt registers WinTab in the list.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openSettings()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// A small window explaining why the permission is needed; it closes itself once the permission is granted.
@MainActor
final class PermissionWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "WinTab – Accessibility Permission")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionView())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

private struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.square.on.square")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                Text("WinTab needs the Accessibility permission")
                    .font(.title3.bold())
            }
            Text("It lets WinTab notice the ⌥Tab shortcut, list the windows of your apps and bring the one you pick to the front. WinTab does not record or send anything.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click “Open System Settings”.")
                Text("2. In Privacy & Security → Accessibility, turn on WinTab.")
                Text("3. This window closes by itself and ⌥Tab starts working.")
            }
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Open System Settings") { AccessibilityPermission.request() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
