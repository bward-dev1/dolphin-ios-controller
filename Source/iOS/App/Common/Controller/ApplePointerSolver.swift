// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

// The screen being aimed at, as a plane in front of the emitter.
//
// "Sensor bar" is the Wii's name for it; there is no physical sensor bar here, only an assumed
// rectangle at an assumed distance. Both numbers are the player's to tell us -- they're what
// turns "the device rotated 4 degrees" into "the pointer moved a quarter of the way across the
// screen", and no amount of sensor fusion can supply them.
public struct SensorBarModel {
  /// Half the visible screen width, in metres.
  public var halfWidth: Double
  /// Half the visible screen height, in metres.
  public var halfHeight: Double
  /// Distance from the emitter to the plane of the screen, in metres.
  public var distance: Double

  public init(halfWidth: Double, halfHeight: Double, distance: Double) {
    self.halfWidth = halfWidth
    self.halfHeight = halfHeight
    self.distance = distance
  }

  /// A 16:9 TV of the given diagonal, at the given distance.
  public static func widescreenTV(diagonalInches: Double, distanceMetres: Double) -> SensorBarModel {
    let diagonal = diagonalInches * 0.0254
    // 16:9 -> diagonal = sqrt(16^2 + 9^2) / 16 * width
    let width = diagonal * 16.0 / (16.0 * 16.0 + 9.0 * 9.0).squareRoot()
    return SensorBarModel(halfWidth: width / 2.0,
                          halfHeight: width * 9.0 / 16.0 / 2.0,
                          distance: distanceMetres)
  }

  /// A 4:3 TV of the given diagonal, at the given distance.
  public static func standardTV(diagonalInches: Double, distanceMetres: Double) -> SensorBarModel {
    let diagonal = diagonalInches * 0.0254
    let width = diagonal * 4.0 / (4.0 * 4.0 + 3.0 * 3.0).squareRoot()
    return SensorBarModel(halfWidth: width / 2.0,
                          halfHeight: width * 3.0 / 4.0 / 2.0,
                          distance: distanceMetres)
  }

  /// A screen defined by how far the player has to *rotate* to sweep it, rather than by its
  /// physical size and distance. `distance` is arbitrary here and cancels out; only the ratio to
  /// the half-extents matters.
  public static func angularSweep(halfYawDegrees: Double, halfPitchDegrees: Double) -> SensorBarModel {
    let distance = 1.0
    return SensorBarModel(halfWidth: distance * tan(halfYawDegrees * .pi / 180.0),
                          halfHeight: distance * tan(halfPitchDegrees * .pi / 180.0),
                          distance: distance)
  }

  /// The on-device presentations, where the "screen" is the device the player is holding.
  ///
  /// Deliberately NOT the device's literal display at arm's length, which was the first thing
  /// tried and is wrong twice over. Physically it's incoherent -- if the device is the screen,
  /// rotating it rotates the target too, so there is nothing fixed to aim at and the whole model
  /// is really "wrist rotation moves the cursor", calibrated against a neutral hold. And
  /// numerically it comes out backwards: a 10.9" iPad at 40 cm subtends a half-angle of about
  /// 14.8 degrees, *wider* than a 50" TV at 2.5 m (12.5 degrees), so modelling it literally makes
  /// aiming at the screen in your hands harder than aiming across the room.
  ///
  /// So the on-device modes get an explicit comfort sweep instead. The angles are Dolphin's own
  /// defaults for this exact job, halved: Data/Sys/Profiles/Wiimote/Touchscreen.ini ships
  /// `IR/Total Yaw = 25` and `IR/Total Pitch = 20`, which is the emulator's own answer to "how
  /// much wrist rotation should cover the screen".
  public static func handheld(landscape: Bool) -> SensorBarModel {
    // Landscape gives the wider axis more sweep, so a given rotation covers a comparable
    // *fraction* of the screen either way round.
    return landscape
      ? SensorBarModel.angularSweep(halfYawDegrees: 12.5, halfPitchDegrees: 10.0)
      : SensorBarModel.angularSweep(halfYawDegrees: 10.0, halfPitchDegrees: 12.5)
  }
}

