#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo
//
// Draws the WinTab app icon – three stacked windows on a blue rounded square – and writes
//   Assets/AppIcon.png   (1024 × 1024, for the README)
//   Assets/AppIcon.icns  (all macOS icon sizes, copied into the app by scripts/build-app.sh)
// Run from the repository root:  swift scripts/make-icon.swift

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// One window card: body, title bar with three dots, optional content lines. The cards behind are opaque but
/// tinted with the background color, so they look farther away without showing each other through.
func drawWindow(_ ctx: CGContext, frame: CGRect, body: UInt32, bar: UInt32, dots: UInt32?, content: Bool) {
    let radius: CGFloat = 40
    let titleBar: CGFloat = 70

    // Soft shadow under the card.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x0A1240, 0.35))
    ctx.addPath(roundedRect(frame, radius))
    ctx.setFillColor(color(body))
    ctx.fillPath()
    ctx.restoreGState()

    // Title bar: a slightly darker strip clipped to the card's top corners.
    ctx.saveGState()
    ctx.addPath(roundedRect(frame, radius))
    ctx.clip()
    ctx.setFillColor(color(bar))
    ctx.fill(CGRect(x: frame.minX, y: frame.maxY - titleBar, width: frame.width, height: titleBar))
    ctx.restoreGState()

    let dotColors: [UInt32] = dots.map { [$0, $0, $0] } ?? [0xFF5F57, 0xFEBC2E, 0x28C840]
    for (i, dot) in dotColors.enumerated() {
        let center = CGPoint(x: frame.minX + 46 + CGFloat(i) * 42, y: frame.maxY - titleBar / 2)
        ctx.setFillColor(color(dot))
        ctx.fillEllipse(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
    }

    guard content else { return }
    // A picture block and a few text lines.
    let inset: CGFloat = 46
    let top = frame.maxY - titleBar - 44
    ctx.setFillColor(color(0x8FB3FF))
    ctx.addPath(roundedRect(CGRect(x: frame.minX + inset, y: top - 150, width: 170, height: 150), 22))
    ctx.fillPath()
    let lineX = frame.minX + inset + 170 + 36
    let lineWidths: [CGFloat] = [1, 0.8, 0.9, 0.55]
    for (i, factor) in lineWidths.enumerated() {
        let maxWidth = frame.maxX - inset - lineX
        ctx.setFillColor(color(0xD3DAE8))
        ctx.addPath(roundedRect(CGRect(x: lineX, y: top - 26 - CGFloat(i) * 42, width: maxWidth * factor, height: 24), 12))
        ctx.fillPath()
    }
    for (i, factor) in [CGFloat(1), 0.7].enumerated() {
        let width = (frame.width - 2 * inset) * factor
        ctx.setFillColor(color(0xD3DAE8))
        ctx.addPath(roundedRect(CGRect(x: frame.minX + inset, y: top - 210 - CGFloat(i) * 42, width: width, height: 24), 12))
        ctx.fillPath()
    }
}

func drawIcon(size pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / canvas
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    // The macOS icon grid: an 824 pt rounded square centered on the 1024 pt canvas, with a drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x2B4FE0))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient, lighter at the top.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x4F8BFF), color(0x2A3FD1), color(0x1E2A9E)] as CFArray,
                              locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY),
                           options: [])
    ctx.restoreGState()

    // Three windows, back to front, peeking out to the upper left – the switcher's stack.
    let size = CGSize(width: 560, height: 400)
    drawWindow(ctx, frame: CGRect(origin: CGPoint(x: 172, y: 402), size: size),
               body: 0x9DB6FF, bar: 0x8AA6F7, dots: 0x7893EA, content: false)
    drawWindow(ctx, frame: CGRect(origin: CGPoint(x: 232, y: 312), size: size),
               body: 0xD3DEFF, bar: 0xBCCBF7, dots: 0xA3B5EC, content: false)
    drawWindow(ctx, frame: CGRect(origin: CGPoint(x: 292, y: 222), size: size),
               body: 0xFFFFFF, bar: 0xE8ECF5, dots: nil, content: true)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let fileManager = FileManager.default
let assets = URL(fileURLWithPath: "Assets", isDirectory: true)
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try writePNG(drawIcon(size: 1024), to: assets.appendingPathComponent("AppIcon.png"))

// iconutil wants an .iconset folder with these names.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WinTab-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try writePNG(drawIcon(size: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(drawIcon(size: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", assets.appendingPathComponent("AppIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed")
    exit(1)
}
print("Wrote Assets/AppIcon.png and Assets/AppIcon.icns")
