// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import WinTabCore

/// A global keyboard event tap (CGEventTap). It sees every key press in the session, may swallow it,
/// and needs the Accessibility permission. The callback runs on the main run loop.
@MainActor
final class KeyboardTap {
    /// Returns true to swallow the event.
    private let handler: (KeyEvent) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping (KeyEvent) -> Bool) {
        self.handler = handler
    }

    /// The tap exists (it was created with the Accessibility permission).
    var isInstalled: Bool { tap != nil }

    /// Fails (returns false) when WinTab does not have the Accessibility permission yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    /// Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off when a callback was too slow – turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            return handler(.keyDown(keyCode, Modifiers(flags)))
        case .keyUp:
            return handler(.keyUp(keyCode, Modifiers(flags)))
        case .flagsChanged:
            return handler(.modifiersChanged(Modifiers(flags)))
        default:
            return false
        }
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let tapAddress = UInt(bitPattern: userInfo)
    // The tap's run loop source is added to the main run loop, so this runs on the main thread.
    let swallow = MainActor.assumeIsolated {
        Unmanaged<KeyboardTap>.fromOpaque(UnsafeRawPointer(bitPattern: tapAddress)!).takeUnretainedValue()
            .handle(type: type, keyCode: keyCode, flags: flags)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

extension Modifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskCommand) { insert(.command) }
    }
}