/// Where the emulated Wii Remote's IR pointer has landed.
public struct PointerSolution {
  /// Wii cursor space, clamped to [-1, 1]: -1 is the left edge of the screen, +1 the right.
  public let x: Double
  /// Wii cursor space, clamped to [-1, 1]: -1 is the *bottom* edge, +1 the top. Up-positive,
  /// matching Dolphin's Cursor group -- not UIKit's y-down convention.
  public let y: Double

  /// How far outside the screen rectangle the ray landed, before clamping: 0 at the centre, 1 at
  /// an edge, 2 a full screen-width past it, `.infinity` when there is no intersection at all.
  ///
  /// Exposed rather than just a bool because hiding the cursor needs hysteresis, and a bool
  /// can't provide it. A player holds the pointer on menu borders and screen corners, i.e. right
  /// at the boundary, where hand tremor alone will cross it repeatedly; toggling IR/Hide at the
  /// IMU's 200 Hz would make the game's cursor strobe. VirtualWiiRemote uses this magnitude to
  /// put a gap between the hide and show levels.
  public let overshoot: Double

  /// Whether the ray landed on the screen rectangle at all. Inclusive at the boundary, with a
  /// small tolerance, because a pointer sitting exactly on an edge is on the screen and rounding
  /// should not be what decides.
  public var isOnScreen: Bool {
    return overshoot <= 1.0 + 1e-9
  }

  public init(x: Double, y: Double, overshoot: Double) {
    self.x = x
    self.y = y
    self.overshoot = overshoot
  }

  /// No intersection with the screen plane at all -- aiming parallel to it, or away from it.
  public static let missed = PointerSolution(x: 0, y: 0, overshoot: .infinity)
}

// Turns device attitude into an absolute IR pointer position, for a chosen emitter on the
// device -- the Apple logo, the tip of a virtual remote, or the top edge.
//
// This is deliberately *not* Dolphin's own IMUPoint (WiimoteEmu's IMUCursor). IMUPoint fuses
// the IMU axes we hand it and produces a pointer, but it has no way to know that the emitter is
// a logo on the back panel rather than a tip at the front, so it cannot express "point the back
// of the iPad at the TV" at all. Solving here and writing the absolute IR axes puts the
// geometry where the geometry is known.
//
// Because this occupies the same absolute-Cursor slot that touch pointing does, IMUPoint has to
// be disabled while it's running -- the same mutual exclusion
// -[EmulationiOSViewController updatePointerValuesOnWiiTouchPads] already enforces between
// touch and motion pointing.
//
// # How it works
//
// There is no compass and no absolute knowledge of where the TV is, so the solver works
// relative to a neutral attitude captured by `recenter()` -- exactly what "point at your TV and
// tap Calibrate" already means elsewhere in the app.
//
//   1. At recenter, the emitter's world-space pointing frame (forward/right/up) and world-space
//      position are stored. That frame *defines* where the screen is: dead centre, `distance`
//      metres along neutral-forward.
//   2. Each sample, the emitter's current world-space forward is decomposed onto the neutral
//      frame's axes, giving how far off-axis it now aims.
//   3. The ray is intersected with the screen plane and the hit point normalised by half the
//      screen size.
//
// Rolling the device does not move the pointer, which is correct -- position is position, and
// the roll axis is never consulted. It falls out of the maths rather than needing to be
// special-cased: only the *direction* of neutral-forward is projected, never the emitter's own
// current roll.
public final class ApplePointerSolver {
  /// The screen being aimed at. Changing this mid-session is fine and takes effect immediately.
  public var screen: SensorBarModel

  private struct Neutral {
    let frame: PointingFrame
    let origin: Vector3
  }

  private var neutral: Neutral?

