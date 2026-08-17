# DolphiniOS Controller Architecture (Beta)

Reconnaissance notes and design, written before any code in this branch. Read this first.

## Part 1 — What already exists in the fork

### The real Wii Remote input path

Input does **not** go through a Wii Remote object on the iOS side. It goes through a flat
integer-keyed state table that Dolphin's `ciface::iOS` input backend polls:

```
TCButton / TCJoystick / TCDirectionalPad / TCDeviceMotion   (Swift, UI + CoreMotion)
        |
        v
TCManagerInterface  (ObjC++ shim: Source/iOS/App/DolphiniOS/UI/Emulation/TouchController/)
        |  +setButtonStateFor:controller:state:
        |  +setAxisValueFor:controller:value:
        v
ciface::iOS::StateManager  (Source/Core/InputCommon/ControllerInterface/iOS/StateManager.{h,cpp})
        |  std::vector<ControllerState>, each a map<ButtonType,bool> + map<ButtonType,float>
        v
ciface::iOS::Touchscreen  (registers "Touchscreen" devices 0..N with Dolphin's ControllerInterface)
        |
        v
WiimoteEmu::Wiimote  (control groups: Buttons, DPad, IR, IMUAccelerometer, IMUGyroscope, IMUPoint)
```

Key facts:

- `ButtonType` (`Source/Core/InputCommon/ControllerInterface/iOS/ButtonType.h`) is the whole
  contract. Relevant ranges:
  - `WIIMOTE_BUTTON_A=100 .. WIIMOTE_RIGHT=110` — face/dpad buttons
  - `WIIMOTE_IR=111`, `WIIMOTE_IR_UP=112`, `_DOWN=113`, `_LEFT=114`, `_RIGHT=115`,
    `_FORWARD=116`, `_BACKWARD=117`, `_HIDE=118` — the **absolute IR pointer**, in
    normalised `-1..1` game-space units
  - `WIIMOTE_ACCEL_* = 625..630`, `WIIMOTE_GYRO_* = 631..636` — the IMU
  - `WIIMOTE_IR_RECENTER = 800` — pulse to make the current device attitude "forward" for
    Dolphin's own IMUPoint (motion-pointing) group
- **The iPad's Wii Remote lives on touchscreen device 4, not 0.** `EmulationiOSViewController`
  `viewDidLoad` assigns `padView.port = 4` for all Wii pads and `0` for the GameCube pad; the
  same 4 is passed to `[TCDeviceMotion setPort:4]`. GC controller is port 0.
- Touch pointing and motion pointing are **mutually exclusive** and this is enforced in one
  place, `-[EmulationiOSViewController updatePointerValuesOnWiiTouchPads]`:
  `Wiimote::GetWiimoteGroup(0, IMUPoint)->enabled.SetValue(irMode == None)`.
  So `TouchPadIRMode == None` means "hand pointing to the IMU", not "no pointing".
- `TCWiiPad.handleLongPress` is what writes IR today. It converts a touch point to
  `-1..1` via `gameCenterX/Y` and `gameWidthHalfInv/HeightHalfInv`, which
  `recalculatePointerValues(new_rect:game_aspect:)` derives from the renderer view bounds and
  `g_presenter->CalculateDrawAspectRatio()` (i.e. it already accounts for pillar/letterboxing).
  Note the axis write order is `[y, y, x, x]` starting at `WIIMOTE_IR + 1` — i.e.
  up, down, left, right — because Dolphin's IR group takes four one-sided axes, not two signed
  ones.

### Motion

