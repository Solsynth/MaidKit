/// Web-safe stand-ins for the `dart:io` `Platform` queries MaidKit uses.
///
/// Flutter's web SDK ships a compilable `dart:io` whose members throw at
/// runtime, so importing it is fine but *calling* `Platform.isMacOS` in a
/// browser crashes. Every query that can be reached at runtime goes through
/// this file, which keeps the exact native answers on native platforms.
///
/// `defaultTargetPlatform` is the Flutter-level equivalent of `Platform.*` and
/// is always available; `dart:io` is still consulted for the few values Flutter
/// does not expose (environment, host name), guarded so a browser never reaches
/// them.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isWebPlatform => kIsWeb;

/// Desktop operating systems: the platforms with a window manager, native
/// menus and a real filesystem.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get isApplePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// The separator the platform's paths are written with, for the code that
/// builds paths by hand (`'$directory/$name'`).
String get platformPathSeparator =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows ? r'\' : '/';

/// `Platform.operatingSystem`, with the browser reported as `web`.
String get operatingSystemName => kIsWeb ? 'web' : Platform.operatingSystem;

/// The host name used when labelling a device, empty in a browser.
String get hostName => kIsWeb ? '' : Platform.localHostname;

/// The user's home directory, or null when the platform has no environment.
///
/// A home directory is a filesystem concept: a browser reports null and callers
/// fall back to an empty expansion.
String? get homeDirectory => kIsWeb ? null : Platform.environment['HOME'];
