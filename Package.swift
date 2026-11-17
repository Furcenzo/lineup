// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import PackageDescription

let package = Package(
    name: "WinTab",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WinTab", targets: ["WinTab"]),
    ],
    targets: [
        // Pure logic (window list ordering, selection, hotkey state machine) – no UI, tested.
        .target(name: "WinTabCore"),
        // Declarations of private macOS APIs (see Sources/CPrivate/include/CPrivate.h).
        .target(name: "CPrivate", linkerSettings: [.linkedFramework("ApplicationServices")]),
        .executableTarget(
            name: "WinTab",
            dependencies: ["WinTabCore", "CPrivate"],
            // Localizable.strings files are copied into the .app by scripts/build-app.sh
            exclude: ["Resources"]
        ),
        .testTarget(name: "WinTabCoreTests", dependencies: ["WinTabCore"]),
    ]
)
