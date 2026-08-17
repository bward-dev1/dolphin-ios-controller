// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "VirtualWiiRemoteRegistry.h"

#include <algorithm>
#include <string>
#include <vector>

#import "Common/Config/Config.h"

#import "Core/Config/WiimoteSettings.h"
#import "Core/HW/Wiimote.h"

#import "InputCommon/ControllerEmu/ControllerEmu.h"
#import "InputCommon/ControllerInterface/ControllerInterface.h"
#import "InputCommon/ControllerInterface/CoreDevice.h"
#import "InputCommon/InputConfig.h"

#import "FoundationStringUtil.h"

NSString* const DOLWiiRemoteRegistryDidChangeNotification =
    @"DOLWiiRemoteRegistryDidChangeNotification";

namespace
{
constexpr NSInteger kSlotCount = 4;

bool IsTouchscreen(const ciface::Core::DeviceQualifier& qualifier)
{
  return qualifier.source == "iOS" && qualifier.name == "Touchscreen";
}

// What kind of thing a device qualifier names, for display purposes only. Nothing behavioural
// hangs off this -- the input path is identical either way, which is the whole point.
DOLWiiRemoteBacking BackingForQualifier(const ciface::Core::DeviceQualifier& qualifier)
{
  if (IsTouchscreen(qualifier))
  {
    return DOLWiiRemoteBackingThisDevice;
  }

  // "DSUClient" is the source name Dolphin's CemuHook backend registers under. A device arriving
  // that way is another machine on the network -- for this app, most likely a second iOS device
  // running the Remote Controller screen, which is what DSUServerManager broadcasts for.
  if (qualifier.source == "DSUClient")
  {
    return DOLWiiRemoteBackingRemoteDevice;
  }

  return DOLWiiRemoteBackingLocalGamepad;
}

NSString* DisplayNameForBacking(DOLWiiRemoteBacking backing, NSString* qualifier)
{
  switch (backing)
  {
    case DOLWiiRemoteBackingNone:
      return @"Not connected";
    case DOLWiiRemoteBackingThisDevice:
      return @"This device";
    case DOLWiiRemoteBackingRealWiiRemote:
      return @"Real Wii Remote";
    case DOLWiiRemoteBackingLocalGamepad:
    case DOLWiiRemoteBackingRemoteDevice:
      return qualifier;
  }

  return qualifier;
}
}  // namespace

// Declared here rather than in the header: these are built by the registry and read by the UI,
// never constructed by callers.
@interface DOLWiiRemoteSlot ()

- (instancetype)initWithSlot:(NSInteger)slot
                     backing:(DOLWiiRemoteBacking)backing
                 displayName:(NSString*)displayName
             deviceQualifier:(NSString* _Nullable)deviceQualifier
                 isConnected:(BOOL)isConnected;

@end

@implementation DOLWiiRemoteSlot

- (instancetype)initWithSlot:(NSInteger)slot
                     backing:(DOLWiiRemoteBacking)backing
                 displayName:(NSString*)displayName
             deviceQualifier:(NSString* _Nullable)deviceQualifier
                 isConnected:(BOOL)isConnected {
  self = [super init];

  if (self != nil) {
    _slot = slot;
    _dolphinPort = slot - 1;
    _backing = backing;
    _displayName = [displayName copy];
    _deviceQualifier = [deviceQualifier copy];
    _isConnected = isConnected;
  }

  return self;
}

@end

@interface VirtualWiiRemoteRegistry ()

// Readonly in the header, writable here.
@property (nonatomic, copy) NSArray<DOLWiiRemoteSlot*>* slots;

- (void)postChangeNotification;

@end

@implementation VirtualWiiRemoteRegistry

+ (instancetype)shared {
  static VirtualWiiRemoteRegistry* instance;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    instance = [[VirtualWiiRemoteRegistry alloc] init];
  });

  return instance;
}

- (instancetype)init {
  self = [super init];

  if (self != nil) {
    self.slots = @[];
    [self refresh];
  }

  return self;
}

