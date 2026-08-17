// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation
import UIKit

// What the coordinator needs from whoever is presenting the emulation, so that it can stay free of
// UIKit presentation itself.
@objc public protocol ControllerBetaCoordinatorDelegate: AnyObject {
  /// An external display just appeared and the player hasn't been asked about it. The delegate is
  /// expected to put up "Use TV Mode?" and call -applyPresentation: if they say yes.
  func controllerBetaCoordinatorDidDetectExternalDisplay(_ coordinator: ControllerBetaCoordinator)

  /// The presentation actually in effect changed, for any reason -- an explicit choice, a Smart
  /// Orientation rotation, or a TV being unplugged. The delegate should re-lay-out its overlay.
  func controllerBetaCoordinator(_ coordinator: ControllerBetaCoordinator,
                                 didChangeActivePresentation presentation: WiiRemotePresentation)
}

// Owns the Beta controller for a running game: the remote registry, the motion stream, Smart
// Orientation, and external-display awareness.
//
// Created and started only from behind DOLControllerBetaGate. While Beta is off this object holds
// nothing: no CoreMotion stream is open, no observers are registered, no VirtualWiiRemote exists.
// That's rule 1 of the gate, and `stop()` restores it exactly.
//
// A singleton because there is exactly one set of device sensors, and two coordinators would mean
// two CMMotionManagers writing the same StateManager slots.
@objc public class ControllerBetaCoordinator: NSObject {
  @objc public static let shared = ControllerBetaCoordinator()

  @objc public weak var delegate: ControllerBetaCoordinatorDelegate?

  /// Wii Remote 1: this device. Slots 2-4 are added by the multi-remote registry.
  @objc public private(set) var primaryRemote: VirtualWiiRemote?

  private var motion: VirtualWiiRemoteMotion?
  private var observers: [NSObjectProtocol] = []

  /// The presentation the player chose. Never rewritten by rotating the device or by a TV coming
  /// and going -- only by an explicit choice.
  private var basePresentation: WiiRemotePresentation = .normal

  /// True when a TV presentation is selected but no external display scene exists.
  ///
  /// Tracked rather than assumed. The fork already learned this the hard way once -- see the
  /// "stop assuming a TV is attached" fix -- and the same trap is here: a TV presentation with no
  /// TV leaves the game rendering on a device whose overlay is deliberately a minimal remote, i.e.
  /// the player is looking at a controller with no game on it.
  private var isExternalDisplayMissing = false

  /// Whether the "Use TV Mode?" offer has been made for the currently attached display. Reset on
  /// disconnect, so plugging in again asks again, but not so often that it nags.
  private var didOfferTVModeForCurrentDisplay = false

  @objc public private(set) var isRunning = false

  private override init() {
    super.init()
  }

  // MARK: - Lifecycle

  /// Starts the Beta controller. Returns false if this device can't supply a fused attitude, in
  /// which case the caller must fall back to the stock motion path -- a Beta setting is not worth
  /// leaving someone with a controller that doesn't move.
  @objc public func start() -> Bool {
    guard !isRunning else {
      return true
    }

    basePresentation = presentationFromSettings()
    isExternalDisplayMissing = !EmulationCoordinator.shared().isExternalDisplayConnected

    let remote = VirtualWiiRemote(slot: 1, presentation: effectiveBasePresentation)
    let motion = VirtualWiiRemoteMotion(remote: remote)

    guard motion.start() else {
      return false
    }

    primaryRemote = remote
    self.motion = motion
    isRunning = true

    applySettings()
    registerObservers()

    return true
  }

