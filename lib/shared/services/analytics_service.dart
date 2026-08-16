import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../../servers/maidcafe_push.dart';

/// Firebase Analytics for MaidKit, mirroring Solian's `AnalyticsService`:
/// a guarded singleton that never throws — analytics must never break the
/// app, and unsupported platforms (Linux, Windows) silently no-op.
///
/// Requires Firebase to be initialized first (see `main.dart`); [initialize]
/// is therefore only meaningful on platforms where [firebaseSupported] is
/// true and the caller runs it after `Firebase.initializeApp`.
class MaidKitAnalytics {
  MaidKitAnalytics._();

  static final MaidKitAnalytics instance = MaidKitAnalytics._();

  FirebaseAnalytics? _analytics;
  bool _enabled = true;

  void initialize() {
    if (!firebaseSupported()) return;
    try {
      _analytics = FirebaseAnalytics.instance;
    } catch (_) {
      _analytics = null;
    }
  }

  /// Master switch; kept for future privacy settings. Off stops all events
  /// (Firebase still collects nothing at the platform level either).
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Pseudo-anonymous account identity for analytics (the Solarpass handle;
  /// CloudUser has no stable id exposed). Cleared on sign-out.
  void setUserId(String? id) {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      analytics.setUserId(id: id);
    } catch (_) {
      // Never let analytics break the sign-in flow.
    }
  }

  void logEvent(String name, [Map<String, Object>? parameters]) {
    if (!_enabled) return;
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Fire-and-forget: a failed event must not surface to the user.
    }
  }

  void logAppOpen() {
    logEvent('app_open');
  }

  void logCloudSignIn() {
    logEvent('cloud_sign_in', {
      'platform': _platformName(),
      'cloud': 'solsynth',
    });
  }

  void logCloudSignOut() {
    logEvent('cloud_sign_out');
  }

  void logDaemonRegistered() {
    logEvent('daemon_registered');
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}
