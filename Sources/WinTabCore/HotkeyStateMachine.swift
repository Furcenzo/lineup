// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

/// Modifier keys, independent of AppKit / CoreGraphics so the logic can be tested.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

/// Virtual key codes (kVK_* from Carbon's Events.h) the switcher reacts to.
public enum KeyCode {
    public static let tab: UInt16 = 48
    public static let `return`: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
}

/// A keyboard event seen by the global event tap.
public enum KeyEvent: Sendable, Equatable {
    case keyDown(UInt16, Modifiers)
    case keyUp(UInt16, Modifiers)
    /// A modifier key was pressed or released; carries the modifiers held now.
    case modifiersChanged(Modifiers)
}

public enum SwitcherAction: Sendable, Equatable {
    case open(reverse: Bool)
    case next
    case previous
    /// Switch to the selected window and close the switcher.
    case confirm
    /// Close the switcher without switching.
    case cancel
}

/// What to do with one keyboard event: an optional switcher action, and whether the event must be
/// swallowed (not delivered to the frontmost app).
public struct KeyEventResult: Sendable, Equatable {
    public var action: SwitcherAction?
    public var swallow: Bool

    public init(action: SwitcherAction? = nil, swallow: Bool) {
        self.action = action; self.swallow = swallow
    }

    public static let pass = KeyEventResult(swallow: false)
}

/// The hotkey: hold `modifier`, press `keyCode` (Tab) to open the switcher, press it again to move,
/// release the modifier to switch.
public struct HotkeyConfig: Sendable, Equatable {
    public var modifier: Modifiers
    public var keyCode: UInt16

    public init(modifier: Modifiers, keyCode: UInt16 = KeyCode.tab) {
        self.modifier = modifier; self.keyCode = keyCode
    }

    /// ⌘Tab – replaces the system app switcher (the default).
    public static let commandTab = HotkeyConfig(modifier: .command)
    /// ⌥Tab – leaves the system ⌘Tab alone.
    public static let optionTab = HotkeyConfig(modifier: .option)
}

/// The shortcut the user picked; the raw value is stored in UserDefaults.
public enum ShortcutChoice: String, Sendable, CaseIterable {
    case commandTab = "command"
    case optionTab = "option"

    public static let `default` = ShortcutChoice.commandTab

    public init(storedValue: String?) {
        self = storedValue.flatMap(ShortcutChoice.init(rawValue:)) ?? .default
    }

    public var config: HotkeyConfig {
        switch self {
        case .commandTab: .commandTab
        case .optionTab: .optionTab
        }
    }

    /// Whether WinTab has to turn off the system app switcher for this shortcut.
    public var replacesSystemSwitcher: Bool { self == .commandTab }
}

/// Turns raw key events into switcher actions. Pure logic – the event tap feeds it and performs the
/// returned actions.
public struct HotkeyStateMachine: Sendable {
    public var config: HotkeyConfig
    public private(set) var isActive = false
    /// Shift is held while the switcher is open (the close buttons turn into "force quit").
    public private(set) var isShiftHeld = false
    /// Keys whose keyDown was swallowed; their keyUp is swallowed too, even after the switcher closed,
    /// so the frontmost app never sees half a key press.
    private var swallowedKeys = Set<UInt16>()

    public init(config: HotkeyConfig) {
        self.config = config
    }

    public mutating func handle(_ event: KeyEvent) -> KeyEventResult {
        let result = process(event)
        switch event {
        case let .keyDown(_, modifiers), let .keyUp(_, modifiers), let .modifiersChanged(modifiers):
            isShiftHeld = isActive && modifiers.contains(.shift)
        }
        return result
    }

    private mutating func process(_ event: KeyEvent) -> KeyEventResult {
        switch event {
        case let .keyDown(code, modifiers):
            return isActive ? keyDownWhileActive(code, modifiers) : keyDownWhileInactive(code, modifiers)
        case let .keyUp(code, _):
            if swallowedKeys.remove(code) != nil || isActive { return KeyEventResult(swallow: true) }
            return .pass
        case let .modifiersChanged(modifiers):
            // Never swallow modifier changes – apps must keep a consistent idea of which keys are held.
            if isActive && !modifiers.contains(config.modifier) {
                isActive = false
                return KeyEventResult(action: .confirm, swallow: false)
            }
            return .pass
        }
    }

    /// The switcher was closed from outside (mouse click, lost permission…).
    public mutating func deactivate() {
        isActive = false
        isShiftHeld = false
    }

    private mutating func keyDownWhileInactive(_ code: UInt16, _ modifiers: Modifiers) -> KeyEventResult {
        // Other modifiers besides the trigger and Shift mean a different shortcut (e.g. ⌃⌥Tab) – leave it alone.
        let others = modifiers.subtracting([config.modifier, .shift])
        guard code == config.keyCode, modifiers.contains(config.modifier), others.isEmpty else { return .pass }
        isActive = true
        return swallow(code, .open(reverse: modifiers.contains(.shift)))
    }

    private mutating func keyDownWhileActive(_ code: UInt16, _ modifiers: Modifiers) -> KeyEventResult {
        switch code {
        case config.keyCode:
            return swallow(code, modifiers.contains(.shift) ? .previous : .next)
        case KeyCode.rightArrow, KeyCode.downArrow:
            return swallow(code, .next)
        case KeyCode.leftArrow, KeyCode.upArrow:
            return swallow(code, .previous)
        case KeyCode.escape:
            isActive = false
            return swallow(code, .cancel)
        case KeyCode.return, KeyCode.keypadEnter, KeyCode.space:
            isActive = false
            return swallow(code, .confirm)
        default:
            // Typing while the switcher is open must not reach the app underneath.
            return swallow(code, nil)
        }
    }

    private mutating func swallow(_ code: UInt16, _ action: SwitcherAction?) -> KeyEventResult {
        swallowedKeys.insert(code)
        return KeyEventResult(action: action, swallow: true)
    }
}
