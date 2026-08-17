// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation
import UIKit

// One Wii Remote, however it happens to be presented.
//
// This is the whole point of the Beta architecture: the five presentations, the four pointer
// sources, and slots 2-4 arriving over DSU or Bluetooth all funnel through this one object,
// and it writes the same ButtonType axes on the same touchscreen port that the stock touch
// controller writes. WiimoteEmu reads that port through ciface::iOS::Touchscreen and has no way
// to ask where the numbers came from -- so it cannot tell an iPad held like a remote from a real
// controller, which is exactly the guarantee the design needs.
//
// It owns *state and geometry*, not views. Nothing here touches UIKit layout; presentations
// install their own overlays and tell this object which way the device is being held.
//
// Beta only. Nothing constructs one of these unless DOLControllerBetaGate.isEnabled() -- see the
// rules in ControllerBetaGate.h.
@objc public class VirtualWiiRemote: NSObject {
  /// Wii Remote number as the game sees it, 1-4. The iPad is always 1.
  @objc public let slot: Int

  /// The ciface::iOS::Touchscreen device id this writes to. Not the same as `slot`: the stock
  /// app puts the Wii Remote on touchscreen device 4 and the GameCube pad on 0, so slot 1 maps
  /// to port 4.
  @objc public let port: Int

  /// The touchscreen device id the stock app assigns to the emulated Wii Remote.
  @objc public static let wiimotePort = 4

  // Everything mutable lives behind one lock and one struct. `ingest` runs on the CoreMotion
  // delivery queue while the presentation layer sets these from the main thread, so reading
  // them field by field would let a single motion sample be solved against a half-applied
  // configuration -- e.g. a new presentation with the old pointer source.
  private struct Configuration {
    var presentation: WiiRemotePresentation
    var pointerSource: WiiRemotePointerSource
    var orientationLock: WiiRemoteOrientationLock
    var interfaceOrientation: UIInterfaceOrientation
    var pointerEnabled: Bool
  }

  private let lock = NSLock()
  private var config: Configuration
  private let solver: ApplePointerSolver
  private let geometry: DeviceGeometry

  /// Whether the last solved pointer was off-screen, so `IR/Hide` is only written when it
  /// changes rather than on every one of 200 samples a second.
  ///
  /// Its own lock rather than the configuration lock: `ingest` deliberately releases that lock
  /// before submitting, and reusing it here would make submitPointer unsafe to call from any
  /// future path that already holds it (NSLock is not recursive).
  private let hideStateLock = NSLock()
  private var lastHidden = false

  /// Whether a pointer position has been written since the last time it was parked. Touched only
  /// from the CoreMotion delivery queue, which is serial, so it needs no lock.
  private var wrotePointer = false

  /// ciface::iOS::InputBackend::PopulateDevices registers eight Touchscreen devices: 0-3 are
  /// GameCube pads, 4-7 are Wii Remotes. So slots 1-4 are ports 4-7.
  @objc public init(slot: Int, presentation: WiiRemotePresentation) {
    self.slot = slot
    self.port = VirtualWiiRemote.wiimotePort + max(0, min(3, slot - 1))

    // Touched here, on the main thread, rather than lazily from the motion queue: detect() reads
    // UIScreen, which is main-thread-only.
    self.geometry = DeviceGeometry.shared

    self.config = Configuration(
      presentation: presentation,
      pointerSource: presentation.defaultPointerSource,
      orientationLock: .auto,
      interfaceOrientation: .portrait,
      pointerEnabled: true
    )

    self.solver = ApplePointerSolver(
      screen: VirtualWiiRemote.defaultScreen(for: presentation, geometry: DeviceGeometry.shared)
    )

    super.init()
  }

  // MARK: - Configuration