  /// Below this, the emitter is aiming within a few degrees of parallel to the screen plane (or
  /// away from it entirely) and the intersection either doesn't exist or is wildly far off.
  /// Reported as off-screen rather than as a huge coordinate.
  private static let minimumForwardComponent = 0.05

  public init(screen: SensorBarModel) {
    self.screen = screen
  }

  public var isCalibrated: Bool {
    return neutral != nil
  }

  /// Makes the device's current attitude the pointer's neutral centre.
  public func recenter(attitude: RotationMatrix3,
                       source: WiiRemotePointerSource,
                       geometry: DeviceGeometry) {
    let deviceFrame = source.frame(in: geometry)

    neutral = Neutral(
      frame: PointingFrame(forward: worldFromDevice(deviceFrame.forward, attitude),
                           up: worldFromDevice(deviceFrame.up, attitude)),
      origin: worldFromDevice(source.origin(in: geometry), attitude)
    )
  }

  public func clearCalibration() {
    neutral = nil
  }

  /// nil until `recenter` has been called at least once -- there is no meaningful pointer
  /// position before the player has told us which way the screen is.
  public func solve(attitude: RotationMatrix3,
                    source: WiiRemotePointerSource,
                    geometry: DeviceGeometry) -> PointerSolution? {
    guard let neutral = neutral else {
      return nil
    }

    let deviceFrame = source.frame(in: geometry)
    let forward = worldFromDevice(deviceFrame.forward, attitude)

    // How far the emitter now aims off the neutral axis, in the neutral frame's own terms.
    let right = Vector3.dot(forward, neutral.frame.right)
    let up = Vector3.dot(forward, neutral.frame.up)
    let along = Vector3.dot(forward, neutral.frame.forward)

    guard along > ApplePointerSolver.minimumForwardComponent else {
      return PointerSolution.missed
    }

    // Rotation-induced movement of the emitter itself. Only the part caused by rotating the
    // device is knowable -- if the player walks across the room, no IMU can tell us. This term is
    // what makes the choice of emitter (logo on the back vs tip at the front) mean anything
    // beyond a label.
    //
    // Measured size, for calibration of expectations: with the Apple logo 7 mm behind the screen
    // plane, yawing a full half-FOV at a 50" TV 2.5 m away puts the pointer 0.28% of a
    // half-width past where the pure-angle answer would -- rotating the iPad about its own
    // vertical axis swings the logo about 1.5 mm sideways, and that 1.5 mm lands directly on the
    // hit point. Small, but it is the whole reason the emitter is modelled as a position and not
    // just a direction. PointerGeometryTests pins both the magnitude and the zero-thickness case
    // that isolates it.
    let originShift = worldFromDevice(source.origin(in: geometry), attitude) - neutral.origin

    // Ray from (neutral origin + shift) along `forward`, meeting the plane at `distance` along
    // neutral-forward.
    let travel = (screen.distance - Vector3.dot(originShift, neutral.frame.forward)) / along

    guard travel > 0 else {
      // The screen plane is behind the emitter.
      return PointerSolution.missed
    }

    let hitRight = Vector3.dot(originShift, neutral.frame.right) + travel * right
    let hitUp = Vector3.dot(originShift, neutral.frame.up) + travel * up

    guard screen.halfWidth > 1e-6, screen.halfHeight > 1e-6 else {
      return PointerSolution.missed
    }

    let x = hitRight / screen.halfWidth
    let y = hitUp / screen.halfHeight

    // Clamped on the way out, with the pre-clamp magnitude reported separately. Dolphin's Cursor
    // group gates to a unit square anyway, but leaving large magnitudes in place would make its
    // relative-input mode -- which integrates the value -- slam to an edge the instant the player
    // looked away.
    return PointerSolution(x: min(max(x, -1.0), 1.0),
                           y: min(max(y, -1.0), 1.0),
                           overshoot: max(abs(x), abs(y)))
  }
}