  @objc public func stop() {
    guard isRunning else {
      return
    }

    motion?.stop()
    motion = nil
    primaryRemote = nil
    isRunning = false
    didOfferTVModeForCurrentDisplay = false

    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  private func registerObservers() {
    let center = NotificationCenter.default

    observers.append(center.addObserver(forName: .dolExternalDisplayDidConnect,
                                       object: nil, queue: .main) { [weak self] _ in
      self?.externalDisplayConnected()
    })

    observers.append(center.addObserver(forName: .dolExternalDisplayDidDisconnect,
                                       object: nil, queue: .main) { [weak self] _ in
      self?.externalDisplayDisconnected()
    })

    observers.append(center.addObserver(
      forName: NSNotification.Name(DOLControllerBetaSettingsDidChangeNotification),
      object: nil, queue: .main) { [weak self] _ in
      self?.applySettings()
    })

    // Orientation is NOT observed here. UIDevice.orientationDidChangeNotification only fires after
    // beginGeneratingDeviceOrientationNotifications(), and it reports *device* orientation, which
    // can differ from the interface's. The emulation view controller calls -applyOrientation from
    // viewDidLayoutSubviews instead -- the same hook the stock path uses to refresh
    // TCDeviceMotion's orientation, so the two can never disagree.
  }

  // MARK: - Settings

  private func presentationFromSettings() -> WiiRemotePresentation {
    return WiiRemotePresentation(rawValue: DOLControllerBetaSettings.presentation) ?? .normal
  }

  /// The player's choice, downgraded to its on-device counterpart when a TV presentation is
  /// selected with no TV attached.
  private var effectiveBasePresentation: WiiRemotePresentation {
    guard basePresentation.requiresExternalDisplay, isExternalDisplayMissing else {
      return basePresentation
    }

    return basePresentation.isLandscape ? .onDeviceLandscape : .onDevicePortrait
  }

  /// Pushes the persisted configuration onto the live remote. Safe to call repeatedly.
  @objc public func applySettings() {
    guard let remote = primaryRemote else {
      return
    }

    basePresentation = presentationFromSettings()

    remote.orientationLock =
      WiiRemoteOrientationLock(rawValue: DOLControllerBetaSettings.orientationLock) ?? .auto

    // applyOrientation does the actual presentation assignment (and the pointer source and screen
    // that follow from it), because the portrait/landscape half of the presentation is derived
    // rather than stored.
    applyOrientation()
  }

  private func applyPointerSource(to remote: VirtualWiiRemote) {
    // The -1 sentinel means "follow the presentation", which is exactly what the presentation
    // setter already does, so Automatic is simply the absence of an override.
    if DOLControllerBetaSettings.isPointerSourceAutomatic {
      remote.pointerSource = remote.presentation.defaultPointerSource
    } else if let source = WiiRemotePointerSource(
      rawValue: DOLControllerBetaSettings.pointerSourceOrAutomatic) {
      remote.pointerSource = source
    }
  }

  private func applyScreen(to remote: VirtualWiiRemote) {
    // Only the TV presentations get a measured screen. The on-device ones use a wrist-rotation
    // comfort sweep, which the presentation setter already installs -- see SensorBarModel.handheld
    // for why a literal device screen is the wrong model there.
    guard remote.presentation.requiresExternalDisplay else {
      return
    }

    let diagonal = Double(DOLControllerBetaSettings.tvDiagonalInches)
    let distance = Double(DOLControllerBetaSettings.tvDistanceMetres)
    let screen = DOLControllerBetaSettings.tvIsWidescreen
      ? SensorBarModel.widescreenTV(diagonalInches: diagonal, distanceMetres: distance)
      : SensorBarModel.standardTV(diagonalInches: diagonal, distanceMetres: distance)

    remote.setSensorBarHalfWidth(screen.halfWidth,
                                halfHeight: screen.halfHeight,
                                distance: screen.distance)
  }

  // MARK: - Smart Orientation

  /// Chooses the live presentation from the player's choice, whether a TV is attached, and how the
  /// device is actually being held. Called from the emulation view controller's layout pass.
  ///
  /// The persisted presentation is never rewritten here. It stays the family the player picked
  /// (Normal / on-device / TV) and only the portrait-versus-landscape half is derived, because
  /// writing it back would mean every wrist turn rewrote Dolphin.ini and would make the Settings
  /// screen's checkmark move while nobody was looking at it.
  @objc public func applyOrientation() {
    guard let remote = primaryRemote else {
      return
    }

    let orientation = ControllerBetaCoordinator.currentInterfaceOrientation()
    remote.interfaceOrientation = orientation

    let base = effectiveBasePresentation

    let wantsLandscape: Bool
    switch remote.orientationLock {
    case .auto:
      wantsLandscape = orientation.isLandscape
    case .portrait:
      wantsLandscape = false
    case .landscape:
      wantsLandscape = true
    }

    // Normal Mode's `rotated` is nil and it is left alone: it manages its own layout the way stock
    // DolphiniOS always has.
    var target = base
    if wantsLandscape != base.isLandscape, let rotated = base.rotated {
      target = rotated
    }

    guard remote.presentation != target else {
      // Still re-apply these: the pointer source or TV size may have changed without the
      // presentation changing.
      applyPointerSource(to: remote)
      applyScreen(to: remote)
      return
    }

    remote.presentation = target
    applyPointerSource(to: remote)
    applyScreen(to: remote)

    // The presentation setter drops the pointer calibration, because the emitter it was captured
    // for may have moved. Recentre immediately rather than letting the player discover a dead
    // pointer and go hunting for the menu item: a Smart Orientation switch is not something they
    // asked for, so it must not cost them anything.
    motion?.requestRecenter()

    delegate?.controllerBetaCoordinator(self, didChangeActivePresentation: target)
  }

  private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
    // Read the same way the stock path reads it (TCDeviceMotion.statusBarOrientationChanged) so
    // the two can't disagree about which way round landscape is.
    let orientation = UIApplication.shared.statusBarOrientation

    return orientation == .unknown ? .portrait : orientation
  }

