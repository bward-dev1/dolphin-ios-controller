// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation

// Drives a VirtualWiiRemote from CoreMotion's *fused* device-motion stream.
//
// The stock path (TCDeviceMotion) uses the raw accelerometer and gyroscope streams, which give
// rates and accelerations but no orientation. The Apple Logo pointer needs an actual attitude, so
// this uses startDeviceMotionUpdates instead. Two consequences worth knowing:
//
//   * CoreMotion bias-corrects rotationRate on this stream, so the stock path's manual
//     "lay it flat and hold still" gyro calibration is redundant here.
//   * `.xArbitraryZVertical` is used rather than a magnetometer-referenced frame. There is no
//     compass involved, so iOS never shows a figure-of-eight calibration prompt, and the arbitrary
//     yaw origin costs nothing because the pointer is solved relative to a recenter anyway.
//
// Beta only. Nothing constructs one of these unless DOLControllerBetaGate.isEnabled().
@objc public class VirtualWiiRemoteMotion: NSObject {
  private let motionManager = CMMotionManager()
  private let queue = OperationQueue()
  private weak var remote: VirtualWiiRemote?

  /// Set when the next sample should become the pointer's neutral centre.
  ///
  /// Deferred to a sample rather than done on demand because a recenter needs an attitude, and
  /// asking CMMotionManager for `deviceMotion` right after starting returns nil until the first
  /// sample lands. Doing it this way means "recenter" is always honoured, just possibly 5 ms late.
  private let recenterLock = NSLock()
  private var wantsRecenter = false

  @objc public private(set) var isRunning = false

  @objc public init(remote: VirtualWiiRemote) {
    self.remote = remote

    // Matched to the stock path: 200 Hz is the real Wii Remote's report rate, and there is no
    // benefit to sampling faster than the thing being emulated.
    self.motionManager.deviceMotionUpdateInterval = 1.0 / 200.0

    self.queue.name = "me.oatmealdome.dolphinios.virtual-wii-remote-motion"
    // One sample at a time, in order. The solver keeps a neutral attitude and the remote keeps
    // hide-state, so concurrent delivery would interleave writes for no gain.
    self.queue.maxConcurrentOperationCount = 1

    super.init()
  }

  /// Returns false when this device can't supply a fused attitude at all, so the caller can fall
  /// back to the stock motion path rather than leaving the player with a dead controller.
  @objc public func start() -> Bool {
    guard !isRunning else {
      return true
    }

    guard motionManager.isDeviceMotionAvailable else {
      NSLog("VirtualWiiRemoteMotion: device motion unavailable, cannot drive the Beta controller")
      return false
    }

    // The pointer produces nothing until it has a neutral attitude, so centre it on however the
    // device is being held right now. Without this the player would start a game, see no cursor,
    // and have no way to know a hidden calibration step was missing.
    requestRecenter()

    motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
      guard let self = self, let motion = motion else {
        if let error = error {
          NSLog("VirtualWiiRemoteMotion: %@", error.localizedDescription)
        }
        return
      }

      guard let remote = self.remote else {
        return
      }

      self.recenterLock.lock()
      let shouldRecenter = self.wantsRecenter
      self.wantsRecenter = false
      self.recenterLock.unlock()

      if shouldRecenter {
        remote.recenterPointer(withMotion: motion)
      }

      remote.ingest(motion)
    }

    isRunning = true

    return true
  }

  @objc public func stop() {
    guard isRunning else {
      return
    }

    motionManager.stopDeviceMotionUpdates()
    queue.cancelAllOperations()
    isRunning = false
  }

  /// Makes the next sample's attitude the pointer's neutral centre.
  @objc public func requestRecenter() {
    recenterLock.lock()
    wantsRecenter = true
    recenterLock.unlock()
  }
}
