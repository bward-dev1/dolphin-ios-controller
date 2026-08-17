// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue when any of these change, so a live emulation session can pick up a
// new presentation or emitter without being restarted.
extern NSString* const DOLControllerBetaSettingsDidChangeNotification;

// The Beta controller's persisted configuration.
//
// Split from DOLControllerBetaGate deliberately: the gate is a promise about which code runs and
// has rules attached, while this is ordinary preference storage that is only ever read from
// inside the gate. Keeping them in one class would invite reading a Beta preference on a path
// that hasn't checked the gate.
//
// Reads and writes Config:: under Main.iOS, so everything lands in Dolphin.ini next to
// TouchPadIRMode -- which matters, because the Beta pointer and TouchPadIRMode are mutually
// exclusive and a user debugging one will go looking for the other.
//
// The raw-integer accessors take and return WiiRemotePresentation / WiiRemotePointerSource /
// WiiRemoteOrientationLock raw values. They are typed as NSInteger rather than the Swift enums
// because those enums live on the Swift side of the bridge, and importing generated Swift headers
// into a header that Swift itself imports is a cycle.
@interface DOLControllerBetaSettings : NSObject

/// WiiRemotePresentation raw value.
@property (class, nonatomic) NSInteger presentation;

/// WiiRemotePointerSource raw value, or -1 for "whatever the presentation implies".
@property (class, nonatomic) NSInteger pointerSourceOrAutomatic;

/// True when pointerSourceOrAutomatic is the -1 sentinel.
@property (class, nonatomic, readonly) BOOL isPointerSourceAutomatic;

/// WiiRemoteOrientationLock raw value.
@property (class, nonatomic) NSInteger orientationLock;

@property (class, nonatomic) float tvDiagonalInches;
@property (class, nonatomic) float tvDistanceMetres;
@property (class, nonatomic) BOOL tvIsWidescreen;

@property (class, nonatomic) BOOL offersTVMode;

/// Clears the explicit pointer source, going back to following the presentation.
+ (void)resetPointerSourceToAutomatic;

@end

NS_ASSUME_NONNULL_END
