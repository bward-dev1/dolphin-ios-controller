// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "ControllerBetaGate.h"

#import "Common/Config/Config.h"

#import "Core/Config/iOSSettings.h"

NSString* const DOLControllerBetaDidChangeNotification = @"DOLControllerBetaDidChangeNotification";

@implementation DOLControllerBetaGate

+ (BOOL)isEnabled {
  return Config::Get(Config::MAIN_CONTROLLER_BETA_ENABLED);
}

+ (void)setEnabled:(BOOL)enabled {
  if ([self isEnabled] == enabled) {
    return;
  }

  // SetBase, not SetBaseOrCurrent: this is a persistent user choice about which build of the
  // controller stack they want, not a per-run override. SetBaseOrCurrent would redirect the
  // write into the CurrentRun layer while a game is running, and CurrentRun is discarded by
  // BootManager::RestoreConfig() -- the toggle would appear to work, then forget itself the
  // moment emulation stopped.
  Config::SetBase(Config::MAIN_CONTROLLER_BETA_ENABLED, enabled);
  Config::Save();

  dispatch_block_t notify = ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:DOLControllerBetaDidChangeNotification
                                                        object:nil];
  };

  if ([NSThread isMainThread]) {
    notify();
  } else {
    dispatch_async(dispatch_get_main_queue(), notify);
  }
}

@end