  /// Switching presentation re-derives the pointer source and the assumed screen, and drops the
  /// pointer calibration.
  ///
  /// Dropping the calibration is deliberate: a neutral attitude captured while pointing the top
  /// edge at a TV means nothing once the emitter has moved to the back panel, and silently
  /// keeping it would leave the pointer pinned to a corner with no obvious cause. Better to
  /// require a recenter, which every presentation prompts for anyway.
  @objc public var presentation: WiiRemotePresentation {
    get {
      lock.lock()
      defer { lock.unlock() }
      return config.presentation
    }
    set {
      lock.lock()
      defer { lock.unlock() }

      guard config.presentation != newValue else {
        return
      }

      config.presentation = newValue
      config.pointerSource = newValue.defaultPointerSource
      solver.screen = VirtualWiiRemote.defaultScreen(for: newValue, geometry: geometry)
      solver.clearCalibration()
    }
  }

  @objc public var pointerSource: WiiRemotePointerSource {
    get {
      lock.lock()
      defer { lock.unlock() }
      return config.pointerSource
    }
    set {
      lock.lock()
      defer { lock.unlock() }

      guard config.pointerSource != newValue else {
        return
      }

      config.pointerSource = newValue
      // Same reasoning as presentation: the neutral attitude is tied to one emitter position and
      // direction, so it cannot survive the emitter changing.
      solver.clearCalibration()
    }
  }

  @objc public var orientationLock: WiiRemoteOrientationLock {
    get {
      lock.lock()
      defer { lock.unlock() }
      return config.orientationLock
    }
    set {
      lock.lock()
      config.orientationLock = newValue
      lock.unlock()
    }
  }

  /// Told to us by the presentation layer rather than read from UIApplication here, so the
  /// motion queue never has to touch UIKit and a locked orientation can differ from the actual
  /// interface orientation.
  @objc public var interfaceOrientation: UIInterfaceOrientation {
    get {
      lock.lock()
      defer { lock.unlock() }
      return config.interfaceOrientation
    }
    set {
      lock.lock()
      config.interfaceOrientation = newValue
      lock.unlock()
    }
  }

