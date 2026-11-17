// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

/// How the switcher arranges its tiles: as many columns as fit, rows as even as possible, and tiles
/// shrunk (down to `minimumScale`) when there are too many windows for the screen height.
public struct GridLayout: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    /// Factor for the tile size (1 = full size).
    public var scale: Double

    public init(columns: Int, rows: Int, scale: Double) {
        self.columns = columns; self.rows = rows; self.scale = scale
    }

    /// - Parameters:
    ///   - count: number of tiles,
    ///   - tileWidth, tileHeight: full-size tile,
    ///   - spacing: gap between tiles (not scaled),
    ///   - availableWidth, availableHeight: room for the grid itself (without the panel's padding).
    public static func fit(count: Int, tileWidth: Double, tileHeight: Double, spacing: Double,
                           availableWidth: Double, availableHeight: Double,
                           minimumScale: Double = 0.5) -> GridLayout {
        guard count > 0 else { return GridLayout(columns: 1, rows: 0, scale: 1) }
        var scale = 1.0
        while true {
            let width = tileWidth * scale, height = tileHeight * scale
            let fitting = max(1, Int((availableWidth + spacing) / (width + spacing)))
            let rows = (count + fitting - 1) / fitting
            // Same number of rows, but spread evenly: 7 tiles in 5 columns → 4 + 3, not 5 + 2.
            let columns = (count + rows - 1) / rows
            let gridHeight = Double(rows) * height + Double(rows - 1) * spacing
            if gridHeight <= availableHeight || scale <= minimumScale {
                return GridLayout(columns: columns, rows: rows, scale: scale)
            }
            scale = max(minimumScale, scale - 0.05)
        }
    }
}

/// The largest size with the aspect ratio of `width × height` that fits into `maxWidth × maxHeight`
/// (whole pixels, at least 1×1) – the size of a window thumbnail.
public func aspectFit(width: Double, height: Double, maxWidth: Double, maxHeight: Double) -> (width: Int, height: Int) {
    guard width > 0, height > 0, maxWidth > 0, maxHeight > 0 else { return (1, 1) }
    let scale = min(maxWidth / width, maxHeight / height)
    return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
}
