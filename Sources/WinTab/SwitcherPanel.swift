// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import SwiftUI

/// What the switcher overlay shows.
@MainActor @Observable
final class SwitcherModel {
    struct Item: Identifiable {
        let id: String
        let title: String
        let appName: String
        let icon: NSImage?
        let isMinimized: Bool
    }

    var items = [Item]()
    var selectedIndex: Int?
    var columns = 1
    /// Mouse hover over an item.
    var onHover: (Int) -> Void = { _ in }
    /// Mouse click on an item.
    var onClick: (Int) -> Void = { _ in }
}

/// Layout constants shared by the view and the panel sizing.
enum SwitcherLayout {
    static let tileWidth: CGFloat = 128
    static let tileHeight: CGFloat = 124
    static let iconSize: CGFloat = 72
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 18
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

    /// Sizes the panel for the current items and shows it centered on the screen with the mouse pointer.
    func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        layout(for: screen.visibleFrame)
        let size = hostingView.fittingSize
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }

    /// Picks the number of columns so the grid fits into 90 % of the screen width.
    func layout(for visibleFrame: NSRect) {
        let available = visibleFrame.width * 0.9 - 2 * SwitcherLayout.padding
        let fitting = Int((available + SwitcherLayout.spacing) / (SwitcherLayout.tileWidth + SwitcherLayout.spacing))
        model.columns = max(1, min(model.items.count, fitting))
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
        .padding(SwitcherLayout.padding)
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
        CGFloat(model.columns) * SwitcherLayout.tileWidth + CGFloat(model.columns - 1) * SwitcherLayout.spacing
    }

    /// An item with its position. Views get the item itself, never an index to look up later: SwiftUI may
    /// still evaluate a row of the old list after `items` changed, and a stale index would crash.
    private struct Entry: Identifiable {
        let index: Int
        let item: SwitcherModel.Item
        var id: String { item.id }
    }

    private var grid: some View {
        let columns = max(1, model.columns)
        let entries = model.items.enumerated().map { Entry(index: $0.offset, item: $0.element) }
        let rows = stride(from: 0, to: entries.count, by: columns).map {
            Array(entries[$0..<min($0 + columns, entries.count)])
        }
        return VStack(alignment: .leading, spacing: SwitcherLayout.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: SwitcherLayout.spacing) {
                    ForEach(row) { entry in
                        tile(entry)
                    }
                }
            }
        }
    }

    private func tile(_ entry: Entry) -> some View {
        let item = entry.item
        let index = entry.index
        let isSelected = index == model.selectedIndex
        return VStack(spacing: 6) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "macwindow").resizable().foregroundStyle(.secondary)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: SwitcherLayout.iconSize, height: SwitcherLayout.iconSize)
            .opacity(item.isMinimized ? 0.55 : 1)
            .overlay(alignment: .bottomTrailing) {
                if item.isMinimized {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .orange)
                        .font(.title3)
                        .help("Minimized")
                }
            }
            Text(verbatim: item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(8)
        .frame(width: SwitcherLayout.tileWidth, height: SwitcherLayout.tileHeight, alignment: .top)
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
}
