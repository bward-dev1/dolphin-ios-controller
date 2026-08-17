// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

// Posted when an external-display *scene* connects or disconnects.
//
// Deliberately not UIScreen.didConnectNotification, which also fires for plain mirroring. In
// mirroring there is no separate scene, the game keeps rendering to the device's own screen, and
// offering to move it to the TV would be a lie. This is the same distinction the comment on
// EmulationCoordinator.isExternalDisplayConnected already draws; these notifications just make the
// edge observable instead of only the current state.
//
// Additive: nothing observes them unless the Beta controller is enabled, so posting them changes
// nothing about Normal mode.
extension Notification.Name {
  static let dolExternalDisplayDidConnect = Notification.Name("DOLExternalDisplayDidConnectNotification")
  static let dolExternalDisplayDidDisconnect = Notification.Name("DOLExternalDisplayDidDisconnectNotification")
}

class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    EmulationCoordinator.shared().isExternalDisplayConnected = true

    NotificationCenter.default.post(name: .dolExternalDisplayDidConnect, object: nil)
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    EmulationCoordinator.shared().isExternalDisplayConnected = false

    NotificationCenter.default.post(name: .dolExternalDisplayDidDisconnect, object: nil)
  }
  
  func sceneDidBecomeActive(_ scene: UIScene) {
    //
  }
  
  func sceneWillResignActive(_ scene: UIScene) {
    //
  }
  
  func sceneWillEnterForeground(_ scene: UIScene) {
    //
  }
  
  func sceneDidEnterBackground(_ scene: UIScene) {
    //
  }
}
