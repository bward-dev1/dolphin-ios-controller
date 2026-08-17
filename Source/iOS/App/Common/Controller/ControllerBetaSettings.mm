// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "ControllerBetaSettings.h"

#include <algorithm>

#import "Common/Config/Config.h"

#import "Core/Config/iOSSettings.h"

NSString* const DOLControllerBetaSettingsDidChangeNotification =
    @"DOLControllerBetaSettingsDidChangeNotification";

namespace
{
void PostChangeNotification()
{
  dispatch_block_t notify = ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:DOLControllerBetaSettingsDidChangeNotification
                      object:nil];
  };

  if ([NSThread isMainThread])
  {
    notify();
  }
  else
  {
    dispatch_async(dispatch_get_main_queue(), notify);
  }
}

// SetBaseOrCurrent rather than SetBase: these are legitimate mid-game adjustments (the in-game
// menu will offer the presentation switch), and while a game is running that has to land on the
// CurrentRun layer so a per-game INI isn't clobbered. Outside a run it targets base and persists.
// Unlike the gate itself, none of these is a promise about which code path exists, so a per-run
// override is harmless.
template <typename T>
void Write(const Config::Info<T>& info, const T& value)
{
  if (Config::Get(info) == value)
  {
    return;
  }

  Config::SetBaseOrCurrent(info, value);

  // A no-op for a CurrentRun write (that layer has no loader and is never persisted), so this
  // only actually writes Dolphin.ini for changes made outside a run. Worth the unconditional
  // call: every one of these is user-initiated from a settings screen or a menu, so it happens
  // at human frequency, and waiting for the resign-active hook would lose the choice if the
  // player force-quit straight after making it.
  Config::Save();

  PostChangeNotification();
}
}  // namespace

@implementation DOLControllerBetaSettings

+ (NSInteger)presentation {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_PRESENTATION);
}

+ (void)setPresentation:(NSInteger)presentation {
  Write(Config::MAIN_CONTROLLER_BETA_PRESENTATION, static_cast<int>(presentation));
}

+ (NSInteger)pointerSourceOrAutomatic {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_POINTER_SOURCE);
}

+ (void)setPointerSourceOrAutomatic:(NSInteger)pointerSourceOrAutomatic {
  Write(Config::MAIN_CONTROLLER_BETA_POINTER_SOURCE,
        static_cast<int>(pointerSourceOrAutomatic));
}

+ (BOOL)isPointerSourceAutomatic {
  return [self pointerSourceOrAutomatic] < 0;
}

+ (void)resetPointerSourceToAutomatic {
  [self setPointerSourceOrAutomatic:-1];
}

+ (NSInteger)orientationLock {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_ORIENTATION_LOCK);
}

+ (void)setOrientationLock:(NSInteger)orientationLock {
  Write(Config::MAIN_CONTROLLER_BETA_ORIENTATION_LOCK, static_cast<int>(orientationLock));
}

+ (float)tvDiagonalInches {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_TV_DIAGONAL_INCHES);
}

+ (void)setTvDiagonalInches:(float)tvDiagonalInches {
  // A zero or negative diagonal would make the assumed screen degenerate, which the solver
  // reports as permanently off-screen -- i.e. a pointer that silently never appears. Clamped
  // rather than rejected so a bad value in a hand-edited Dolphin.ini can't brick pointing.
  Write(Config::MAIN_CONTROLLER_BETA_TV_DIAGONAL_INCHES,
        std::clamp(tvDiagonalInches, 10.0f, 200.0f));
}

+ (float)tvDistanceMetres {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_TV_DISTANCE_METRES);
}

+ (void)setTvDistanceMetres:(float)tvDistanceMetres {
  Write(Config::MAIN_CONTROLLER_BETA_TV_DISTANCE_METRES,
        std::clamp(tvDistanceMetres, 0.3f, 15.0f));
}

+ (BOOL)tvIsWidescreen {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_TV_WIDESCREEN);
}

+ (void)setTvIsWidescreen:(BOOL)tvIsWidescreen {
  Write(Config::MAIN_CONTROLLER_BETA_TV_WIDESCREEN, static_cast<bool>(tvIsWidescreen));
}

+ (BOOL)offersTVMode {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_OFFER_TV_MODE);
}

+ (void)setOffersTVMode:(BOOL)offersTVMode {
  Write(Config::MAIN_CONTROLLER_BETA_OFFER_TV_MODE, static_cast<bool>(offersTVMode));
}

@end
