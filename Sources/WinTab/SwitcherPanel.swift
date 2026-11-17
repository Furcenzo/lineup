// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import SwiftUI
import WinTabCore

/// What the switcher overlay shows.
@MainActor @Observable
final class SwitcherModel {
    struct Item: Identifiable {
        let id: String
        let windowID: UInt32?
        let title: String
        let appName: String
        let icon: NSImage?
        let isMinimized: Bool
        var thumbnail: NSImage?
    }

    var items = [Item]()
    var selectedIndex: Int?
    /// Big tiles with window thumbnails instead of app icons.
    var showsPreviews = false
    var layout = GridLayout(columns: 1, rows: 1, scale: 1)
    /// Mouse hover over an item.
    var onHover: (Int) -> Void = { _ in }
    /// Mouse click on an item.
    var onClick: (Int) -> Void = { _ in }

    var metrics: TileMetrics { TileMetrics(previews: showsPreviews, scale: layout.scale) }

    func setThumbnail(_ image: NSImage, for windowID: UInt32) {
        guard let index = items.firstIndex(where: { $0.windowID == windowID }) else { return }
        items[index].thumbnail = image
    }
}

/// Sizes of one tile; tiles shrink (`scale`) when many windows have to fit on the screen.
struct TileMetrics {
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 18

    let tileWidth: CGFloat
    let tileHeight: CGFloat
    /// The box the thumbnail (or the big icon) is fitted into.
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    /// The app icon: alone in icon mode, a badge on the thumbnail in preview mode.
    let iconSize: CGFloat

    init(previews: Bool, scale: Double = 1) {
        let s = CGFloat(scale)
        if previews {
            (tileWidth, tileHeight, imageWidth, imageHeight, iconSize) = (232 * s, 196 * s, 216 * s, 138 * s, 36 * s)
        } else {
            (tileWidth, tileHeight, imageWidth, imageHeight, iconSize) = (128 * s, 124 * s, 72 * s, 72 * s, 72 * s)
        }
    }
}

/// The floating overlay. It is a non-activating panel: it never becomes the key window and never
/// activates WinTab, so the frontmost app keeps its focus while the switcher is open.
@MainActor
final class SwitcherPanel: NSPanel {
    let model = SwitcherModel()
    private let hostingView: NSHostingView<SwitcherView>

    init() {
        hostingView = FirstMouseHostingView(rootView: SwitcherView(model: model))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The screen the switcher appears on.
    static func screen(for choice: SwitcherScreen) -> NSScreen? {
        switch choice {
        case .mouse:
            NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main ?? NSScreen.screens.first
        case .primary:
            // The first screen is the one with the menu bar in System Settings → Displays.
            NSScreen.screens.first
        }
    }

    /// Sizes the panel for the current items and shows it centered on the chosen screen.
    func present(on choice: SwitcherScreen = .mouse) {
        guard let screen = Self.screen(for: choice) else { return }
        layout(for: screen.visibleFrame)
        let size = hostingView.fittingSize
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }

    /// Fits the grid into 90 % of the screen width and 80 % of its height (minus the title line).
    func layout(for visibleFrame: NSRect) {
        let full = TileMetrics(previews: model.showsPreviews)
        let titleLine: CGFloat = 34
        model.layout = GridLayout.fit(
            count: model.items.count, tileWidth: full.tileWidth, tileHeight: full.tileHeight,
            spacing: TileMetrics.spacing,
            availableWidth: visibleFrame.width * 0.9 - 2 * TileMetrics.padding,
            availableHeight: visibleFrame.height * 0.8 - 2 * TileMetrics.padding - titleLine)
        hostingView.layoutSubtreeIfNeeded()
    }

    /// Renders the panel content into a PNG without showing it (debugging, no screen recording needed).
    func snapshot(to url: URL) throws {
        layout(for: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
        hostingView.setFrameSize(hostingView.fittingSize)
        hostingView.layoutSubtreeIfNeeded()
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Lets the first click on the (never key) panel reach the SwiftUI views.
private final class FirstMouseHostingView: NSHostingView<SwitcherView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SwitcherView: View {
    let model: SwitcherModel

    var body: some View {
        VStack(spacing: 10) {
            if model.items.isEmpty {
                Text("No windows on this desktop")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            } else {
                grid
                Text(verbatim: selectedTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: gridWidth)
            }
        }
        .padding(TileMetrics.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }

    private var selectedTitle: String {
        guard let index = model.selectedIndex, model.items.indices.contains(index) else { return "" }
        let item = model.items[index]
        return item.title == item.appName ? item.title : "\(item.appName) – \(item.title)"
    }

    private var gridWidth: CGFloat {
        let columns = CGFloat(max(1, model.layout.columns))
        return columns * model.metrics.tileWidth + (columns - 1) * TileMetrics.spacing
    }

    /// An item with its position. Views get the item itself, never an index to look up later: SwiftUI may
    /// still evaluate a row of the old list after `items` changed, and a stale index would crash.
    private struct Entry: Identifiable {
        let index: Int
        let item: SwitcherModel.Item
        var id: String { item.id }
    }

    private var grid: some View {
        let columns = max(1, model.layout.columns)
        let entries = model.items.enumerated().map { Entry(index: $0.offset, item: $0.element) }
        let rows = stride(from: 0, to: entries.count, by: columns).map {
            Array(entries[$0..<min($0 + columns, entries.count)])
        }
        let metrics = model.metrics
        return VStack(alignment: .leading, spacing: TileMetrics.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: TileMetrics.spacing) {
                    ForEach(row) { entry in
                        tile(entry, metrics: metrics)
                    }
                }
            }
        }
    }

    private func tile(_ entry: Entry, metrics: TileMetrics) -> some View {
        let item = entry.item
        let index = entry.index
        let isSelected = index == model.selectedIndex
        return VStack(spacing: 6) {
            image(for: item, metrics: metrics)
                .frame(width: metrics.imageWidth, height: metrics.imageHeight)
            Text(verbatim: item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(8)
        .frame(width: metrics.tileWidth, height: metrics.tileHeight, alignment: .top)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.35)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in if inside { model.onHover(index) } }
        .onTapGesture { model.onClick(index) }
    }

    /// Preview mode: the thumbnail with the app icon as a badge (or a big icon until there is a thumbnail).
    /// Icon mode: the app icon.
    @ViewBuilder
    private func image(for item: SwitcherModel.Item, metrics: TileMetrics) -> some View {
        if model.showsPreviews, let thumbnail = item.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .opacity(item.isMinimized ? 0.6 : 1)
                .frame(width: metrics.imageWidth, height: metrics.imageHeight)
                .overlay(alignment: .bottomTrailing) {
                    appIcon(item, size: metrics.iconSize)
                        .overlay(alignment: .topLeading) { minimizedBadge(item) }
                        .offset(x: 4, y: 4)
                }
        } else {
            let size = model.showsPreviews ? min(metrics.imageHeight * 0.7, 96) : metrics.iconSize
            appIcon(item, size: size)
                .opacity(item.isMinimized ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) { minimizedBadge(item) }
        }
    }

    private func appIcon(_ item: SwitcherModel.Item, size: CGFloat) -> some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "macwindow").resizable().foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func minimizedBadge(_ item: SwitcherModel.Item) -> some View {
        if item.isMinimized {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
                .font(.title3)
                .help("Minimized")
        }
    }
}