- (void)refresh {
  // RefreshDevices before reading: a pad connected since the last look would otherwise show as
  // disconnected, which is exactly the state a player is most likely to be looking at this screen
  // to fix.
  g_controller_interface.RefreshDevices();

  const std::vector<std::string> present = g_controller_interface.GetAllDeviceStrings();

  NSMutableArray<DOLWiiRemoteSlot*>* slots = [[NSMutableArray alloc] initWithCapacity:kSlotCount];

  for (NSInteger slot = 1; slot <= kSlotCount; slot++) {
    const int port = static_cast<int>(slot - 1);
    const WiimoteSource source = Config::Get(Config::GetInfoForWiimoteSource(port));

    if (source == WiimoteSource::None) {
      [slots addObject:[[DOLWiiRemoteSlot alloc] initWithSlot:slot
                                                      backing:DOLWiiRemoteBackingNone
                                                  displayName:DisplayNameForBacking(DOLWiiRemoteBackingNone, nil)
                                              deviceQualifier:nil
                                                  isConnected:NO]];
      continue;
    }

    if (source == WiimoteSource::Real) {
      // Dolphin's real-Wiimote path owns this entirely; there is no ciface device to name.
      [slots addObject:[[DOLWiiRemoteSlot alloc] initWithSlot:slot
                                                      backing:DOLWiiRemoteBackingRealWiiRemote
                                                  displayName:DisplayNameForBacking(DOLWiiRemoteBackingRealWiiRemote, nil)
                                              deviceQualifier:nil
                                                  isConnected:YES]];
      continue;
    }

    ControllerEmu::EmulatedController* controller = Wiimote::GetConfig()->GetController(port);
    const ciface::Core::DeviceQualifier& qualifier = controller->GetDefaultDevice();
    const std::string qualifierString = qualifier.ToString();

    if (qualifierString.empty()) {
      // Emulated, but bound to nothing. The game sees a Wii Remote that never does anything, which
      // is worth surfacing rather than drawing as if it were fine.
      [slots addObject:[[DOLWiiRemoteSlot alloc] initWithSlot:slot
                                                      backing:DOLWiiRemoteBackingNone
                                                  displayName:@"Emulated, but no device assigned"
                                              deviceQualifier:nil
                                                  isConnected:NO]];
      continue;
    }

    NSString* foundationQualifier = CppToFoundationString(qualifierString);
    const DOLWiiRemoteBacking backing = BackingForQualifier(qualifier);
    const bool isConnected =
        std::find(present.begin(), present.end(), qualifierString) != present.end();

    [slots addObject:[[DOLWiiRemoteSlot alloc] initWithSlot:slot
                                                    backing:backing
                                                displayName:DisplayNameForBacking(backing, foundationQualifier)
                                            deviceQualifier:foundationQualifier
                                                isConnected:isConnected]];
  }

  self.slots = slots;
}

- (NSArray<NSString*>*)assignableDeviceQualifiers {
  g_controller_interface.RefreshDevices();

  NSMutableArray<NSString*>* result = [[NSMutableArray alloc] init];

  for (const auto& name : g_controller_interface.GetAllDeviceStrings()) {
    ciface::Core::DeviceQualifier qualifier;
    qualifier.FromString(name);

    // Touchscreen devices are this device's own on-screen pads. The fork restricts them to port 0
    // (LegacyInputConfigMigrationService says so outright, and MappingRootViewController filters
    // them out for other ports), so offering one for slot 2-4 would be offering something that
    // cannot work.
    if (IsTouchscreen(qualifier)) {
      continue;
    }

    [result addObject:CppToFoundationString(name)];
  }

  return result;
}

- (BOOL)assignDeviceQualifier:(NSString*)qualifier toSlot:(NSInteger)slot {
  if (slot <= 1 || slot > kSlotCount) {
    // Slot 1 is permanently this device: it is what VirtualWiiRemote writes to, and the bundled
    // Touchscreen.ini profile is what maps it. Letting it be reassigned would leave the Beta
    // controller writing axes nothing was listening to.
    return NO;
  }

  const int port = static_cast<int>(slot - 1);

  ControllerEmu::EmulatedController* controller = Wiimote::GetConfig()->GetController(port);
  controller->SetDefaultDevice(FoundationToCppString(qualifier));
  controller->UpdateReferences(g_controller_interface);

  Wiimote::GetConfig()->SaveConfig();

  // Order matters: bind the device first, then switch the port on. The other way round briefly
  // presents the game with a Wii Remote wired to nothing.
  Config::SetBaseOrCurrent(Config::GetInfoForWiimoteSource(port), WiimoteSource::Emulated);
  Config::Save();

  [self refresh];
  [self postChangeNotification];

  return YES;
}

- (BOOL)clearSlot:(NSInteger)slot {
  if (slot <= 1 || slot > kSlotCount) {
    return NO;
  }

  const int port = static_cast<int>(slot - 1);

  Config::SetBaseOrCurrent(Config::GetInfoForWiimoteSource(port), WiimoteSource::None);
  Config::Save();

  // The device binding is deliberately left in place. Setting the source to None is what the game
  // sees as the remote unplugging; forgetting which pad was mapped to it as well would make
  // switching a remote off and on again a re-setup rather than a toggle.

  [self refresh];
  [self postChangeNotification];

  return YES;
}

- (void)postChangeNotification {
  dispatch_block_t notify = ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:DOLWiiRemoteRegistryDidChangeNotification
                      object:nil];
  };

  if ([NSThread isMainThread]) {
    notify();
  } else {
    dispatch_async(dispatch_get_main_queue(), notify);
  }
}

@end
