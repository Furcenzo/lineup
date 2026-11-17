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

    /// Shows the system prompt (registers WinTab in the Accessibility list) and opens the settings page.
    static func request() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt (a global var Swift 6
        // refuses to read).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openSettings()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// A window with SwiftUI content, created on first use and reused.
@MainActor
final class HostingWindow<Content: View> {
    private var window: NSWindow?
    private let title: () -> String
    private let content: () -> Content

    init(title: @escaping () -> String, content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = title()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.center()
            self.window = window
        }
        // WinTab is an agent app – it has to activate itself to bring a window to the front.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

/// Permission onboarding: both permissions with their live state.
struct PermissionsView: View {
    let status: SystemStatus
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to WinTab")
                        .font(.title2.bold())
                    Text("Switch between windows with ⌘Tab, like Alt+Tab on Windows.")
                        .foregroundStyle(.secondary)
                }
            }
            PermissionRows(status: status)
            Text("WinTab does not store or send anything. If macOS offers to quit and reopen WinTab after you allow a permission, accept it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !status.accessibility {
                    Text("WinTab can't work without Accessibility.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

/// The two permission rows, shared by the onboarding and Settings.
struct PermissionRows: View {
    let status: SystemStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(
                title: "Accessibility",
                detail: "Required. Lets WinTab notice its keyboard shortcut, list your windows and bring the one you pick to the front.",
                isGranted: status.accessibility,
                action: AccessibilityPermission.request)
            PermissionRow(
                title: "Screen & System Audio Recording",
                detail: "Optional. For window previews – without it WinTab shows app icons.",
                isGranted: status.screenRecording,
                action: {
                    ScreenRecordingPermission.request()
                    ScreenRecordingPermission.openSettings()
                })
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isGranted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button("Allow…", action: action)
            }
        }
    }
}
