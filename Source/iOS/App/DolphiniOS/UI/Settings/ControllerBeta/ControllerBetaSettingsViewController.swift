// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// The fork's two top-level options, in one place.
//
// Presented as two mutually exclusive rows rather than a single UISwitch labelled "Beta"
// because "Normal" is a real, named, supported choice here -- not merely the absence of a
// feature. A lone switch would read as "turn on the extra stuff", which undersells the
// guarantee on the Normal side: with this off, the controller code that runs is the code that
// shipped, not a configured-down version of the new code.
class ControllerBetaSettingsViewController: UITableViewController {
  private enum Section: Int, CaseIterable {
    case mode
  }

  private enum Mode: Int, CaseIterable {
    case normal
    case beta

    var title: String {
      switch self {
      case .normal: return "Normal"
      case .beta: return "Beta"
      }
    }

    var detail: String {
      switch self {
      case .normal:
        return "Stock DolphiniOS controls. Nothing below is active."
      case .beta:
        return "The new Wii Remote work: on-device and TV presentations, Apple Logo pointing, and multiple remotes."
      }
    }
  }

  init() {
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    title = "Controller"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
  }

  private var currentMode: Mode {
    return DOLControllerBetaGate.isEnabled() ? .beta : .normal
  }

  // MARK: - UITableViewDataSource

  override func numberOfSections(in tableView: UITableView) -> Int {
    return Section.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Section(rawValue: section) {
    case .mode:
      return Mode.allCases.count
    case nil:
      return 0
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .mode:
      return "Controller Mode"
    case nil:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .mode:
      return "Beta is experimental and changes how the Wii Remote is emulated. Switching back to "
        + "Normal always restores the original behaviour exactly \u{2014} nothing is migrated or "
        + "rewritten, so it is always safe to try."
    case nil:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

    // Reused cells keep whatever the last row left behind.
    cell.accessoryType = .none

    switch Section(rawValue: indexPath.section) {
    case .mode:
      guard let mode = Mode(rawValue: indexPath.row) else {
        break
      }

      var config = UIListContentConfiguration.subtitleCell()
      config.text = mode.title
      config.secondaryText = mode.detail
      cell.contentConfiguration = config
      cell.accessoryType = mode == currentMode ? .checkmark : .none

      // A checkmark is invisible to VoiceOver, which otherwise reads both rows identically and
      // gives no way to tell which one is in effect.
      cell.accessibilityTraits = mode == currentMode ? [.button, .selected] : [.button]
    case nil:
      break
    }

    return cell
  }

  // MARK: - UITableViewDelegate

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    switch Section(rawValue: indexPath.section) {
    case .mode:
      guard let mode = Mode(rawValue: indexPath.row), mode != currentMode else {
        return
      }

      DOLControllerBetaGate.setEnabled(mode == .beta)
      tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    case nil:
      break
    }
  }
}
