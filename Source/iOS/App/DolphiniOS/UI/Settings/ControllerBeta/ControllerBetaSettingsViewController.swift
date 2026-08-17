// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// The fork's two top-level options, and everything the Beta one exposes.
//
// The mode itself is presented as two mutually exclusive rows rather than a single UISwitch
// labelled "Beta" because "Normal" is a real, named, supported choice here -- not merely the
// absence of a feature. A lone switch would read as "turn on the extra stuff", which undersells
// the guarantee on the Normal side: with this off, the controller code that runs is the code that
// shipped, not a configured-down version of the new code.
//
// Everything below the mode section is hidden entirely while Normal is selected, rather than
// shown greyed out. Beta off is a no-op, and a screenful of live-looking controls that provably
// affect nothing is worse than no controls at all.
class ControllerBetaSettingsViewController: UITableViewController {
  private enum Section: Int, CaseIterable {
    case mode
    case presentation
    case pointerSource
    case orientation
    case tv
    case remotes
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

  private enum TVRow: Int, CaseIterable {
    case diagonal
    case distance
    case widescreen
    case offerTVMode
  }

  /// The pointer-source section shows an extra "Automatic" row above the four real sources.
  private static let automaticPointerSourceRow = 0

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

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    // Guarded, not unconditional. In Normal mode the Wii Remotes section isn't shown at all, and
    // touching the registry would construct its singleton and call
    // g_controller_interface.RefreshDevices() for a section nobody can see -- which is exactly the
    // "Beta off constructs nothing" rule in ControllerBetaGate.h.
    if isBeta {
      // The slot picker pushed from the Wii Remotes section writes straight to the registry, and
      // controllers connect and disconnect while this screen sits open, so the rows are rebuilt on
      // every appearance rather than only on load.
      VirtualWiiRemoteRegistry.shared().refresh()
    }

    tableView.reloadData()
  }

  // MARK: - Current values

  private var isBeta: Bool {
    return DOLControllerBetaGate.isEnabled()
  }

  private var currentMode: Mode {
    return isBeta ? .beta : .normal
  }

  private var currentPresentation: WiiRemotePresentation {
    return WiiRemotePresentation(rawValue: DOLControllerBetaSettings.presentation) ?? .normal
  }

  private var currentOrientationLock: WiiRemoteOrientationLock {
    return WiiRemoteOrientationLock(rawValue: DOLControllerBetaSettings.orientationLock) ?? .auto
  }

  /// nil when the player has left the emitter on Automatic.
  private var explicitPointerSource: WiiRemotePointerSource? {
    guard !DOLControllerBetaSettings.isPointerSourceAutomatic else {
      return nil
    }

    return WiiRemotePointerSource(rawValue: DOLControllerBetaSettings.pointerSourceOrAutomatic)
  }

  /// What the pointer actually is right now, explicit or implied.
  private var effectivePointerSource: WiiRemotePointerSource {
    return explicitPointerSource ?? currentPresentation.defaultPointerSource
  }

  // MARK: - UITableViewDataSource