  /// Turns pointer writes off without tearing anything down -- for when the player has chosen
  /// touch pointing, or Dolphin's own IMUPoint, instead.
  @objc public var isPointerEnabled: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return config.pointerEnabled
    }
    set {
      lock.lock()
      config.pointerEnabled = newValue
      lock.unlock()
    }
  }

  @objc public func setSensorBarHalfWidth(_ halfWidth: Double, halfHeight: Double, distance: Double) {
    lock.lock()
    solver.screen = SensorBarModel(halfWidth: halfWidth, halfHeight: halfHeight, distance: distance)
    lock.unlock()
  }

  /// Starting guess for a presentation: a 50" widescreen TV at 2.5 m when the game is on a TV,
  /// and a wrist-rotation comfort sweep when the device is the screen. Replaced the moment the
  /// player tells us anything more specific.
  ///
  /// `geometry` is unused for now -- see SensorBarModel.handheld for why the on-device modes
  /// deliberately don't key off the device's physical screen size -- but it's kept in the
  /// signature because the TV branch will want it once the sensor-bar calibration screen can
  /// measure a real one.
  private static func defaultScreen(for presentation: WiiRemotePresentation,
                                    geometry: DeviceGeometry) -> SensorBarModel {
    return presentation.requiresExternalDisplay
      ? SensorBarModel.widescreenTV(diagonalInches: 50, distanceMetres: 2.5)
      : SensorBarModel.handheld(landscape: presentation.isLandscape)
  }

  @objc public var isPointerCalibrated: Bool {
    lock.lock()
    defer { lock.unlock() }
    return solver.isCalibrated
  }

  // MARK: - Pointer calibration

  /// Makes the device's current attitude the pointer's neutral centre: "point at your TV, then
  /// tap this".
  @objc public func recenterPointer(withMotion motion: CMDeviceMotion) {
    lock.lock()
    solver.recenter(attitude: VirtualWiiRemote.rotation(from: motion),
                    source: config.pointerSource,
                    geometry: geometry)
    lock.unlock()
  }

  /// The single conversion between CoreMotion and the platform-independent geometry types.
  /// CMRotationMatrix and RotationMatrix3 are field-for-field identical; keeping them separate is
  /// what lets the pointer maths be exercised as plain Swift, off-device.
  private static func rotation(from motion: CMDeviceMotion) -> RotationMatrix3 {
    let m = motion.attitude.rotationMatrix

    return RotationMatrix3(
      m11: m.m11, m12: m.m12, m13: m.m13,
      m21: m.m21, m22: m.m22, m23: m.m23,
      m31: m.m31, m32: m.m32, m33: m.m33
    )
  }

  // MARK: - Input submission

  /// Buttons, sticks and triggers, as raw ciface::iOS::ButtonType values.
  ///
  /// Raw Ints rather than TCButtonType so this stays callable from Objective-C++ -- TCButtonType
  /// is a Swift-side enum and would not survive the @objc boundary.
  @objc public func submitButton(_ button: Int, pressed: Bool) {
    TCManagerInterface.setButtonStateFor(button, controller: port, state: pressed)
  }

  @objc public func submitAxis(_ axis: Int, value: Float) {
    TCManagerInterface.setAxisValueFor(axis, controller: port, value: value)
  }

  /// Writes an absolute IR pointer position in *Wii cursor space*: x right-positive, y
  /// up-positive, both -1 at one edge of the screen and +1 at the other.
  ///
  /// The sign juggling below is not arbitrary, and it is the single easiest thing in this file
  /// to get backwards, so: ciface::iOS::Touchscreen registers IR Up and IR Left with a -1
  /// multiplier and IR Down and IR Right with +1, and Dolphin clamps every negative input to
  /// zero (ExpressionParser's `std::max(0.0, ...)`). ControllerEmu::Cursor then computes
  /// `y = Up - Down` and `x = Right - Left`. So writing one value v to *both* halves of a pair
  /// yields cursor y = -v and cursor x = +v. Hence the vertical write is negated and the
  /// horizontal one is not. This is the same trick TCWiiPad already uses when it writes
  /// `[y, y, x, x]` starting at wiiInfrared + 1 -- there, y arrives in UIKit's y-down space, so
  /// no negation is needed and none appears.
  ///
  /// `overshoot` is PointerSolution.overshoot: 0 at the centre, 1 at an edge, more beyond.
  @objc public func submitPointer(x: Double, y: Double, overshoot: Double) {
    let horizontal = Float(x)
    let vertical = Float(-y)

    submitAxis(TCButtonType.wiiInfraredUp.rawValue, value: vertical)
    submitAxis(TCButtonType.wiiInfraredDown.rawValue, value: vertical)
    submitAxis(TCButtonType.wiiInfraredLeft.rawValue, value: horizontal)
    submitAxis(TCButtonType.wiiInfraredRight.rawValue, value: horizontal)

    // A real remote loses sight of the sensor bar when you aim away from the TV and games expect
    // the cursor to vanish, so mirror that with IR/Hide.
    let hidden = updateHiddenState(overshoot: overshoot)

    if let hidden = hidden {
      submitButton(TCButtonType.wiiInfraredHide.rawValue, pressed: hidden)
    }
  }

  /// Hide once the pointer is clearly outside the screen, but don't show it again until it is
  /// fully back inside: a Schmitt trigger, not a threshold.
  ///
  /// Without the gap between the two levels this strobes. A single `abs(x) <= 1` boundary is
  /// exactly where players park the pointer -- on menu borders, at screen corners -- and there it
  /// flips on floating-point noise, at the IMU's 200 Hz, toggling the game's cursor visibility
  /// with it. The equality case is the same trap: a pointer resting precisely on an edge is on
  /// the screen, so both comparisons here are inclusive.
  ///
  /// Returns nil when nothing changed, so the common case writes nothing at all.
  private static let hideAboveOvershoot = 1.08
  private static let showAtOrBelowOvershoot = 1.0

  private func updateHiddenState(overshoot: Double) -> Bool? {
    hideStateLock.lock()
    defer { hideStateLock.unlock() }

    let hidden = lastHidden
      ? overshoot > VirtualWiiRemote.showAtOrBelowOvershoot
      : overshoot > VirtualWiiRemote.hideAboveOvershoot

    guard hidden != lastHidden else {
      return nil
    }

    lastHidden = hidden
    return hidden
  }

  // MARK: - Motion

  /// Feeds one fused CoreMotion sample: IMU axes for tilt/swing/shake, plus the solved pointer.
  ///
  /// Called from the CoreMotion delivery queue. Everything it reads is snapshotted under the
  /// lock first, and everything it writes goes through StateManager, which has its own locking.
  @objc public func ingest(_ motion: CMDeviceMotion) {
    lock.lock()
    let snapshot = config
    let solution = snapshot.pointerEnabled
      ? solver.solve(attitude: VirtualWiiRemote.rotation(from: motion),
                     source: snapshot.pointerSource,
                     geometry: geometry)
      : nil
    lock.unlock()

    submitIMU(motion, orientation: motionOrientation(for: snapshot))

    if let solution = solution {
      wrotePointer = true

      submitPointer(x: solution.x, y: solution.y, overshoot: solution.overshoot)
    } else if wrotePointer {
      // Nothing to solve any more -- the pointer was switched off, or the calibration was dropped
      // by a presentation change. Just stopping would leave the IR axes pegged wherever they last
      // landed, and the game's cursor stuck there: StateManager holds the last value written, so
      // "write nothing" reads as "keep pointing there forever". Park it at the centre and hide it
      // once instead.
      //
      // Done here, on the motion queue, rather than from the setter that turned the pointer off.
      // ciface::iOS::StateManager has no internal locking at all (see StateManager.cpp -- plain
      // std::map writes), so every Beta pointer write is kept on this one queue rather than adding
      // a second writing thread.
      wrotePointer = false

      submitPointer(x: 0, y: 0, overshoot: .infinity)
    }
  }

  /// Which interface orientation the IMU remap should use.
  ///
  /// This is where "Smart Orientation" and "Lock Wii Remote Orientation" actually bite. In the
  /// stock app the equivalent value comes straight from UIApplication.statusBarOrientation, which
  /// is why rotating the device rotates the emulated remote's axes whether the player wanted
  /// that or not. Here the presentation gets the final say, and a manual lock overrides even it.
  private func motionOrientation(for snapshot: Configuration) -> UIInterfaceOrientation {
    switch snapshot.orientationLock {
    case .portrait:
      return .portrait
    case .landscape:
      return snapshot.interfaceOrientation.isLandscape ? snapshot.interfaceOrientation : .landscapeRight
    case .auto:
      break
    }

    switch snapshot.presentation {
    case .normal:
      // Normal Mode follows the interface, matching stock behaviour.
      return snapshot.interfaceOrientation
    case .onDevicePortrait, .tvPortrait:
      return .portrait
    case .onDeviceLandscape, .tvLandscape:
      // Keep whichever way round the player actually turned it -- landscapeLeft and
      // landscapeRight are mirror images, and picking the wrong one inverts tilt controls.
      return snapshot.interfaceOrientation.isLandscape ? snapshot.interfaceOrientation : .landscapeRight
    }
  }

  /// Device-frame accelerometer and gyroscope, remapped into the emulated Wii Remote's frame.
  ///
  /// The remap table is a deliberate copy of TCDeviceMotion's, not a shared helper. Factoring it
  /// out would mean editing TCDeviceMotion, which is the Normal-mode hot path, and rule 1 of the
  /// Beta gate is that Normal mode runs the code that shipped. A twelve-line lookup table
  /// duplicated with a pointer back to the original is the cheaper mistake. If the original
  /// changes, this needs the same change.
  ///
  /// The inputs differ from TCDeviceMotion's in one way worth knowing: CMDeviceMotion's
  /// rotationRate is already bias-corrected by CoreMotion, so the manual gyro-bias calibration
  /// the stock path needs ("lay it flat and hold still") is redundant here.
  private func submitIMU(_ motion: CMDeviceMotion, orientation: UIInterfaceOrientation) {
    // gravity + userAcceleration is total acceleration in g, which is what the raw
    // accelerometer stream TCDeviceMotion reads reports directly.
    let accel = Vector3(x: motion.gravity.x + motion.userAcceleration.x,
                        y: motion.gravity.y + motion.userAcceleration.y,
                        z: motion.gravity.z + motion.userAcceleration.z)
    let gyro = Vector3(x: motion.rotationRate.x,
                       y: motion.rotationRate.y,
                       z: motion.rotationRate.z)

    guard let a = VirtualWiiRemote.remap(accel, orientation: orientation),
          let g = VirtualWiiRemote.remap(gyro, orientation: orientation) else {
      return
    }

    // -9.81: the stock path's conversion from g to the signed m/s^2 the Touchscreen axes expect.
    let gravityScale = -9.81
    let ax = Float(a.x * gravityScale)
    let ay = Float(a.y * gravityScale)
    let az = Float(a.z * gravityScale)

    submitAxis(TCButtonType.wiiAccelLeft.rawValue, value: ax)
    submitAxis(TCButtonType.wiiAccelRight.rawValue, value: ax)
    submitAxis(TCButtonType.wiiAccelForward.rawValue, value: ay)
    submitAxis(TCButtonType.wiiAccelBackward.rawValue, value: ay)
    submitAxis(TCButtonType.wiiAccelUp.rawValue, value: az)
    submitAxis(TCButtonType.wiiAccelDown.rawValue, value: az)

    submitAxis(TCButtonType.nunchukAccelLeft.rawValue, value: ax)
    submitAxis(TCButtonType.nunchukAccelRight.rawValue, value: ax)
    submitAxis(TCButtonType.nunchukAccelForward.rawValue, value: ay)
    submitAxis(TCButtonType.nunchukAccelBackward.rawValue, value: ay)
    submitAxis(TCButtonType.nunchukAccelUp.rawValue, value: az)
    submitAxis(TCButtonType.nunchukAccelDown.rawValue, value: az)

    let gx = Float(g.x)
    let gy = Float(g.y)
    let gz = Float(g.z)

    submitAxis(TCButtonType.wiiGyroPitchUp.rawValue, value: gx)
    submitAxis(TCButtonType.wiiGyroPitchDown.rawValue, value: gx)
    submitAxis(TCButtonType.wiiGyroRollLeft.rawValue, value: gy)
    submitAxis(TCButtonType.wiiGyroRollRight.rawValue, value: gy)
    submitAxis(TCButtonType.wiiGyroYawLeft.rawValue, value: gz)
    submitAxis(TCButtonType.wiiGyroYawRight.rawValue, value: gz)
  }

  /// Mirrors TCDeviceMotion's orientation switch exactly. nil for orientations it doesn't
  /// handle, matching the stock path's `@unknown default: return`.
  private static func remap(_ v: Vector3, orientation: UIInterfaceOrientation) -> Vector3? {
    switch orientation {
    case .portrait, .unknown:
      return Vector3(x: -v.x, y: -v.y, z: v.z)
    case .landscapeRight:
      return Vector3(x: v.y, y: -v.x, z: v.z)
    case .portraitUpsideDown:
      return Vector3(x: v.x, y: v.y, z: v.z)
    case .landscapeLeft:
      return Vector3(x: -v.y, y: v.x, z: v.z)
    @unknown default:
      return nil
    }
  }
}
