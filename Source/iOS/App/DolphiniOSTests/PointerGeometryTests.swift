// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import DolphiniOS
import Foundation
import XCTest

// The Apple Logo pointer's geometry, asserted off-device.
//
// This exists because the sign and handedness conventions in ApplePointerSolver are the easiest
// thing in the Beta controller work to get backwards and the hardest to debug by feel on a
// device: "the cursor moves but wrongly" covers a mirrored axis, a swapped axis, an inverted
// pitch, and a bad emitter frame, and they all look similar in your hands. Keeping the solver
// free of CoreMotion is what lets these run at all.
//
// Two of these assertions started life as *failing* tests whose premises were wrong rather than
// whose code was wrong, and both are kept for that reason -- see testYawAboutOffsetAxisIsIdentical
// and testLiteralDeviceScreenPremiseWasBackwards.
class PointerGeometryTests: XCTestCase {
  /// A generic 10.9" iPad: 0.2117 x 0.2846 m of active area, 7 mm thick.
  private let pad = DeviceGeometry(screenWidth: 0.2117,
                                   screenHeight: 0.2846,
                                   thickness: 0.0070,
                                   appleLogoHeightAboveCentre: 0)

  private let tv = SensorBarModel.widescreenTV(diagonalInches: 50, distanceMetres: 2.5)

  /// The Apple-logo emitter's frame at identity attitude: aiming out of the back (-z), top edge
  /// up (+y). Tests rotate about *this frame's* own axes so they don't depend on which world axis
  /// happens to line up.
  private let logoFrame = PointingFrame(forward: Vector3(x: 0, y: 0, z: -1),
                                        up: Vector3(x: 0, y: 1, z: 0))

  private func calibratedSolver(source: WiiRemotePointerSource = .appleLogo,
                                screen: SensorBarModel? = nil) -> ApplePointerSolver {
    let solver = ApplePointerSolver(screen: screen ?? tv)
    solver.recenter(attitude: .identity, source: source, geometry: pad)
    return solver
  }

  private var horizontalHalfFov: Double {
    return atan(tv.halfWidth / tv.distance)
  }

  private var verticalHalfFov: Double {
    return atan(tv.halfHeight / tv.distance)
  }

  // MARK: - Frame handedness

  func testRightIsForwardCrossUp() {
    // In a world where +Y is the way you're facing and +Z is up, your right hand is +X. If this
    // ever flips, every pointer in the app is mirrored horizontally.
    let frame = PointingFrame(forward: Vector3(x: 0, y: 1, z: 0), up: Vector3(x: 0, y: 0, z: 1))

    XCTAssertEqual(frame.right.x, 1, accuracy: 1e-9)
    XCTAssertEqual(frame.right.y, 0, accuracy: 1e-9)
    XCTAssertEqual(frame.right.z, 0, accuracy: 1e-9)
  }

  func testFrameOrthonormalisesASloppyUp() {
    // `up` is allowed to be merely roughly up.
    let frame = PointingFrame(forward: Vector3(x: 0, y: 1, z: 0), up: Vector3(x: 0, y: 0.4, z: 1))

    XCTAssertEqual(Vector3.dot(frame.forward, frame.up), 0, accuracy: 1e-9)
    XCTAssertEqual(Vector3.dot(frame.forward, frame.right), 0, accuracy: 1e-9)
    XCTAssertEqual(frame.up.length, 1, accuracy: 1e-9)
  }

  func testDegenerateUpStillProducesAUsableFrame() {
    // `up` parallel to `forward` has no valid right vector. Returning zeros would peg the pointer
    // to a corner, so a perpendicular is picked instead.
    let frame = PointingFrame(forward: Vector3(x: 0, y: 0, z: 1), up: Vector3(x: 0, y: 0, z: 1))

    XCTAssertEqual(frame.right.length, 1, accuracy: 1e-9)
    XCTAssertEqual(Vector3.dot(frame.forward, frame.right), 0, accuracy: 1e-9)
  }

  // MARK: - Screen models

  func testWidescreenTVDimensions() {
    // A 50" 16:9 panel is 1.107 m wide and 0.623 m tall.
    XCTAssertEqual(tv.halfWidth, 0.5535, accuracy: 1e-3)
    XCTAssertEqual(tv.halfHeight, 0.3114, accuracy: 1e-3)
  }

  func testAngularSweepIsDistanceInvariant() {
    let sweep = SensorBarModel.angularSweep(halfYawDegrees: 12.5, halfPitchDegrees: 10)

    XCTAssertEqual(atan(sweep.halfWidth / sweep.distance) * 180 / .pi, 12.5, accuracy: 1e-9)
    XCTAssertEqual(atan(sweep.halfHeight / sweep.distance) * 180 / .pi, 10.0, accuracy: 1e-9)
  }

