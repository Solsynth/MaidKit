import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of the platform's alternate app icon state.
class AppIconState {
  final bool supported;
  final String? iconName;

  const AppIconState({required this.supported, this.iconName});

  /// `true` when the primary (default) app icon is active.
  bool get isPrimary => iconName == null;
}

/// Bridges alternate app icon switching to the native
/// `dev.solsynth.maidKit/app_icon` channel (iOS + macOS).
///
/// Preview artwork for the picker is bundled as Flutter assets (see
/// `assets/icons/`); this service only reads and sets the active icon.
class AppIconService {
  AppIconService._();

  static final instance = AppIconService._();
  static const _channel = MethodChannel('dev.solsynth.maidKit/app_icon');

  /// Alternate icon names bundled with the app.
  static const String cuiteIconName = 'AppIcon-Cuite';

  /// Preview asset for the primary (default) icon.
  static const String defaultIconAsset = 'assets/icons/app-icon-default.png';

  /// Preview asset for the Cuite alternate icon.
  static const String cuiteIconAsset = 'assets/icons/app-icon-cuite.png';

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Whether the current platform supports alternate app icon switching.
  bool get isSupported => _isSupported;

  Future<AppIconState?> getState() async {
    if (!_isSupported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getIconState',
      );
      return AppIconState(
        supported: result?['supported'] == true,
        iconName: result?['current'] as String?,
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> setIcon(String? name) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('setAlternateIcon', {'name': name});
  }
}
