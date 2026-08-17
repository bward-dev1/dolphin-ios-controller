// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include "Core/Config/iOSSettings.h"

namespace Config
{
// Main.iOS

const Info<float> MAIN_TOUCH_PAD_OPACITY{{System::Main, "iOS", "TouchPadOpacity"}, 0.50f};
const Info<int> MAIN_TOUCH_PAD_IR_MODE{{System::Main, "iOS", "TouchPadIRMode"}, 2};
const Info<int> MAIN_SELECTED_STATE_SLOT{{System::Main, "iOS", "SelectedStateSlot"}, 1};
const Info<int> MAIN_MUTE_SWITCH_MODE{{System::Main, "iOS", "MuteSwitchMode"}, 0};

// Defaults to false, and that default matters: an existing install that has never heard of
// this key has to come up in Normal mode, running exactly the code it ran before.
const Info<bool> MAIN_CONTROLLER_BETA_ENABLED{{System::Main, "iOS", "ControllerBetaEnabled"},
                                              false};

const Info<int> MAIN_CONTROLLER_BETA_PRESENTATION{
    {System::Main, "iOS", "ControllerBetaPresentation"}, 0};
const Info<int> MAIN_CONTROLLER_BETA_POINTER_SOURCE{
    {System::Main, "iOS", "ControllerBetaPointerSource"}, -1};
const Info<int> MAIN_CONTROLLER_BETA_ORIENTATION_LOCK{
    {System::Main, "iOS", "ControllerBetaOrientationLock"}, 0};

// A 50" widescreen at 2.5 m: roughly the middle of what people actually have, and the numbers
// only set pointer sensitivity, so being a size out is a comfort issue rather than a breakage.
const Info<float> MAIN_CONTROLLER_BETA_TV_DIAGONAL_INCHES{
    {System::Main, "iOS", "ControllerBetaTVDiagonalInches"}, 50.0f};
const Info<float> MAIN_CONTROLLER_BETA_TV_DISTANCE_METRES{
    {System::Main, "iOS", "ControllerBetaTVDistanceMetres"}, 2.5f};
const Info<bool> MAIN_CONTROLLER_BETA_TV_WIDESCREEN{
    {System::Main, "iOS", "ControllerBetaTVWidescreen"}, true};

const Info<bool> MAIN_CONTROLLER_BETA_OFFER_TV_MODE{
    {System::Main, "iOS", "ControllerBetaOfferTVMode"}, true};

}  // namespace Config
