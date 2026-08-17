// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

#if canImport(UIKit)
import UIKit
#endif

// Where things physically are on this device, in metres, in the CoreMotion device frame:
//
//   +x  toward the right edge   (portrait, screen facing you)
//   +y  toward the top edge
//   +z  out of the screen, toward you
//
// Origin is the centre of the screen. The back of the device is therefore at z = -thickness.
//
// These numbers only ever enter the pointer solution as a *parallax* term -- an offset of the
// ray's origin, not its direction. At a typical 2.5 m from a 1 m-wide TV, being 8 mm out
// shifts the pointer by under 1% of half the screen width. So approximations here are cheap,
// and the code below prefers a documented approximation over a hand-typed table of model
// numbers that would be wrong for every device released after it was written.
public struct DeviceGeometry {
  /// Physical width of the display's active area with the device held in portrait.
  public let screenWidth: Double
  /// Physical height of the display's active area with the device held in portrait.
  public let screenHeight: Double
  /// Front-to-back thickness of the body.
  public let thickness: Double
  /// Height of the Apple logo's centre above the centre of the back panel, portrait, +up.
  public let appleLogoHeightAboveCentre: Double

  public init(screenWidth: Double,
              screenHeight: Double,
              thickness: Double,
              appleLogoHeightAboveCentre: Double) {
    self.screenWidth = screenWidth
    self.screenHeight = screenHeight
    self.thickness = thickness
    self.appleLogoHeightAboveCentre = appleLogoHeightAboveCentre
  }

  /// The Apple logo's position in the device frame: centre of the back panel.
  public var appleLogoPosition: Vector3 {
    return Vector3(x: 0, y: appleLogoHeightAboveCentre, z: -thickness)
  }

  /// The centre of the top edge, on the back panel -- the "front tip" of a virtual Wii Remote
  /// laid along the device's long axis, which is where a real remote's IR emitter sits.
  public var virtualRemoteTipPosition: Vector3 {
    return Vector3(x: 0, y: screenHeight / 2.0, z: -thickness / 2.0)
  }

  /// The centre of the top edge, on the screen plane.
  public var deviceFrontPosition: Vector3 {
    return Vector3(x: 0, y: screenHeight / 2.0, z: 0)
  }
}

// Detection is the only part of this that needs UIKit. Split out so the geometry above stays
// platform-independent and can be exercised as plain Swift alongside the pointer maths.
#if canImport(UIKit)
extension DeviceGeometry {
  /// Must be first touched on the main thread: detect() reads UIScreen.
  public static let shared = DeviceGeometry.detect()

  // Points-per-inch is the only per-family constant needed, because UIScreen already reports
  // the pixel dimensions. 264 ppi covers every full-size iPad Apple has shipped; recent iPhones
  // have drifted between 458 and 476, so 460 is used as a mid-range stand-in.
  //
  // Not branched any finer than iPad/iPhone on purpose. iPad mini is genuinely 326, but pixel
  // dimensions can't tell a mini from a full-size iPad -- the 7.9" mini and the 9.7" iPad are
  // both 2048x1536 -- so distinguishing them would need a hand-typed table of hw.machine
  // identifiers that is wrong for every device released after this line was written. Calling a
  // mini 264 ppi overstates its screen by about 23%, which costs a few extra millimetres of
  // parallax and a slightly gentler pointer in the on-device presentations. Both are inside
  // what the recenter/calibration step corrects for anyway.
  private static func detect() -> DeviceGeometry {
    let native = UIScreen.main.nativeBounds  // Always in portrait pixel dimensions.
    let shortSidePixels = Double(min(native.width, native.height))
    let longSidePixels = Double(max(native.width, native.height))

    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    let ppi: Double = isPad ? 264 : 460
    let metresPerInch = 0.0254

    // iPad bodies are 5.9-7.5 mm depending on generation; iPhones 7.4-8.3 mm. One value per
    // family is well inside the tolerance a parallax term needs.
    let thickness: Double = isPad ? 0.0070 : 0.0080

    return DeviceGeometry(
      screenWidth: shortSidePixels / ppi * metresPerInch,
      screenHeight: longSidePixels / ppi * metresPerInch,
      thickness: thickness,
      // Centred on the back panel. True for full-size iPads; some iPhones and the mini sit the
      // logo slightly high, which again costs millimetres of parallax and no direction error.
      appleLogoHeightAboveCentre: 0.0
    )
  }
}
#endif
