// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

// The five ways one VirtualWiiRemote can present itself. The emulator sees no difference
// between any of them -- every presentation ends up writing the same ButtonType axes on the
// same touchscreen port. What a presentation chooses is:
//
//   * which overlay the player touches,
//   * which physical axis of the device counts as "forward" (via defaultPointerSource),
//   * whether the game renders on this device or on the TV.
@objc public enum WiiRemotePresentation: Int, CaseIterable {
  // Spelled out rather than left to Swift's CaseIterable synthesis: @objc enums and synthesised
  // allCases have a fraught history, and an explicit list costs nothing and always compiles.
  public static let allCases: [WiiRemotePresentation] = [
    .normal, .onDevicePortrait, .onDeviceLandscape, .tvPortrait, .tvLandscape,
  ]

  /// Conventional Wii Remote. IMU motion, on-screen Wii Remote buttons, and a virtual IR
  /// emitter at the front/end of a virtual remote laid along the device.
  case normal = 0

  /// The whole device *is* the remote, held vertically. The Apple logo on the back is the IR
  /// emitter origin.
  case onDevicePortrait = 1

  /// The same, rotated: controls move to a landscape layout, the logo stays the reference point.
  case onDeviceLandscape = 2

  /// Game renders to an external display; the device becomes a vertical remote. Pointing the
  /// back of the device at the TV points the remote at the TV.
  case tvPortrait = 3

  /// The same, sideways. Minimal overlay on the device, game entirely on the TV.
  case tvLandscape = 4

  public var displayName: String {
    switch self {
    case .normal: return "Normal Mode"
    case .onDevicePortrait: return "On-Device Portrait"
    case .onDeviceLandscape: return "On-Device Landscape"
    case .tvPortrait: return "TV Portrait"
    case .tvLandscape: return "TV Landscape"
    }
  }

  public var summary: String {
    switch self {
    case .normal:
      return "Wii Remote buttons on screen, motion aiming from the front of a virtual remote."
    case .onDevicePortrait:
      return "Hold the device upright. It is the remote; the Apple logo is the pointer."
    case .onDeviceLandscape:
      return "Hold the device sideways. Controls rotate; the Apple logo stays the pointer."
    case .tvPortrait:
      return "Game on the TV. Hold the device upright and point its back at the screen."
    case .tvLandscape:
      return "Game on the TV. Hold the device sideways as a wide remote."
    }
  }

  /// Whether this presentation expects the game to be rendering on an external display.
  public var requiresExternalDisplay: Bool {
    switch self {
    case .tvPortrait, .tvLandscape:
      return true
    case .normal, .onDevicePortrait, .onDeviceLandscape:
      return false
    }
  }

  /// Whether this presentation is held with the long edge horizontal.
  public var isLandscape: Bool {
    switch self {
    case .onDeviceLandscape, .tvLandscape:
      return true
    case .normal, .onDevicePortrait, .tvPortrait:
      return false
    }
  }

  /// Where the IR ray comes from unless the player has picked a source explicitly.
  ///
  /// Normal Mode keeps the virtual-remote tip because that presentation is a stand-in for a
  /// real Wii Remote and the tip is where a real one's emitter is. The four whole-device
  /// presentations default to the Apple logo, because in those the device is not standing in
  /// for anything -- it *is* the remote, and the logo is the landmark the player can actually
  /// see and aim.
  public var defaultPointerSource: WiiRemotePointerSource {
    switch self {
    case .normal:
      return .standardVirtualRemote
    case .onDevicePortrait, .onDeviceLandscape, .tvPortrait, .tvLandscape:
      return .appleLogo
    }
  }

  /// The landscape counterpart of a portrait presentation, and vice versa. Normal Mode has no
  /// counterpart -- it manages its own layout the way stock DolphiniOS always has.
  public var rotated: WiiRemotePresentation? {
    switch self {
    case .normal:
      return nil
    case .onDevicePortrait:
      return .onDeviceLandscape
    case .onDeviceLandscape:
      return .onDevicePortrait
    case .tvPortrait:
      return .tvLandscape
    case .tvLandscape:
      return .tvPortrait
    }
  }
}