  override func numberOfSections(in tableView: UITableView) -> Int {
    return isBeta ? Section.allCases.count : 1
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Section(rawValue: section) {
    case .mode:
      return Mode.allCases.count
    case .presentation:
      return WiiRemotePresentation.allCases.count
    case .pointerSource:
      return WiiRemotePointerSource.allCases.count + 1  // + Automatic
    case .orientation:
      return WiiRemoteOrientationLock.allCases.count
    case .tv:
      return TVRow.allCases.count
    case .remotes:
      return VirtualWiiRemoteRegistry.shared().slots.count
    case nil:
      return 0
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .mode: return "Controller Mode"
    case .presentation: return "Presentation"
    case .pointerSource: return "Pointer Source"
    case .orientation: return "Lock Wii Remote Orientation"
    case .tv: return "TV"
    case .remotes: return "Wii Remotes"
    case nil: return nil
    }
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .mode:
      return "Beta is experimental and changes how the Wii Remote is emulated. Switching back to "
        + "Normal always restores the original behaviour exactly \u{2014} nothing is migrated or "
        + "rewritten, so it is always safe to try."
    case .presentation:
      return "The TV presentations need an external display connected. Without one they behave "
        + "like their on-device counterparts."
    case .pointerSource:
      return "Where the Wii Remote's infrared emitter is treated as being. Automatic follows the "
        + "presentation: the front of a virtual remote in Normal Mode, the Apple logo everywhere "
        + "else. Changing this clears the pointer's centre, so recenter afterwards."
    case .orientation:
      return "Automatic switches between portrait and landscape as you turn the device. Locking "
        + "it keeps the emulated remote's axes fixed however you hold it."
    case .tv:
      return "Screen size and viewing distance are what turn a wrist rotation into a fraction of "
        + "the screen, and nothing on the device can measure them. A bigger screen or a shorter "
        + "distance means you move less to reach the edges."
    case .remotes:
      return "This device is always Wii Remote 1. Remotes 2 to 4 can be a game controller, or "
        + "another device running the Remote Controller screen on the same network. The game "
        + "can't tell the difference between any of them."
    case nil:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

    // Reused cells keep whatever the last row left behind, so anything a row can set has to be
    // cleared on every path through here.
    cell.accessoryType = .none
    cell.accessoryView = nil
    cell.selectionStyle = .default
    cell.accessibilityHint = nil
    cell.accessibilityTraits = [.button]

    switch Section(rawValue: indexPath.section) {
    case .mode:
      guard let mode = Mode(rawValue: indexPath.row) else { break }
      configure(cell, title: mode.title, subtitle: mode.detail, selected: mode == currentMode)

    case .presentation:
      guard let presentation = WiiRemotePresentation.allCases[safe: indexPath.row] else { break }
      configure(cell,
                title: presentation.displayName,
                subtitle: presentation.summary,
                selected: presentation == currentPresentation)

    case .pointerSource:
      if indexPath.row == ControllerBetaSettingsViewController.automaticPointerSourceRow {
        configure(cell,
                  title: "Automatic",
                  subtitle: "Follows the presentation \u{2014} currently \(effectivePointerSource.displayName).",
                  selected: explicitPointerSource == nil)
      } else if let source = WiiRemotePointerSource.allCases[safe: indexPath.row - 1] {
        configure(cell,
                  title: source.displayName,
                  subtitle: source.summary,
                  selected: explicitPointerSource == source)
      }

    case .orientation:
      guard let lock = WiiRemoteOrientationLock.allCases[safe: indexPath.row] else { break }
      configure(cell,
                title: lock.displayName,
                subtitle: nil,
                selected: lock == currentOrientationLock)

    case .tv:
      configureTVRow(cell, row: TVRow(rawValue: indexPath.row))

    case .remotes:
      configureRemoteRow(cell, at: indexPath.row)

    case nil:
      break
    }

    return cell
  }

  private func configureRemoteRow(_ cell: UITableViewCell, at row: Int) {
    let slots = VirtualWiiRemoteRegistry.shared().slots

    guard row < slots.count else {
      return
    }

    let slot = slots[row]

    var config = UIListContentConfiguration.subtitleCell()
    config.text = "Wii Remote \(slot.slot)"

    // Says "not connected" rather than just naming the device when the device isn't actually there.
    // A slot bound to a controller that's switched off looks identical to a working one otherwise,
    // and that's precisely the state someone opens this screen to diagnose.
    if slot.deviceQualifier != nil && !slot.isConnected {
      config.secondaryText = "\(slot.displayName) \u{2014} not connected"
    } else {
      config.secondaryText = slot.displayName
    }

    cell.contentConfiguration = config

    // Slot 1 is permanently this device, so there is nothing to choose and no disclosure arrow.
    if slot.slot == 1 {
      cell.accessoryType = .none
      cell.selectionStyle = .none
    } else {
      cell.accessoryType = .disclosureIndicator
    }
  }

  private func configure(_ cell: UITableViewCell, title: String, subtitle: String?, selected: Bool) {
    var config = UIListContentConfiguration.subtitleCell()
    config.text = title
    config.secondaryText = subtitle
    cell.contentConfiguration = config
    cell.accessoryType = selected ? .checkmark : .none

    // A checkmark is invisible to VoiceOver, which otherwise reads every row in a section
    // identically and gives no way to tell which one is in effect.
    cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
  }