  func testHandheldSweepFollowsTheHeldOrientation() {
    XCTAssertGreaterThan(SensorBarModel.handheld(landscape: false).halfHeight,
                         SensorBarModel.handheld(landscape: false).halfWidth)
    XCTAssertGreaterThan(SensorBarModel.handheld(landscape: true).halfWidth,
                         SensorBarModel.handheld(landscape: true).halfHeight)
  }

  // MARK: - Calibration

  func testNoSolutionBeforeRecenter() {
    let solver = ApplePointerSolver(screen: tv)

    XCTAssertFalse(solver.isCalibrated)
    XCTAssertNil(solver.solve(attitude: .identity, source: .appleLogo, geometry: pad))
  }

  func testNeutralAttitudePointsDeadCentre() {
    let solution = calibratedSolver().solve(attitude: .identity, source: .appleLogo, geometry: pad)

    XCTAssertEqual(solution?.x ?? .nan, 0, accuracy: 1e-9)
    XCTAssertEqual(solution?.y ?? .nan, 0, accuracy: 1e-9)
    XCTAssertEqual(solution?.isOnScreen, true)
  }

  func testClearingCalibrationStopsSolving() {
    let solver = calibratedSolver()
    solver.clearCalibration()

    XCTAssertFalse(solver.isCalibrated)
    XCTAssertNil(solver.solve(attitude: .identity, source: .appleLogo, geometry: pad))
  }

  // MARK: - Aiming

  func testAimingRightMovesThePointerRight() {
    let solver = calibratedSolver()
    // Rotating about the neutral frame's up axis by -halfFov/2 swings the aim toward the frame's
    // +right, which must land the pointer halfway to the right edge.
    let attitude = RotationMatrix3.rotation(radians: -horizontalHalfFov / 2, about: logoFrame.up)
    let solution = solver.solve(attitude: attitude, source: .appleLogo, geometry: pad)

    XCTAssertNotNil(solution)
    XCTAssertGreaterThan(solution!.x, 0.4)
    XCTAssertLessThan(solution!.x, 0.6)
    XCTAssertEqual(solution!.y, 0, accuracy: 1e-6, "yaw must not bleed into pitch")
    XCTAssertTrue(solution!.isOnScreen)
  }

  func testYawIsAntisymmetric() {
    let solver = calibratedSolver()
    let right = solver.solve(attitude: .rotation(radians: -horizontalHalfFov / 2, about: logoFrame.up),
                             source: .appleLogo, geometry: pad)!
    let left = solver.solve(attitude: .rotation(radians: horizontalHalfFov / 2, about: logoFrame.up),
                            source: .appleLogo, geometry: pad)!

    XCTAssertEqual(left.x, -right.x, accuracy: 1e-9)
  }

  func testPitchIsAntisymmetricAndDoesNotBleedIntoYaw() {
    let solver = calibratedSolver()
    let a = solver.solve(attitude: .rotation(radians: -verticalHalfFov / 2, about: logoFrame.right),
                         source: .appleLogo, geometry: pad)!
    let b = solver.solve(attitude: .rotation(radians: verticalHalfFov / 2, about: logoFrame.right),
                         source: .appleLogo, geometry: pad)!

    XCTAssertEqual(a.x, 0, accuracy: 1e-6)
    XCTAssertEqual(b.x, 0, accuracy: 1e-6)
    XCTAssertEqual(a.y, -b.y, accuracy: 1e-9)
    XCTAssertGreaterThan(abs(a.y), 0.4)
    XCTAssertLessThan(abs(a.y), 0.6)
  }

  func testAimingAFullHalfFovLandsOnTheEdgeOnlyWithoutParallax() {
    // Worth reading before trusting the pure-angle intuition anywhere else in this feature.
    //
    // "Rotate by exactly the half-FOV and the pointer lands exactly on the edge" is only true for
    // an emitter that sits at the centre of rotation. The Apple logo does not: it is on the back
    // panel, 7 mm behind the screen plane, so yawing the device swings the logo sideways by about
    // 1.5 mm and that offset lands directly on the hit point. The pointer therefore reaches the
    // edge slightly *before* the pure-angle answer, and at a full half-FOV it is already 0.28% of
    // a half-width past it.
    //
    // This test originally asserted an exact edge hit and failed, which is how the number above
    // was found. It's split in two now: the flat geometry proves the angular maths is exact, and
    // the real geometry pins the parallax contribution.
    let flat = DeviceGeometry(screenWidth: pad.screenWidth,
                              screenHeight: pad.screenHeight,
                              thickness: 0,
                              appleLogoHeightAboveCentre: 0)
    let flatSolver = ApplePointerSolver(screen: tv)
    flatSolver.recenter(attitude: .identity, source: .appleLogo, geometry: flat)
    let flatSolution = flatSolver.solve(attitude: .rotation(radians: -horizontalHalfFov, about: logoFrame.up),
                                        source: .appleLogo, geometry: flat)!

    XCTAssertEqual(flatSolution.overshoot, 1.0, accuracy: 1e-9,
                   "with the emitter at the centre of rotation the angular maths must be exact")
    XCTAssertTrue(flatSolution.isOnScreen, "a pointer resting on the edge is on the screen")

    let realSolution = calibratedSolver().solve(attitude: .rotation(radians: -horizontalHalfFov, about: logoFrame.up),
                                                source: .appleLogo, geometry: pad)!

    XCTAssertEqual(realSolution.overshoot, 1.0028, accuracy: 1e-4,
                   "a 7 mm emitter offset is worth 0.28% of a half-width at 2.5 m")
    XCTAssertGreaterThan(realSolution.overshoot, flatSolution.overshoot,
                         "parallax makes the edge arrive early, not late")
    // Still clamped for the emulator's benefit even though it is just outside.
    XCTAssertEqual(realSolution.x, 1.0, accuracy: 1e-9)
  }

