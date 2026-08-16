import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'maidcafe_metoer.dart';

/// Wire values of `SnNotificationPushSubscription.Provider`
/// (`SolarNetwork/Metoer/internal/model/notification.go`): Apple APNs = 0,
/// Google FCM = 1.
const maidCafePushProviderApple = 0;
const maidCafePushProviderFcm = 1;

/// Firebase is only available on platforms firebase_core/firebase_messaging
/// support and that have a registered Firebase app (Android, iOS, macOS).
/// Linux, Windows and the web silently keep the in-app Metoer feed as their
/// only notification surface.
bool firebaseSupported() {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

/// True when [cloudUrl] points at a Solsynth-hosted MaidCafe cloud
/// (`*.solsynth.dev` or `*.solian.app`, apex included). Only these publish
/// daemon notifications to the Solar Network Ring, so FCM push is only
/// meaningful against them; a self-hosted cloud has no Ring publisher and
/// the device must not register a push subscription for it.
bool maidCafeCloudSupportsPush(String cloudUrl) {
  final host = Uri.tryParse(cloudUrl)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  return host == 'solsynth.dev' ||
      host.endsWith('.solsynth.dev') ||
      host == 'solian.app' ||
      host.endsWith('.solian.app');
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Shows a system notification for a MaidCafe cloud push. Safe to call from
/// any isolate; the plugin is created fresh so the background FCM isolate
/// does not share main-isolate state.
Future<void> _showLocalNotification({
  required String title,
  required String body,
}) async {
  final plugin = _localNotifications;
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
  );
  await plugin.initialize(settings: settings);
  await plugin.show(
    id: 0,
    title: title,
    body: body.isEmpty ? null : body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'maidcafe_cloud',
        'MaidCafe Cloud',
        channelDescription: 'Notifications from the MaidCafe cloud',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

/// Cold-start and background FCM entry point. The isolate has no access to
/// the widget tree, so it only surfaces the system notification; the feed
/// refreshes on the next page load.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  final title = data['title']?.toString() ?? 'MaidCafe';
  final body = data['body']?.toString() ?? data['content']?.toString() ?? '';
  if (body.isEmpty && title == 'MaidCafe') return;
  await _showLocalNotification(title: title, body: body);
}

/// Registers this device for FCM push of MaidCafe cloud notifications,
/// mirroring Solian's `subscribePushNotification`
/// (`lib/core/services/notify.universal.dart`). The Metoer subscription is
/// keyed by device token and carries the MaidCafe app id, so only daemon
/// notifications reach this device.
class MaidCafePushService {
  MaidCafePushService({
    required this.client,
    required this.pushAllowed,
    required this.onNotification,
  });

  /// Metoer client used to register the push subscription.
  final MaidCafeMetoerClient client;

  /// Consulted before every registration: false skips push entirely (e.g.
  /// the configured MaidCafe cloud is self-hosted and has no Ring
  /// publisher). Evaluated fresh so a later cloud-URL change is honored.
  final bool Function() pushAllowed;

  /// Invoked when a push notification arrives while the app is running, so
  /// the in-app Metoer feed can refresh.
  final void Function() onNotification;

  Future<void>? _pending;
  bool _subscribed = false;
  bool _listenersAttached = false;

  /// Registers this device once per session. Idempotent: concurrent calls
  /// share one attempt and later calls are no-ops after a successful
  /// registration. A failed attempt is retried by the next call (e.g. the
  /// next sign-in).
  Future<void> subscribe() {
    if (!firebaseSupported() || !pushAllowed() || _subscribed) {
      return Future.value();
    }
    return _pending ??= _register()
        .then((_) {
          _subscribed = true;
        })
        .whenComplete(() {
          _pending = null;
        });
  }

  Future<void> _register() async {
    if (!pushAllowed()) return;
    _attachListeners();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final deviceName = await _deviceName();

    if (Platform.isAndroid) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await client.registerPushSubscription(
          deviceToken: token,
          provider: maidCafePushProviderFcm,
          deviceName: deviceName,
        );
      }
      return;
    }

    // iOS/macOS: the APNs token is the FCM identity; it may not be ready at
    // cold start, so poll briefly (Solian polls the same way).
    final apnsToken = await _apnsTokenWithRetry();
    if (apnsToken != null && apnsToken.isNotEmpty) {
      await client.registerPushSubscription(
        deviceToken: apnsToken,
        provider: maidCafePushProviderApple,
        deviceName: deviceName,
      );
    }
  }

  /// Attaches the token-refresh and foreground-message listeners once.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (!pushAllowed()) return;
      try {
        if (Platform.isAndroid) {
          await client.registerPushSubscription(
            deviceToken: token,
            provider: maidCafePushProviderFcm,
            deviceName: await _deviceName(),
          );
        } else {
          final apnsToken = await _apnsTokenWithRetry();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            await client.registerPushSubscription(
              deviceToken: apnsToken,
              provider: maidCafePushProviderApple,
              deviceName: await _deviceName(),
            );
          }
        }
      } catch (_) {
        // Registration is an upsert; the next token refresh or sign-in
        // retries it. Never let push bookkeeping crash the app.
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      // A stale subscription (user switched to a self-hosted cloud after
      // registering) must not surface pushes or refresh the feed.
      if (!pushAllowed()) return;
      final data = message.data;
      final title = data['title']?.toString() ?? 'MaidCafe';
      final body =
          data['body']?.toString() ?? data['content']?.toString() ?? '';
      if (title == 'MaidCafe' && body.isEmpty) return;
      unawaited(_showLocalNotification(title: title, body: body));
      onNotification();
    });
  }

  Future<String?> _apnsTokenWithRetry() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<String> _deviceName() async {
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final model = info.model;
        if (model.trim().isNotEmpty) return model.trim();
      } catch (_) {
        // Fall through to the hostname default.
      }
    }
    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) return hostname;
    } catch (_) {
      // Fall through.
    }
    return 'MaidKit device';
  }
}