  private func configureTVRow(_ cell: UITableViewCell, row: TVRow?) {
    guard let row = row else {
      return
    }

    var config = UIListContentConfiguration.valueCell()

    // Screen size, distance and aspect step through fixed values on tap rather than getting a
    // slider or a picker: a slider inside a table cell is fiddly on a device being held like a
    // remote, and none of these needs finer resolution than this to set pointer sensitivity.
    switch row {
    case .diagonal:
      config.text = "Screen Size"
      config.secondaryText = String(format: "%.0f in", Double(DOLControllerBetaSettings.tvDiagonalInches))
      cell.accessibilityHint = "Changes to the next size"
    case .distance:
      config.text = "Viewing Distance"
      config.secondaryText = String(format: "%.1f m", Double(DOLControllerBetaSettings.tvDistanceMetres))
      cell.accessibilityHint = "Changes to the next distance"
    case .widescreen:
      config.text = "Aspect Ratio"
      config.secondaryText = DOLControllerBetaSettings.tvIsWidescreen ? "16:9" : "4:3"
      cell.accessibilityHint = "Switches between 16:9 and 4:3"
    case .offerTVMode:
      // An on/off row, so a checkmark rather than a value -- and the checkmark alone is invisible
      // to VoiceOver, hence the trait.
      config.text = "Offer TV Mode When Connected"
      config.secondaryText = nil
      cell.accessoryType = DOLControllerBetaSettings.offersTVMode ? .checkmark : .none
      cell.accessibilityTraits = DOLControllerBetaSettings.offersTVMode ? [.button, .selected] : [.button]
      cell.accessibilityHint = nil
    }

    cell.contentConfiguration = config
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
      // The whole table's shape depends on the gate, so this is a full reload rather than a
      // section reload.
      tableView.reloadData()

    case .presentation:
      guard let presentation = WiiRemotePresentation.allCases[safe: indexPath.row] else { return }
      DOLControllerBetaSettings.presentation = presentation.rawValue
      // The Automatic pointer row's subtitle names the implied source, so it has to be redrawn
      // whenever the presentation changes.
      tableView.reloadSections(IndexSet([Section.presentation.rawValue,
                                         Section.pointerSource.rawValue]), with: .none)

    case .pointerSource:
      if indexPath.row == ControllerBetaSettingsViewController.automaticPointerSourceRow {
        DOLControllerBetaSettings.resetPointerSourceToAutomatic()
      } else if let source = WiiRemotePointerSource.allCases[safe: indexPath.row - 1] {
        DOLControllerBetaSettings.pointerSourceOrAutomatic = source.rawValue
      }
      tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)

    case .orientation:
      guard let lock = WiiRemoteOrientationLock.allCases[safe: indexPath.row] else { return }
      DOLControllerBetaSettings.orientationLock = lock.rawValue
      tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)

    case .tv:
      didSelectTVRow(TVRow(rawValue: indexPath.row), at: indexPath)

    case .remotes:
      let slots = VirtualWiiRemoteRegistry.shared().slots

      guard indexPath.row < slots.count else {
        return
      }

      let slot = slots[indexPath.row].slot

      guard slot > 1 else {
        return
      }

      navigationController?.pushViewController(
        ControllerBetaRemoteSlotViewController(slot: slot), animated: true)

    case nil:
      break
    }
  }

  private func didSelectTVRow(_ row: TVRow?, at indexPath: IndexPath) {
    guard let row = row else {
      return
    }

    switch row {
    case .diagonal:
      DOLControllerBetaSettings.tvDiagonalInches =
        ControllerBetaSettingsViewController.next(DOLControllerBetaSettings.tvDiagonalInches,
                                                 in: [24, 32, 40, 43, 50, 55, 65, 75, 85])
    case .distance:
      DOLControllerBetaSettings.tvDistanceMetres =
        ControllerBetaSettingsViewController.next(DOLControllerBetaSettings.tvDistanceMetres,
                                                 in: [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0])
    case .widescreen:
      DOLControllerBetaSettings.tvIsWidescreen = !DOLControllerBetaSettings.tvIsWidescreen
    case .offerTVMode:
      DOLControllerBetaSettings.offersTVMode = !DOLControllerBetaSettings.offersTVMode
    }

    tableView.reloadRows(at: [indexPath], with: .none)
  }

  /// The next value in a cycle, wrapping. Matches on nearest rather than equality so a value
  /// hand-edited into Dolphin.ini, or clamped on the way in, still advances instead of sticking.
  private static func next(_ current: Float, in options: [Float]) -> Float {
    guard !options.isEmpty else {
      return current
    }

    var nearest = 0
    for (index, option) in options.enumerated() {
      if abs(option - current) < abs(options[nearest] - current) {
        nearest = index
      }
    }

    return options[(nearest + 1) % options.count]
  }
}

private extension Array {
  /// Guards against a raw-value list and a row count drifting apart.
  subscript(safe index: Int) -> Element? {
    return indices.contains(index) ? self[index] : nil
  }
}