  func testOvershootGrowsPastTheEdge() {
    let solver = calibratedSolver()
    let onEdge = solver.solve(attitude: .rotation(radians: -horizontalHalfFov, about: logoFrame.up),
                              source: .appleLogo, geometry: pad)!
    let beyond = solver.solve(attitude: .rotation(radians: -horizontalHalfFov * 1.5, about: logoFrame.up),
                              source: .appleLogo, geometry: pad)!

    XCTAssertGreaterThan(beyond.overshoot, onEdge.overshoot)
    XCTAssertFalse(beyond.isOnScreen)
    // Overshoot has to survive the clamp -- it is the only thing left that says *how far* off the
    // pointer is, which is what the hide hysteresis needs.
    XCTAssertEqual(beyond.x, 1.0, accuracy: 1e-9)
  }

  func testMissedSolutionsReportInfiniteOvershoot() {
    let solver = calibratedSolver()
    let away = solver.solve(attitude: .rotation(radians: .pi, about: logoFrame.up),
                            source: .appleLogo, geometry: pad)!

    XCTAssertEqual(away.overshoot, .infinity)
    XCTAssertFalse(away.isOnScreen)
  }

  func testRollDoesNotMoveThePointer() {
    // Twisting the device about the axis it is aiming along changes nothing about *where* it
    // aims, and a real Wii Remote's cursor doesn't move when you roll your wrist either. This
    // falls out of the maths rather than being special-cased, so it's worth pinning down.
    let solver = calibratedSolver()
    let solution = solver.solve(attitude: .rotation(radians: 0.6, about: logoFrame.forward),
                                source: .appleLogo, geometry: pad)!

    XCTAssertEqual(solution.x, 0, accuracy: 1e-9)
    XCTAssertEqual(solution.y, 0, accuracy: 1e-9)
  }

  // MARK: - Off screen

  func testAimingAwayIsOffScreen() {
    let solver = calibratedSolver()
    let solution = solver.solve(attitude: .rotation(radians: .pi, about: logoFrame.up),
                                source: .appleLogo, geometry: pad)!

    XCTAssertFalse(solution.isOnScreen)
  }

  func testAimingPastTheEdgeIsOffScreenAndClamped() {
    let solver = calibratedSolver()
    let solution = solver.solve(attitude: .rotation(radians: -horizontalHalfFov * 3, about: logoFrame.up),
                                source: .appleLogo, geometry: pad)!

    XCTAssertFalse(solution.isOnScreen)
    // Unclamped this would be a large number, and Cursor's relative-input mode integrates the
    // value -- it would slam to an edge the instant the player looked away.
    XCTAssertLessThanOrEqual(abs(solution.x), 1.0)
    XCTAssertLessThanOrEqual(abs(solution.y), 1.0)
  }

  func testDegenerateScreenIsOffScreenRatherThanInfinite() {
    let solver = calibratedSolver(screen: SensorBarModel(halfWidth: 0, halfHeight: 0, distance: 2.5))
    let solution = solver.solve(attitude: .identity, source: .appleLogo, geometry: pad)!

    XCTAssertFalse(solution.isOnScreen)
    XCTAssertFalse(solution.x.isNaN)
    XCTAssertFalse(solution.y.isNaN)
  }

  // MARK: - Emitter choice

