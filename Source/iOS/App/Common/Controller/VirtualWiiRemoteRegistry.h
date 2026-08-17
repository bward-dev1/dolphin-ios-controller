// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const DOLWiiRemoteRegistryDidChangeNotification;

typedef NS_ENUM(NSInteger, DOLWiiRemoteBacking) {
  /// Nothing plugged into this slot; the game sees no Wii Remote here.
  DOLWiiRemoteBackingNone,

  /// This device, via VirtualWiiRemote and CoreMotion. Only ever slot 1.
  DOLWiiRemoteBackingThisDevice,

  /// A game controller connected to this device (MFi, DualSense, Xbox, Joy-Con...).
  DOLWiiRemoteBackingLocalGamepad,

  /// Another device streaming input over Dolphin's CemuHook DSU protocol -- e.g. a second iPad
  /// running this app's Remote Controller screen, which is what DSUServerManager exists for.
  DOLWiiRemoteBackingRemoteDevice,

  /// A genuine Bluetooth Wii Remote, handled by Dolphin's own real-Wiimote path.
  DOLWiiRemoteBackingRealWiiRemote,
};

// One of the four Wii Remotes the game can see.
@interface DOLWiiRemoteSlot : NSObject

/// 1-4, as the game numbers them.
@property (nonatomic, readonly) NSInteger slot;

/// The Dolphin Wii Remote port, which is `slot - 1`.
///
/// Not to be confused with VirtualWiiRemote.port, which is a ciface::iOS::Touchscreen *device id*
/// in the 4-7 range. Two different numbering schemes for the same four remotes: Dolphin's
/// emulated-Wiimote ports are 0-3, and the touchscreen input devices backing them are 4-7. Getting
/// these two mixed up is the single most likely mistake in this file.
@property (nonatomic, readonly) NSInteger dolphinPort;

@property (nonatomic, readonly) DOLWiiRemoteBacking backing;

/// Human-readable, for the UI. Never nil.
@property (nonatomic, readonly, copy) NSString* displayName;

/// The ciface::Core::DeviceQualifier string Dolphin has this port bound to, e.g.
/// "iOS/4/Touchscreen". nil when the slot is empty.
@property (nonatomic, readonly, copy, nullable) NSString* deviceQualifier;

/// False when the slot is configured but the device it names isn't currently present -- an MFi pad
/// that has been switched off, a phone that has left the network.
@property (nonatomic, readonly) BOOL isConnected;

@end

// Which real device is standing in for each of the game's four Wii Remotes.
//
// The point of this class is the guarantee that the emulator cannot tell them apart, and the
// reason that guarantee is cheap is that it was already true: WiimoteEmu reads whatever
// ciface device its port is mapped to, so "make a DSU phone into Wii Remote 3" is a *mapping*
// problem, not a transport problem. Nothing here proxies or translates input. It configures which
// device each port listens to and reports the result.
//
// Division of labour, deliberately:
//
//   * This class binds a port to a device and sets that port's Wii Remote source. That is the part
//     that is the same for every kind of device.
//   * Which physical button on that device is Wii Remote A stays with Dolphin's existing Mapping
//     screen, which already does that job well for arbitrary devices. This class does not invent
//     button profiles for gamepads it has never seen.
//
// Slot 1 is special and fixed: it is this device, it is Dolphin Wii Remote port 0, and its mapping
// comes from the bundled Touchscreen.ini profile. The fork already restricts touchscreen devices to
// port 0 (see LegacyInputConfigMigrationService and MappingRootViewController's filtering), so
// slots 2-4 are necessarily backed by something else -- which is exactly the intended shape.
//
// Beta only.
@interface VirtualWiiRemoteRegistry : NSObject

+ (instancetype)shared;

/// Always four entries, slots 1-4 in order.
@property (nonatomic, readonly, copy) NSArray<DOLWiiRemoteSlot*>* slots;

/// Re-reads Dolphin's config and refreshes the device list. Call before showing any UI built from
/// `slots`; controllers connect and disconnect while nobody is looking.
- (void)refresh;

/// Device qualifier strings that could back slots 2-4, i.e. everything Dolphin can see except the
/// touchscreen devices (which are this device's own on-screen pads and belong to slot 1).
- (NSArray<NSString*>*)assignableDeviceQualifiers;

/// Points a slot at a device and switches that Wii Remote port on.
///
/// Returns NO for slot 1 (which is permanently this device) and for an out-of-range slot. Does not
/// validate that the device is currently connected: binding a pad that is switched off is a
/// legitimate thing to do before switching it on, and Dolphin already shows such a binding as
/// disconnected rather than losing it.
- (BOOL)assignDeviceQualifier:(NSString*)qualifier toSlot:(NSInteger)slot;

/// Empties a slot: the Wii Remote port is set to None, so the game sees the remote unplug.
- (BOOL)clearSlot:(NSInteger)slot;

@end

NS_ASSUME_NONNULL_END
