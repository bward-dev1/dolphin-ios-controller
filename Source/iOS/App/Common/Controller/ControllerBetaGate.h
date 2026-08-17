// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue whenever the gate flips. UI that shows one thing in Normal mode and
// another in Beta mode should observe this rather than re-reading the gate on a timer.
extern NSString* const DOLControllerBetaDidChangeNotification;

// The single switch that separates the fork's two top-level options.
//
//   Normal (default) - stock DolphiniOS. Every code path is the one that shipped.
//   Beta             - the VirtualWiiRemote work, its five presentations, the Apple Logo
//                      pointer, smart orientation, and the multi-remote registry.
//
// Rules for anything that consults this, in priority order:
//
//  1. Beta off must be a no-op, not a cheaper version of Beta. Guarded code may not construct
//     objects, start CoreMotion streams, install gesture recognisers, add observers, or write
//     to StateManager. If Beta is off the only thing that happened is a bool read.
//
//  2. Read it at *branch points*, never per-sample. Beta code is installed or not installed;
//     it is not a conditional inside a 200 Hz motion handler. If you find yourself wanting to
//     check the gate inside a CoreMotion callback, the wiring is wrong -- don't attach the
//     Beta motion source at all in Normal mode.
//
//  3. Never invert it. There is no "if Normal, do something new". Normal mode's behaviour is
//     defined as "the code that was already there", so a Normal-only branch is by definition
//     a behaviour change to Normal mode.
//
// Backed by Config::MAIN_CONTROLLER_BETA_ENABLED, so it lands in Dolphin.ini next to the other
// Main.iOS keys and is legible to the in-game menu, which also reads Dolphin config.
@interface DOLControllerBetaGate : NSObject

// Cheap: one Config lookup. Safe to call from any thread, but see rule 2 -- it is not free
// enough to sit in a per-sample path, and putting it there would defeat rule 1 anyway.
+ (BOOL)isEnabled;

// Persists immediately (Config::Save) rather than relying on the resign-active/terminate
// hooks in DolphinCoreService: someone flipping an experimental controller mode is quite
// likely to force-quit next, and silently losing the choice would read as the toggle not
// working.
+ (void)setEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
