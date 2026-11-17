// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo
//
// Run-time lookup of private SkyLight / HIServices functions (see include/CPrivate.h).
// Signatures, the event record layout and the remote token format follow AltTab
// (lwouis/alt-tab-macos, GPL-3.0: src/macos/api-wrappers/SkyLight.framework.swift,
// WindowFocusEvent.swift, AXUIElement.swift).

#include "CPrivate.h"
#include <dlfcn.h>
#include <string.h>

typedef uint32_t WTConnectionID;

typedef WTConnectionID (*MainConnectionIDFn)(void);
typedef CFArrayRef (*CopyManagedDisplaySpacesFn)(WTConnectionID);
typedef CFArrayRef (*CopyWindowsWithOptionsAndTagsFn)(WTConnectionID, int, CFArrayRef, int, uint64_t *, uint64_t *);
typedef CGError (*SetFrontProcessFn)(ProcessSerialNumber *, CGWindowID, uint32_t);
typedef CGError (*PostEventRecordFn)(ProcessSerialNumber *, uint8_t *);
typedef OSStatus (*GetProcessForPIDFn)(pid_t, ProcessSerialNumber *);
typedef AXUIElementRef (*CreateWithRemoteTokenFn)(CFDataRef);
typedef CFArrayRef (*HWCaptureWindowListFn)(WTConnectionID, CGWindowID *, uint32_t, uint32_t);

static MainConnectionIDFn mainConnectionID;
static CopyManagedDisplaySpacesFn copyManagedDisplaySpaces;
static CopyWindowsWithOptionsAndTagsFn copyWindowsWithOptionsAndTags;
static SetFrontProcessFn setFrontProcess;
static PostEventRecordFn postEventRecord;
static GetProcessForPIDFn getProcessForPID;
static CreateWithRemoteTokenFn createWithRemoteToken;
static HWCaptureWindowListFn hwCaptureWindowList;

static void lookUp(void) {
    static bool done = false;
    if (done) return;
    done = true;
    // SkyLight and HIServices are loaded by AppKit / ApplicationServices already; CoreGraphics re-exports
    // the CGS* names. Open SkyLight explicitly anyway in case that ever changes.
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    mainConnectionID = (MainConnectionIDFn)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    copyManagedDisplaySpaces = (CopyManagedDisplaySpacesFn)dlsym(RTLD_DEFAULT, "CGSCopyManagedDisplaySpaces");
    copyWindowsWithOptionsAndTags = (CopyWindowsWithOptionsAndTagsFn)dlsym(RTLD_DEFAULT, "CGSCopyWindowsWithOptionsAndTags");
    setFrontProcess = (SetFrontProcessFn)dlsym(RTLD_DEFAULT, "_SLPSSetFrontProcessWithOptions");
    postEventRecord = (PostEventRecordFn)dlsym(RTLD_DEFAULT, "SLPSPostEventRecordTo");
    // Deprecated since 10.9 and missing from the SDK headers, but still exported.
    getProcessForPID = (GetProcessForPIDFn)dlsym(RTLD_DEFAULT, "GetProcessForPID");
    createWithRemoteToken = (CreateWithRemoteTokenFn)dlsym(RTLD_DEFAULT, "_AXUIElementCreateWithRemoteToken");
    hwCaptureWindowList = (HWCaptureWindowListFn)dlsym(RTLD_DEFAULT, "CGSHWCaptureWindowList");
}

bool WTPrivateAPIsAvailable(void) {
    lookUp();
    return mainConnectionID && copyManagedDisplaySpaces && copyWindowsWithOptionsAndTags && setFrontProcess
        && postEventRecord && getProcessForPID && createWithRemoteToken;
}

CFArrayRef WTCopyManagedDisplaySpaces(void) {
    lookUp();
    if (!mainConnectionID || !copyManagedDisplaySpaces) return NULL;
    return copyManagedDisplaySpaces(mainConnectionID());
}

CFArrayRef WTCopyWindowsOnSpaces(CFArrayRef spaceIDs) {
    lookUp();
    if (!mainConnectionID || !copyWindowsWithOptionsAndTags) return NULL;
    uint64_t setTags = 0, clearTags = 0;
    // Owner 0 = all apps. Option 2 also returns windows of apps assigned to All Spaces.
    return copyWindowsWithOptionsAndTags(mainConnectionID(), 0, spaceIDs, 2, &setTags, &clearTags);
}

bool WTFocusWindow(pid_t pid, CGWindowID windowID) {
    lookUp();
    if (!setFrontProcess || !postEventRecord || !getProcessForPID) return false;
    ProcessSerialNumber psn = {0, 0};
    if (getProcessForPID(pid, &psn) != noErr) return false;
    // 0x200 = kCPSUserGenerated: a user-initiated switch (not suppressed like a background request).
    if (setFrontProcess(&psn, windowID, 0x200) != kCGErrorSuccess) return false;

    // Make the window key with a synthetic event record (0xf8 bytes; WindowServer may read a little further,
    // so the buffer is 0x100 and zeroed). The points lie outside any window content, so nothing is clicked.
    uint8_t bytes[0x100];
    memset(bytes, 0, sizeof bytes);
    bytes[0x04] = 0xF8;
    bytes[0x3A] = 0x10;
    CGPoint offContent = {300000, 300000};
    memcpy(&bytes[0x10], &offContent, sizeof offContent);
    memcpy(&bytes[0x20], &offContent, sizeof offContent);
    memcpy(&bytes[0x3C], &windowID, sizeof windowID);
    bytes[0x08] = 0x01; // down
    postEventRecord(&psn, bytes);
    bytes[0x08] = 0x02; // up
    postEventRecord(&psn, bytes);
    return true;
}

AXUIElementRef WTCreateAXElementWithRemoteToken(pid_t pid, uint64_t elementID) {
    lookUp();
    if (!createWithRemoteToken) return NULL;
    // 20 bytes: pid (4) + 0 (4) + magic "coco" 0x636f636f (4) + element ID (8).
    uint8_t token[20];
    memset(token, 0, sizeof token);
    int32_t magic = 0x636f636f;
    memcpy(&token[0], &pid, 4);
    memcpy(&token[8], &magic, 4);
    memcpy(&token[12], &elementID, 8);
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, token, sizeof token);
    if (!data) return NULL;
    AXUIElementRef element = createWithRemoteToken(data);
    CFRelease(data);
    return element;
}

CGImageRef WTCopyWindowImage(CGWindowID windowID) {
    lookUp();
    if (!mainConnectionID || !hwCaptureWindowList) return NULL;
    // 1 << 11 = ignore global clip shape, 1 << 8 = best resolution.
    CFArrayRef images = hwCaptureWindowList(mainConnectionID(), &windowID, 1, (1 << 11) | (1 << 8));
    if (!images) return NULL;
    CGImageRef image = NULL;
    if (CFArrayGetCount(images) > 0) {
        image = (CGImageRef)CFArrayGetValueAtIndex(images, 0);
        if (image) CFRetain(image);
    }
    CFRelease(images);
    return image;
}
