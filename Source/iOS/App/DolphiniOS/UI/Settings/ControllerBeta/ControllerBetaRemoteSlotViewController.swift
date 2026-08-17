// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// Picks which real device backs one of Wii Remotes 2, 3 or 4.
//
// Only the *binding* happens here. Which button on that device is Wii Remote A stays with Dolphin's
// existing Mapping screen, which already handles arbitrary devices properly -- this deliberately
// does not invent button profiles for pads it has never seen. The footer says so, because a player
// who binds a controller here and finds none of its buttons do anything would otherwise reasonably
// conclude the binding failed.
class ControllerBetaRemoteSlotViewController: UITableViewController {
  private enum Section: Int, CaseIterable {
    // Named `unassigned`, not `none`. Switching over `Section(rawValue:)` gives a `Section?`, and
    // in that context `case .none` silently binds to Optional.none -- i.e. it would match nil and
    // leave the real row unreachable. One of Swift's better traps.
    case unassigned
    case devices
  }

  private let slot: Int
  private var qualifiers: [String] = []

  init(slot: Int) {
    self.slot = slot

    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    title = "Wii Remote \(slot)"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    // Re-read on every appearance, not just once: controllers get switched on and phones join the
    // network while this screen is open, and the list is the whole point of the screen.
    reload()
  }

  private func reload() {
    qualifiers = VirtualWiiRemoteRegistry.shared().assignableDeviceQualifiers()
    tableView.reloadData()
  }

  private var currentQualifier: String? {
    let slots = VirtualWiiRemoteRegistry.shared().slots

    guard slot >= 1, slot <= slots.count else {
      return nil
    }

    return slots[slot - 1].deviceQualifier
  }

  // MARK: - UITableViewDataSource

  override func numberOfSections(in tableView: UITableView) -> Int {
    return Section.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Section(rawValue: section) {
    case .unassigned:
      return 1
    case .devices:
      return qualifiers.count
    case nil:
      return 0
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .devices:
      return "Available Devices"
    case .unassigned, nil:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .unassigned:
      return nil
    case .devices:
      if qualifiers.isEmpty {
        return "Nothing to assign yet. Connect a game controller, or run the Remote Controller "
          + "screen on another device on the same network so it appears here."
      }

      return "Assigning a device here makes the game see it as Wii Remote \(slot). Which of its "
        + "buttons does what is set in Settings \u{2192} Controllers \u{2192} Port \(slot), the "
        + "same as for any other controller."
    case nil:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

    cell.accessoryType = .none
    cell.accessibilityTraits = [.button]

    let title: String
    let selected: Bool

    switch Section(rawValue: indexPath.section) {
    case .unassigned:
      title = "None"
      selected = currentQualifier == nil
    case .devices:
      guard indexPath.row < qualifiers.count else {
        return cell
      }
      title = qualifiers[indexPath.row]
      selected = qualifiers[indexPath.row] == currentQualifier
    case nil:
      return cell
    }

    var config = UIListContentConfiguration.cell()
    config.text = title
    cell.contentConfiguration = config
    cell.accessoryType = selected ? .checkmark : .none
    cell.accessibilityTraits = selected ? [.button, .selected] : [.button]

    return cell
  }

  // MARK: - UITableViewDelegate

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    switch Section(rawValue: indexPath.section) {
    case .unassigned:
      _ = VirtualWiiRemoteRegistry.shared().clearSlot(slot)
    case .devices:
      guard indexPath.row < qualifiers.count else {
        return
      }
      _ = VirtualWiiRemoteRegistry.shared().assignDeviceQualifier(qualifiers[indexPath.row], toSlot: slot)
    case nil:
      return
    }

    tableView.reloadData()
  }
}