`TCDeviceMotion` (`.../TouchController/TCDeviceMotion.swift`) is a singleton wrapping
`CMMotionManager` at 200 Hz (the real Wiimote's report rate). It:

- remaps raw device-frame accel/gyro into Wiimote frame with a `switch` on
  `UIApplication.shared.statusBarOrientation`, refreshed from
  `EmulationiOSViewController.viewDidLayoutSubviews` via `statusBarOrientationChanged()`;
- subtracts a gyro bias captured by `calibrateFlat(_:)`;
- `recenterPointer()` pulses `WIIMOTE_IR_RECENTER`.

It uses **raw** `startAccelerometerUpdates` / `startGyroUpdates`, *not*
`startDeviceMotionUpdates`. There is therefore no fused attitude quaternion anywhere in the
app today. Anything that needs a real world-referenced orientation (which the Apple Logo
pointer does) has to add `CMDeviceMotion`.

### Settings / preferences — there are THREE stores, and they are not interchangeable

1. **Dolphin's own config** — `Config::Get/SetBase/SetBaseOrCurrent`, declared in
   `Source/Core/Core/Config/iOSSettings.{h,cpp}` under `System::Main` section `"iOS"`.
   Persists to `Dolphin.ini`. Existing keys: `TouchPadOpacity`, `TouchPadIRMode`,
   `SelectedStateSlot`, `MuteSwitchMode`. This is the right home for anything the emulator
   core or the in-game menu reads.
   `Config::LayerType::CurrentRun` is a non-persisted layer dropped by
   `BootManager::RestoreConfig()` — the established idiom for "this run only".
2. **`NSUserDefaults`** — used for app-shell state (`DOLDidRepairForcedMotionPointingV1`,
   the welcome screen's seen-flag, `PreGameCalibrationPreferences` on the upstream branch).
3. **`Source/iOS/App/Project/Assets/DefaultPreferences.plist`** — seeds `NSUserDefaults`.

Settings UI: `SettingsRootViewController.swift` is a storyboard-backed `UITableViewController`
(`.../DolphiniOS/UI/Settings/Base.lproj/SettingsRoot.storyboard`). Rows are dispatched by
**cell `tag`**, not index path — `RowTag` enum, tags 1–4 taken. New screens are pushed
programmatically (`CoverArtSettingsViewController`, `AppIconSelectorViewController`,
`OptimizeSettingsViewController`), so a new Beta screen only needs one storyboard cell plus a
tag case.

### External display plumbing — already real, do not rebuild

- `ExternalDisplaySceneDelegate.swift` sets/clears
  `EmulationCoordinator.shared().isExternalDisplayConnected` on scene connect/disconnect.
  This is the authoritative "a TV scene exists" signal — deliberately *not* "some `UIScreen`
  exists", because plain mirroring produces no separate scene.
- `ExternalDisplayEmulationViewController` calls
  `[[EmulationCoordinator shared] registerExternalDisplayView:self.rendererView]` and, since
  9d225fa97b, re-runs `g_presenter->ResizeSurface()` from `viewDidLayoutSubviews` (the AirPlay
  frozen/stretched-first-frame fix).
- `EmulationCoordinator` owns the Metal layer and hands it to whichever view is registered.

So **TV mode is a UI-composition problem, not a rendering problem**: the renderer already
follows the external scene. What TV mode has to add is what the iPad shows *instead* of the
game.

### Multi-controller reality

- `DSUServerManager` already speaks Dolphin's CemuHook DSU protocol so a *second* iOS device
  can act as a remote motion+button controller for a host device.
- `MFiControllerScanner` / `MFiController` register real MFi gamepads with Dolphin directly.
- Because everything lands in `StateManager` keyed by `(controller_id, ButtonType)`, and
  `WiimoteEmu` reads whichever device its mapping points at, the emulator genuinely cannot
  tell sources apart — the abstraction the requirement asks for is largely a *mapping and
  bookkeeping* layer, not a new transport.

### Upstream branch `fix/landscape-wii-pointer-regression`

Read. It is **not** orientation trigonometry — it is about defaults and persistence:

- `PreGameCalibrationPreferences` gains `NSUserDefaults` persistence and, before the user has
  answered once, derives its defaults from `isExternalDisplayConnected` instead of hardcoding
  "yes, TV".
- `switchToMotionPointingIfNeeded` splits into `...Persisting:` — the automatic pre-boot path
  writes only `CurrentRun`, so an accidental boot can't permanently rewrite `TouchPadIRMode`
  in `Dolphin.ini`. Explicit menu actions still persist.
- `repairForcedMotionPointingOnce` one-shot repair for installs already damaged on disk.
- `TCDeviceMotion.calibrateFlat` gains an `NSLock`, an `isGyroAvailable` guard and a 3 s
  watchdog, because the pre-boot modal gates the entire boot on its completion.
- `EmulationBootParameter.targetsWii` so GameCube boots skip the Wii-only calibration gate.

**Lessons taken into this branch:** use `CurrentRun` for anything implied rather than asked
for; never gate a boot on a CoreMotion callback without a watchdog; treat
`isExternalDisplayConnected` as the display truth.

That branch is **not merged into this fork's master**, so nothing here may depend on it.
Where both touch the same file the merge is textual, not semantic.

## Part 2 — Design

### The gate (must land first, must be a no-op when off)

`ControllerBetaGate` — one `Config::Info<bool>` (`Main.iOS.ControllerBetaEnabled`, default
`false`) plus a cached `@objc` accessor. Rules:

- Every new code path is entered only from inside an `if (ControllerBetaGate.isEnabled)`.
- Beta off ⇒ not a single new object is constructed, no new CoreMotion stream starts, no
  existing call site changes behaviour. The stock path is textually unchanged except for the
  guarded branch.
- Read through `Config` so it lands in `Dolphin.ini` alongside the other `iOS` keys and is
  visible to the in-game menu.

### VirtualWiiRemote

One abstraction, five presentations. The object owns *state and geometry*, not views.

```
VirtualWiiRemote
  .slot                 : 1..4   (iPad is always 1)
  .presentation         : normal | onDevicePortrait | onDeviceLandscape | tvPortrait | tvLandscape
  .pointerSource        : standardVirtualRemote | appleLogo | deviceFront | cameraTracking
  .orientationLock      : auto | portrait | landscape
  submit(button:pressed:) / submit(axis:value:)   -> StateManager via TCManagerInterface
  ingest(deviceMotion:)                           -> pointer + IMU axes
```

Presentation selects (a) which overlay view is installed, (b) which physical axis of the
device is "forward", and (c) whether the game renders locally or to the TV. It does **not**
change the wire format — every presentation ends up writing the same `ButtonType` axes on the
same port, which is exactly why the emulator can't tell them apart.

### Apple Logo pointer

`IRPosition = AppleLogoPosition`. Model the device as a rigid body:

- Get a world-referenced attitude from `CMDeviceMotion.attitude` (`.xArbitraryZVertical`
  reference frame — no magnetometer, so no compass calibration prompt, and yaw drift is
  handled by the existing recenter mechanism rather than absolute heading).
- The device's own frame has the logo on the **back**, at the geometric centre of the rear
  face, offset `-z` from the screen plane by the device thickness. The logo's *normal* is
  therefore `-z_device`, and "pointing the back of the iPad at the TV" means aiming that
  normal at the screen plane.
- Ray-cast the logo normal from the logo's world position onto an assumed TV plane at a
  configurable distance, take the intersection in plane coordinates, normalise to `-1..1`,
  emit as `WIIMOTE_IR_UP/DOWN/LEFT/RIGHT` in the same four-one-sided-axis form
  `TCWiiPad` already uses.
- `pointerSource` swaps only the origin and normal:
  - `standardVirtualRemote` — origin at the front tip of a virtual remote laid along the
    device, normal `+y_device` (this is what "IR emitter at the front/end of the virtual
    remote" means for Normal Mode)
  - `appleLogo` — rear-face centre, normal `-z_device`
  - `deviceFront` — top edge centre, normal `+y_device`
  - `cameraTracking` — reserved; falls back to `appleLogo` until a tracker exists

Device geometry (screen size, thickness, logo offset) comes from a documented per-family
approximation rather than a model table — see `DeviceGeometry.detect`. Getting the logo offset
slightly wrong costs a small constant parallax error, not a wrong direction, so an
approximation is acceptable. Part 3 quantifies it: 0.28% of a half-screen-width at TV
distances.

### Smart orientation

`UIDevice.orientationDidChangeNotification` -> if `orientationLock == .auto`, switch
`onDevicePortrait <-> onDeviceLandscape` (or the TV pair). Manual lock pins it. This must
also keep `TCDeviceMotion.statusBarOrientationChanged()` semantics intact for the stock path.

### External display awareness

Observe the same connect/disconnect signal `ExternalDisplaySceneDelegate` already publishes;
when Beta is on and a display appears mid-session, offer "Use TV Mode?" once per connection.

### Multi-remote

`VirtualWiiRemoteRegistry` — slot 1 is the iPad, slots 2–4 are claimed by DSU/MFi/Bluetooth
devices. Every slot is a `VirtualWiiRemote` writing to its own `StateManager` controller id,
so the mapping stays "one Wii Remote interface per slot" from the emulator's side.

## Part 3 — What was built, and what the design got wrong

Written after the fact. Part 2 above is the design as planned; this is where reality diverged.

### Landed

| Commit | What |
| --- | --- |
| `184eb4b` | `DOLControllerBetaGate` + `Main.iOS.ControllerBetaEnabled` + the Settings row |
| `161d909` | `VirtualWiiRemote`, `ApplePointerSolver`, `DeviceGeometry`, the mode enums, `PointerGeometryTests` |
| `4dfc977` | `DOLControllerBetaSettings` and the full Beta settings screen |
| `c1c61d2` | `VirtualWiiRemoteMotion`, `ControllerBetaCoordinator`, the gate biting in `EmulationiOSViewController` |
| `cb4d275` | `VirtualWiiRemoteRegistry` and the Wii Remotes UI |

### Three things the design got wrong, caught by `PointerGeometryTests`

Keeping the geometry free of CoreMotion (one conversion at the boundary in
`VirtualWiiRemote.ingest`) meant it could be compiled and executed as plain Swift on a machine
with no iOS SDK. That paid for itself immediately.

1. **Modelling the on-device presentations against the device's literal screen at arm's
   length.** Wrong twice over. Physically incoherent — if the device *is* the screen, rotating
   it rotates the target, so there is nothing fixed to aim at and the real model is "wrist
   rotation moves the cursor, relative to a neutral hold". And numerically backwards: a 10.9"
   iPad at 40 cm subtends a **14.8°** half-angle, *wider* than a 50" TV at 2.5 m (**12.5°**), so
   it would have made aiming at the screen in your hands harder than aiming across the room.
   Replaced with `SensorBarModel.handheld`, an explicit comfort sweep using Dolphin's own
   defaults for this exact job, halved — `Touchscreen.ini` ships `IR/Total Yaw = 25` and
   `IR/Total Pitch = 20`.

2. **"Rotate by exactly the half-FOV and the pointer lands exactly on the edge" is false for
   the Apple logo.** The logo is 7 mm behind the screen plane, so yawing the device swings it
   ~1.5 mm sideways and that lands directly on the hit point; the edge arrives **0.28% early**.
   Isolated by a zero-thickness geometry that *does* land at exactly 1.0. This is the whole
   reason the emitter is modelled as a position and not just a direction, and it is why the
   coarse `DeviceGeometry` table is defensible: the error is parallax, never direction.

3. **`IR/Hide` had no hysteresis.** Players park the pointer on menu borders and screen corners
   — i.e. right at the boundary — where hand tremor alone crosses it repeatedly, and toggling
   `IR/Hide` at the IMU's 200 Hz would strobe the game's cursor. `PointerSolution` now reports
   the pre-clamp `overshoot` and `VirtualWiiRemote` runs a Schmitt trigger on it.

### Deliberately not built

- **Per-presentation overlay layouts.** The presentations drive geometry, orientation and
  pointer source, and the coordinator tells its delegate when the active one changes — but the
  five presentations still share the stock `TCWiiPad`/`TCSidewaysWiiPad` xibs. Bespoke overlays
  are a pure-UIKit job, and with no Xcode on the build machine there is no way to see, let
  alone verify, a layout. Writing five untested xibs would be volume, not progress.
- **Button-mapping profiles for slots 2–4.** The registry binds a device to a port; which of
  its buttons is Wii Remote A stays with Dolphin's existing Mapping screen, which already
  handles arbitrary devices. Hand-writing an MFi-to-Wiimote INI with no hardware to test on
  would be a guess dressed up as a feature.
- **Camera tracking.** `WiiRemotePointerSource.cameraTracking` exists and resolves to
  `appleLogo`, so selecting it can never leave a player with a dead pointer. No tracker.
- **The sensor-bar calibration visualiser.** Nice-to-have, same UIKit problem as the overlays.

### Verification status

- `PointerGeometryTests` — **27 cases, run, 0 failures.** Real execution, off-device.
- Everything else — **written, not verified.** No Xcode on the build machine (Command Line
  Tools only, so no iOS SDK), so none of the Objective-C++ or UIKit code has been compiled.

### The one assumption that needs hardware

`worldFromDevice` treats `CMAttitude.rotationMatrix` as **device → reference**. This is the
convention in which a device lying flat on its back has the identity matrix and
`CMDeviceMotion.gravity` reads `(0, 0, -1)` in both frames, and it is the convention behind the
usual "aim direction = `rotationMatrix * (0,0,-1)`" recipe. It has **not** been confirmed on a
device.

If it is backwards, the symptom is a pointer that responds to aiming but along mirrored or
swapped axes, and the fix is to transpose in that one function — every vector the solver
compares passes through it.
