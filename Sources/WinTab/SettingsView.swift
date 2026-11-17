// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import WinTabCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let status: SystemStatus

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Switch windows with", selection: $settings.shortcut) {
                    Text("⌘Tab – replaces the system app switcher").tag(ShortcutChoice.commandTab)
                    Text("⌥Tab – keeps the system ⌘Tab").tag(ShortcutChoice.optionTab)
                }
                .pickerStyle(.radioGroup)
                if settings.shortcut == .commandTab && status.secureInput {
                    Text("Secure input is on – ⌘Tab shows the system app switcher for now")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section("Windows") {
                Toggle("Window previews", isOn: $settings.previews)
                if settings.previews && !status.screenRecording {
                    HStack {
                        Text("Previews need the Screen Recording permission.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow…") {
                            ScreenRecordingPermission.request()
                            ScreenRecordingPermission.openSettings()
                        }
                    }
                }
                Toggle("Windows from all desktops", isOn: $settings.allSpaces)
                Toggle("Minimized windows", isOn: $settings.showMinimized)
                Toggle("Windows of hidden apps", isOn: $settings.showHiddenApps)
                Picker("Show the switcher on", selection: $settings.screen) {
                    Text("The screen with the mouse pointer").tag(SwitcherScreen.mouse)
                    Text("The main screen").tag(SwitcherScreen.primary)
                }
            }

            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button {
                            settings.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                Button("Add App…", action: addExcludedApp)
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Windows of these apps are never shown in the switcher.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { status.loginItem != .off },
                    set: { LoginItem.set($0); status.refresh() }))
                if status.loginItem == .needsApproval {
                    HStack {
                        Text("Allow WinTab in System Settings → General → Login Items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            Section("Permissions") {
                PermissionRows(status: status)
                    .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Exclude")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  bundleID != SystemAppSwitcher.bundleID,
                  !settings.excludedBundleIDs.contains(bundleID) else { continue }
            settings.excludedBundleIDs.append(bundleID)
        }
    }
}

/// An app's icon and name, found by its bundle ID (or the bundle ID when the app is not installed).
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(verbatim: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "questionmark.app")
                    .frame(width: 20, height: 20)
                Text(verbatim: bundleID)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
