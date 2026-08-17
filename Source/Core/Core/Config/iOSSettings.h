// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "Common/Config/Config.h"

namespace Config
{
// Main.iOS

extern const Info<float> MAIN_TOUCH_PAD_OPACITY;
extern const Info<int> MAIN_TOUCH_PAD_IR_MODE;
extern const Info<int> MAIN_SELECTED_STATE_SLOT;
extern const Info<int> MAIN_MUTE_SWITCH_MODE;

// The one switch that separates "Normal" from "Beta". Off means the stock DolphiniOS
// controller behaviour, byte for byte -- see DOLControllerBetaGate for the rules every
// caller of this has to follow.
extern const Info<bool> MAIN_CONTROLLER_BETA_ENABLED;

// Everything below is read only while MAIN_CONTROLLER_BETA_ENABLED is true. They are kept in
// Dolphin config rather than NSUserDefaults so the whole controller configuration lives in one
// file the user can inspect, alongside TouchPadIRMode which it interacts with.

// WiiRemotePresentation raw value. 0 (normal) matches the stock layout.
extern const Info<int> MAIN_CONTROLLER_BETA_PRESENTATION;

// WiiRemotePointerSource raw value, or -1 for "whatever the presentation implies". The sentinel
// is the default so that changing presentation moves the emitter with it, which is what a player
// who never opened this setting would expect.
extern const Info<int> MAIN_CONTROLLER_BETA_POINTER_SOURCE;

// WiiRemoteOrientationLock raw value. 0 (auto) is Smart Orientation.
extern const Info<int> MAIN_CONTROLLER_BETA_ORIENTATION_LOCK;

// The assumed screen for the TV presentations. Diagonal and viewing distance are what convert a
// wrist rotation into a fraction of the screen, and nothing can measure them for us.
extern const Info<float> MAIN_CONTROLLER_BETA_TV_DIAGONAL_INCHES;
extern const Info<float> MAIN_CONTROLLER_BETA_TV_DISTANCE_METRES;
extern const Info<bool> MAIN_CONTROLLER_BETA_TV_WIDESCREEN;

// Whether to offer "Use TV Mode?" when an external display appears mid-session.
extern const Info<bool> MAIN_CONTROLLER_BETA_OFFER_TV_MODE;

}  // namespace Config
