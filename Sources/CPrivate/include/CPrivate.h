// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo
//
// Private (undocumented) macOS APIs. They are used by many window managers and switchers
// (AltTab, Rectangle, yabai…), but Apple may change them in any macOS release – keep their
// use small and always have a fallback.
//
// The WT* functions look the private symbols up at run time (dlsym), so a macOS release without them
// does not stop WinTab from launching: the functions then return NULL / false and WinTab falls back to
// public APIs. Their knowledge comes from AltTab (lwouis/alt-tab-macos, GPL-3.0), which in turn credits
// yabai and Hammerspoon.

#ifndef CPRIVATE_H
#define CPRIVATE_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

CF_ASSUME_NONNULL_BEGIN

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

/// True when every private symbol used below was found.
bool WTPrivateAPIsAvailable(void);

/// The Spaces of every display (CGSCopyManagedDisplaySpaces): an array of dictionaries with
/// "Display Identifier", "Current Space" (dictionary) and "Spaces" (array of dictionaries with
/// "id64" = space ID and "type": 0 = normal desktop, 4 = fullscreen app). NULL when unavailable.
CFArrayRef _Nullable WTCopyManagedDisplaySpaces(void) CF_RETURNS_RETAINED;

/// IDs (CFNumber) of the windows on the given Spaces (array of CFNumber space IDs), front to back per
/// Space (CGSCopyWindowsWithOptionsAndTags). NULL when unavailable.
CFArrayRef _Nullable WTCopyWindowsOnSpaces(CFArrayRef _Nonnull spaceIDs) CF_RETURNS_RETAINED;

/// Brings one window of an app to the front – also on another Space (macOS then switches to it) – and
/// makes it the key window: _SLPSSetFrontProcessWithOptions + two SLPSPostEventRecordTo event records.
/// Returns false when the private calls are unavailable or failed.
bool WTFocusWindow(pid_t pid, CGWindowID windowID);

/// An accessibility element of `pid` built from a "remote token" with the given element ID
/// (_AXUIElementCreateWithRemoteToken). The only way to reach windows on other Spaces, which
/// kAXWindowsAttribute leaves out: try IDs from 0 up and check which window each element belongs to.
/// Returns NULL when unavailable or when no element has this ID.
AXUIElementRef _Nullable WTCreateAXElementWithRemoteToken(pid_t pid, uint64_t elementID) CF_RETURNS_RETAINED;

/// An image of one window, also on another Space (CGSHWCaptureWindowList with "ignore global clip shape" +
/// "best resolution", like AltTab). Full window resolution – scale it down. Needs the Screen Recording
/// permission. NULL when unavailable or failed.
CGImageRef _Nullable WTCopyWindowImage(CGWindowID windowID) CF_RETURNS_RETAINED;

CF_ASSUME_NONNULL_END

#endif
