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

}  // namespace Config