  // MARK: - Presentation changes from the UI

  /// Applies and persists a presentation the player explicitly chose.
  @objc public func applyPresentation(_ presentation: WiiRemotePresentation) {
    DOLControllerBetaSettings.presentation = presentation.rawValue

    // The settings-change notification would get here on the next main-queue turn anyway, but
    // applying directly keeps an in-game menu selection feeling immediate. applySettings ->
    // applyOrientation is what notifies the delegate, so there's no second call here.
    applySettings()
  }

  /// The presentation actually in effect, which may be the rotated or TV-less counterpart of the
  /// persisted one.
  @objc public var activePresentation: WiiRemotePresentation {
    return primaryRemote?.presentation ?? effectiveBasePresentation
  }

  /// "Point at your TV and tap this."
  @objc public func recenterPointer() {
    motion?.requestRecenter()
  }

  /// Whether the device is currently being held with its long edge horizontal.
  ///
  /// Exposed so the Objective-C++ UI doesn't have to reach for the deprecated
  /// UIApplication.statusBarOrientation itself, and so there is exactly one place in the Beta stack
  /// that decides what "landscape" means.
  @objc public var isHeldLandscape: Bool {
    return ControllerBetaCoordinator.currentInterfaceOrientation().isLandscape
  }

  // MARK: - External display awareness

  private func externalDisplayConnected() {
    isExternalDisplayMissing = false

    // If a TV presentation was already selected, this is the display it was waiting for: bring it
    // back rather than asking about something they already chose.
    if basePresentation.requiresExternalDisplay {
      applyOrientation()
      return
    }

    guard DOLControllerBetaSettings.offersTVMode, !didOfferTVModeForCurrentDisplay else {
      return
    }

    didOfferTVModeForCurrentDisplay = true

    delegate?.controllerBetaCoordinatorDidDetectExternalDisplay(self)
  }

  private func externalDisplayDisconnected() {
    isExternalDisplayMissing = true
    didOfferTVModeForCurrentDisplay = false

    // Deliberately not persisted: the player chose TV mode, and a cable coming loose is not them
    // changing their mind. effectiveBasePresentation downgrades the live presentation while the
    // display is away and restores it when the display comes back.
    applyOrientation()
  }
}
