// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo
//
// Private (undocumented) macOS APIs. They are used by many window managers and switchers
// (AltTab, Rectangle, yabai…), but Apple may change them in any macOS release – keep their
// use small and always have a fallback.

#ifndef CPRIVATE_H
#define CPRIVATE_H

#include <ApplicationServices/ApplicationServices.h>

/// Returns the CGWindowID (the same number as kCGWindowNumber in CGWindowListCopyWindowInfo)
/// of an accessibility window element. Exported by HIServices.
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

/// System keyboard shortcuts ("symbolic hot keys") handled by the WindowServer before any event tap sees
/// them. 1 = ⌘Tab, 2 = ⌘⇧Tab (the app switcher), 6 = ⌘` (next window of the same app).
/// The enabled state is global for the login session and survives the process that changed it –
/// whoever turns a hot key off must turn it back on. Exported by SkyLight via CoreGraphics.
typedef int CGSSymbolicHotKey;
CGError CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey, bool isEnabled);
bool CGSIsSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey);

#endif
