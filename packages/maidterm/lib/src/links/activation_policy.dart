import 'package:flutter/foundation.dart' show defaultTargetPlatform, internal;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:libghostty/libghostty.dart' show Mods;

import 'link_settings.dart';

/// Whether the current pointer and keyboard state can activate a link.
@internal
bool canActivateLink({
  required LinkSettings settings,
  required Mods virtualMods,
  PointerDeviceKind? pointerKind,
}) {
  if (settings.types.isEmpty || settings.onActivate == null) return false;
  if (pointerKind != null && pointerKind != .mouse) return true;

  final keyboard = HardwareKeyboard.instance;
  return switch (settings.modifier) {
    .none => true,
    .alt => keyboard.isAltPressed || virtualMods.hasAlt,
    .control => keyboard.isControlPressed || virtualMods.hasCtrl,
    .meta => keyboard.isMetaPressed || virtualMods.hasSuper,
    .shift => keyboard.isShiftPressed || virtualMods.hasShift,
    .primary => switch (defaultTargetPlatform) {
      .macOS || .iOS => keyboard.isMetaPressed || virtualMods.hasSuper,
      _ => keyboard.isControlPressed || virtualMods.hasCtrl,
    },
  };
}
