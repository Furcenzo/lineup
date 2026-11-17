// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import CPrivate
import ScreenCaptureKit
import WinTabCore

/// The Screen Recording permission (System Settings → Privacy & Security → Screen & System Audio Recording),
/// needed for window previews. Without it WinTab shows app icons.
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (only the first time) and registers WinTab in the settings list.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

/// Window thumbnails taken with ScreenCaptureKit, cached per window ID.
///
/// The switcher shows the cached image at once and asks for fresh ones when it opens; a window is also
/// captured when it loses the focus, so the cache is fairly fresh even for windows that get minimized or
/// hidden later (those can't be captured any more).
@MainActor
final class ThumbnailStore {
    /// Largest thumbnail in pixels (the tile shows it at half that size on a Retina display).
    nonisolated static let maxPixelWidth: Double = 480
    nonisolated static let maxPixelHeight: Double = 300
    /// Thumbnails of windows not listed for this long are dropped.
    static let maxAge: Duration = .seconds(30 * 60)

    /// Previews switched on in the menu and the permission granted.
    var isEnabled = false
    /// Called on the main actor for every new thumbnail.
    var onUpdate: (CGWindowID, NSImage) -> Void = { _, _ in }

    private var images = [CGWindowID: (image: NSImage, time: ContinuousClock.Instant)]()
    private var inFlight = Set<CGWindowID>()

    func image(for windowID: CGWindowID) -> NSImage? { images[windowID]?.image }

    /// Captures the given windows (not minimized ones or those of hidden apps) and reports each through
    /// `onUpdate` as soon as it is ready.
    func refresh(_ windowIDs: [CGWindowID]) {
        guard isEnabled else { return }
        let wanted = windowIDs.filter { !inFlight.contains($0) }
        guard !wanted.isEmpty else { return }
        inFlight.formUnion(wanted)
        Task {
            let start = ContinuousClock.now
            var captured = 0
            defer {
                inFlight.subtract(wanted)
                log.debug("captured \(captured)/\(wanted.count) thumbnails in \(ContinuousClock.now - start, privacy: .public)")
            }
            // All windows, also those on other Spaces (they can be captured too).
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            let requests = wanted.map { CaptureRequest(id: $0, window: windows[$0]) }
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for request in requests {
                    group.addTask { (request.id, await request.capture()) }
                }
                for await (id, image) in group {
                    guard let image else { continue }
                    let pointSize = NSSize(width: Double(image.width) / 2, height: Double(image.height) / 2)
                    let thumbnail = NSImage(cgImage: image, size: pointSize)
                    images[id] = (thumbnail, .now)
                    captured += 1
                    onUpdate(id, thumbnail)
                }
            }
        }
    }

    /// Forgets thumbnails of windows that were not seen for a long time (closed windows).
    func prune(keeping visibleIDs: Set<CGWindowID>) {
        let now = ContinuousClock.now
        for (id, entry) in images where !visibleIDs.contains(id) && now - entry.time > Self.maxAge {
            images[id] = nil
        }
    }

    func removeAll() {
        images = [:]
    }
}

/// One window to capture. ScreenCaptureKit objects are immutable descriptions, safe to hand to a child task.
private struct CaptureRequest: @unchecked Sendable {
    let id: CGWindowID
    let window: SCWindow?

    /// ScreenCaptureKit first; windows it can't capture (e.g. fullscreen apps on another Space) through the
    /// private CGSHWCaptureWindowList, scaled down.
    func capture() async -> CGImage? {
        if let window, let image = await captureWithScreenCaptureKit(window) { return image }
        return captureWithWindowServer()
    }

    private func captureWithWindowServer() -> CGImage? {
        guard let image = WTCopyWindowImage(id), image.width > 1, image.height > 1 else { return nil }
        let size = aspectFit(width: Double(image.width), height: Double(image.height),
                             maxWidth: ThumbnailStore.maxPixelWidth, maxHeight: ThumbnailStore.maxPixelHeight)
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    private func captureWithScreenCaptureKit(_ window: SCWindow) async -> CGImage? {
        let size = aspectFit(width: window.frame.width, height: window.frame.height,
                             maxWidth: ThumbnailStore.maxPixelWidth, maxHeight: ThumbnailStore.maxPixelHeight)
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