  func testYawAboutOffsetAxisIsIdentical() {
    // Kept because it was a failing test with a wrong premise. The virtual-remote tip and the
    // device front aim the same way and differ only along device z; yawing about that very axis
    // cannot expose the difference, so "different emitters always give different answers" is
    // false. Asserting the exact equality documents which rotation is blind to the offset.
    let tipSolver = calibratedSolver(source: .standardVirtualRemote)
    let frontSolver = calibratedSolver(source: .deviceFront)
    let tipFrame = PointingFrame(forward: Vector3(x: 0, y: 1, z: 0), up: Vector3(x: 0, y: 0, z: 1))
    let attitude = RotationMatrix3.rotation(radians: 0.05, about: tipFrame.up)

    let tip = tipSolver.solve(attitude: attitude, source: .standardVirtualRemote, geometry: pad)!
    let front = frontSolver.solve(attitude: attitude, source: .deviceFront, geometry: pad)!

    XCTAssertEqual(tip.x, front.x, accuracy: 1e-12)
  }

  func testPitchDoesExposeTheEmitterOffset() {
    let tipSolver = calibratedSolver(source: .standardVirtualRemote)
    let frontSolver = calibratedSolver(source: .deviceFront)
    let tipFrame = PointingFrame(forward: Vector3(x: 0, y: 1, z: 0), up: Vector3(x: 0, y: 0, z: 1))
    let attitude = RotationMatrix3.rotation(radians: 0.05, about: tipFrame.right)

    let tip = tipSolver.solve(attitude: attitude, source: .standardVirtualRemote, geometry: pad)!
    let front = frontSolver.solve(attitude: attitude, source: .deviceFront, geometry: pad)!

    XCTAssertNotEqual(tip.y, front.y, "the parallax term has to actually do something")
    // ...but only just. This is the claim that justifies the coarse device-geometry table.
    XCTAssertLessThan(abs(tip.y - front.y), 0.01)
  }

  func testCameraTrackingFallsBackToTheLogo() {
    XCTAssertEqual(WiiRemotePointerSource.cameraTracking.effective, .appleLogo)
    XCTAssertEqual(WiiRemotePointerSource.cameraTracking.origin(in: pad),
                   WiiRemotePointerSource.appleLogo.origin(in: pad))
  }

  func testAppleLogoIsOnTheBackPanel() {
    let origin = WiiRemotePointerSource.appleLogo.origin(in: pad)

    XCTAssertEqual(origin.x, 0, accuracy: 1e-12)
    XCTAssertEqual(origin.z, -pad.thickness, accuracy: 1e-12, "the logo is on the back, not the screen")
  }

  // MARK: - The premise that was wrong

  func testLiteralDeviceScreenPremiseWasBackwards() {
    // Kept as documentation of a design mistake caught by testing rather than by hardware.
    //
    // The on-device presentations first modelled the pointer against the device's *own* display
    // at arm's length. That is physically incoherent -- if the device is the screen, rotating it
    // rotates the target -- and numerically backwards: an iPad at 40 cm subtends a wider
    // half-angle than a 50" TV at 2.5 m, so it would have made aiming at the screen in your hands
    // harder than aiming across the room. Hence SensorBarModel.handheld's explicit comfort sweep.
    let literal = SensorBarModel(halfWidth: pad.screenWidth / 2,
                                 halfHeight: pad.screenHeight / 2,
                                 distance: 0.40)

    XCTAssertGreaterThan(atan(literal.halfWidth / literal.distance),
                         atan(tv.halfWidth / tv.distance))
  }

  func testHandheldSweepIsMoreSensitiveThanTheTV() {
    let handheldSolver = calibratedSolver(screen: SensorBarModel.handheld(landscape: false))
    let tvSolver = calibratedSolver()
    let attitude = RotationMatrix3.rotation(radians: -0.05, about: logoFrame.up)

    let handheld = handheldSolver.solve(attitude: attitude, source: .appleLogo, geometry: pad)!
    let onTV = tvSolver.solve(attitude: attitude, source: .appleLogo, geometry: pad)!

    XCTAssertGreaterThan(abs(handheld.x), abs(onTV.x))
  }

  // MARK: - Presentation table

  func testPresentationTable() {
    XCTAssertEqual(WiiRemotePresentation.allCases.count, 5)
    XCTAssertEqual(WiiRemotePresentation.allCases.filter { $0.requiresExternalDisplay },
                   [.tvPortrait, .tvLandscape])
    XCTAssertEqual(WiiRemotePresentation.allCases.filter { $0.isLandscape },
                   [.onDeviceLandscape, .tvLandscape])
    XCTAssertEqual(WiiRemotePresentation.normal.defaultPointerSource, .standardVirtualRemote)
    XCTAssertEqual(WiiRemotePresentation.allCases.filter { $0.defaultPointerSource == .appleLogo }.count, 4)
  }

  func testRotatingTwiceIsIdentityExceptForNormalMode() {
    XCTAssertNil(WiiRemotePresentation.normal.rotated)

    for presentation in WiiRemotePresentation.allCases where presentation != .normal {
      XCTAssertEqual(presentation.rotated?.rotated, presentation)
      XCTAssertNotEqual(presentation.rotated?.isLandscape, presentation.isLandscape)
    }
  }
}