// Which point on the device emits the virtual IR ray, and which way it faces. Selectable
// because there is no single right answer: it depends on how the player is holding the thing
// and what they think they're aiming.
@objc public enum WiiRemotePointerSource: Int, CaseIterable {
  public static let allCases: [WiiRemotePointerSource] = [
    .standardVirtualRemote, .appleLogo, .deviceFront, .cameraTracking,
  ]

  /// The front tip of a virtual Wii Remote laid along the device's long axis, aiming out of the
  /// top edge. What a real remote does.
  case standardVirtualRemote = 0

  /// The Apple logo on the back panel, aiming straight out of the back. Point the back of the
  /// device at the TV and the remote points at the TV.
  case appleLogo = 1

  /// The centre of the top edge on the screen plane, aiming out of the top edge. Same direction
  /// as standardVirtualRemote, without the virtual remote's forward offset.
  case deviceFront = 2

  /// Reserved for optical tracking of the real sensor bar / TV. Until a tracker exists this
  /// behaves as appleLogo rather than doing nothing, so selecting it can never leave a player
  /// with a dead pointer.
  case cameraTracking = 3

  public var displayName: String {
    switch self {
    case .standardVirtualRemote: return "Standard Virtual Remote"
    case .appleLogo: return "Apple Logo"
    case .deviceFront: return "Device Front"
    case .cameraTracking: return "Camera Tracking"
    }
  }

  public var summary: String {
    switch self {
    case .standardVirtualRemote:
      return "Aims out of the top edge, from the tip of a virtual remote."
    case .appleLogo:
      return "Aims straight out of the back, from the Apple logo."
    case .deviceFront:
      return "Aims out of the top edge, from the edge itself."
    case .cameraTracking:
      return "Not implemented yet \u{2014} currently behaves like Apple Logo."
    }
  }

  /// Resolves the reserved cases to something that actually produces a ray.
  public var effective: WiiRemotePointerSource {
    return self == .cameraTracking ? .appleLogo : self
  }

  /// Where the ray starts, in the device frame.
  public func origin(in geometry: DeviceGeometry) -> Vector3 {
    switch effective {
    case .standardVirtualRemote:
      return geometry.virtualRemoteTipPosition
    case .appleLogo:
      return geometry.appleLogoPosition
    case .deviceFront:
      return geometry.deviceFrontPosition
    case .cameraTracking:
      return geometry.appleLogoPosition
    }
  }

  /// Which way the ray aims, in the device frame, plus which way is "up" around that aim.
  ///
  /// For appleLogo, forward is -z (out of the back) and up is +y (the device's top edge),
  /// because a player pointing the back at a TV is holding the device with the screen facing
  /// themselves and the top edge up.
  ///
  /// For the two edge-aiming sources, forward is +y (out of the top edge) and up is +z (out of
  /// the screen), because a player pointing the top edge at a TV is holding the device roughly
  /// flat, the way you hold a Wii Remote.
  public func frame(in geometry: DeviceGeometry) -> PointingFrame {
    switch effective {
    case .appleLogo, .cameraTracking:
      return PointingFrame(forward: Vector3(x: 0, y: 0, z: -1), up: Vector3(x: 0, y: 1, z: 0))
    case .standardVirtualRemote, .deviceFront:
      return PointingFrame(forward: Vector3(x: 0, y: 1, z: 0), up: Vector3(x: 0, y: 0, z: 1))
    }
  }
}

// Smart orientation: follow the device unless the player has pinned it.
@objc public enum WiiRemoteOrientationLock: Int, CaseIterable {
  public static let allCases: [WiiRemoteOrientationLock] = [.auto, .portrait, .landscape]

  case auto = 0
  case portrait = 1
  case landscape = 2

  public var displayName: String {
    switch self {
    case .auto: return "Automatic"
    case .portrait: return "Portrait"
    case .landscape: return "Landscape"
    }
  }
}
