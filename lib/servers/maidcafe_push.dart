import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

/// Shows a system notification. Safe to call from any isolate; the plugin is
/// created fresh so the background FCM isolate does not share main-isolate
/// state.
Future<void> showSystemNotification({
  required String title,
  required String body,
  required String channelId,
  required String channelName,
  String channelDescription = '',
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
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

/// Cold-start and background FCM entry point. The isolate has no access to
/// the widget tree, so it only surfaces the system notification; the cloud
/// history refreshes on the next page load.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  final title = data['title']?.toString() ?? 'MaidCafe';
  final body = data['body']?.toString() ?? data['content']?.toString() ?? '';
  if (body.isEmpty && title == 'MaidCafe') return;
  await showSystemNotification(
    title: title,
    body: body,
    channelId: 'maidcafe_cloud',
    channelName: 'MaidCafe Cloud',
    channelDescription: 'Notifications from the MaidCafe cloud',
  );
}

/// Registers this device for FCM push of MaidCafe cloud notifications,
/// mirroring Solian's `subscribePushNotification`
/// (`lib/core/services/notify.universal.dart`). The OAuth flow does not
/// populate Metoer's session client ID, so this service supplies a persistent
/// per-install device ID together with the current platform token.
enum MaidCafePushRegistrationStatus {
  unknown,
  notSignedIn,
  registering,
  registered,
  waitingForToken,
  unavailable,
  unsupported,
  failed,
}

const _maidCafePushDeviceIdKey = 'maidcafe_push_device_id';

Future<String> _loadMaidCafePushDeviceId() async {
  final preferences = SharedPreferencesAsync();
  final stored = (await preferences.getString(
    _maidCafePushDeviceIdKey,
  ))?.trim();
  if (stored != null && stored.isNotEmpty) return stored;
  final generated = Uuid().v4();
  await preferences.setString(_maidCafePushDeviceIdKey, generated);
  return generated;
}

class MaidCafePushService {
  MaidCafePushService({
    required this.client,
    required this.pushAllowed,
    required this.onNotification,
    this.onStatusChanged,
    this.deviceIdProvider,
  });

  /// Metoer client used to register the push subscription.
  final MaidCafeMetoerClient client;

  /// Consulted before every registration: false skips push entirely (e.g.
  /// the configured MaidCafe cloud is self-hosted and has no Ring
  /// publisher). Evaluated fresh so a later cloud-URL change is honored.
  final bool Function() pushAllowed;

  /// Invoked when a push notification arrives while the app is running, so
  /// the cloud notification history can refresh.
  final void Function() onNotification;

  /// Reports registration state to the settings UI.
  final void Function(MaidCafePushRegistrationStatus status)? onStatusChanged;

  /// Optional override for tests. The default is a persistent per-install ID.
  final Future<String> Function()? deviceIdProvider;

  Future<String>? _deviceId;
  Future<void>? _pending;
  bool _subscribed = false;
  bool _listenersAttached = false;

  MaidCafePushRegistrationStatus get initialStatus {
    if (!firebaseSupported()) {
      return MaidCafePushRegistrationStatus.unsupported;
    }
    if (!pushAllowed()) {
      return MaidCafePushRegistrationStatus.unavailable;
    }
    return MaidCafePushRegistrationStatus.unknown;
  }

  void refreshStatus({required bool signedIn}) {
    final status = !firebaseSupported()
        ? MaidCafePushRegistrationStatus.unsupported
        : !pushAllowed()
        ? MaidCafePushRegistrationStatus.unavailable
        : _subscribed
        ? MaidCafePushRegistrationStatus.registered
        : signedIn
        ? MaidCafePushRegistrationStatus.unknown
        : MaidCafePushRegistrationStatus.notSignedIn;
    onStatusChanged?.call(status);
  }

  void markNotSignedIn() {
    _subscribed = false;
    refreshStatus(signedIn: false);
  }

  /// Registers this device. A normal call is idempotent for the current
  /// session; concurrent calls share one attempt. [force] repeats the
  /// platform-token registration after a successful attempt so the settings
  /// retry action can repair a stale server-side subscription.
  Future<void> subscribe({bool force = false}) {
    if (!firebaseSupported()) {
      debugPrint(
        '[MaidCafePush] Skipping registration: Firebase is unsupported on '
        '${Platform.operatingSystem}.',
      );
      onStatusChanged?.call(MaidCafePushRegistrationStatus.unsupported);
      return Future.value();
    }
    if (!pushAllowed()) {
      debugPrint(
        '[MaidCafePush] Skipping registration: configured MaidCafe cloud '
        'does not support push.',
      );
      onStatusChanged?.call(MaidCafePushRegistrationStatus.unavailable);
      return Future.value();
    }
    if (_subscribed && !force) {
      debugPrint('[MaidCafePush] Already registered this session.');
      onStatusChanged?.call(MaidCafePushRegistrationStatus.registered);
      return Future.value();
    }
    if (_pending != null) return _pending!;
    debugPrint(
      '[MaidCafePush] Starting ${Platform.operatingSystem} registration.',
    );
    onStatusChanged?.call(MaidCafePushRegistrationStatus.registering);
    final attempt = _subscribe();
    _pending = attempt;
    return attempt;
  }

  Future<void> _subscribe() async {
    try {
      final registered = await _register();
      _subscribed = registered;
      debugPrint(
        registered
            ? '[MaidCafePush] Server accepted the push subscription.'
            : '[MaidCafePush] No device token is available yet.',
      );
      onStatusChanged?.call(
        registered
            ? MaidCafePushRegistrationStatus.registered
            : MaidCafePushRegistrationStatus.waitingForToken,
      );
    } catch (error, stackTrace) {
      debugPrint('[MaidCafePush] Registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      onStatusChanged?.call(MaidCafePushRegistrationStatus.failed);
      rethrow;
    } finally {
      _pending = null;
    }
  }

  Future<String> _deviceIdForRegistration() {
    return _deviceId ??= (deviceIdProvider ?? _loadMaidCafePushDeviceId)();
  }

  Future<bool> _register() async {
    if (!pushAllowed()) return false;
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[MaidCafePush] Notification permission: '
      '${permission.authorizationStatus}.',
    );
    if (!Platform.isAndroid) {
      // Explicitly re-enable auto-init here. The plugin's native setter calls
      // registerForRemoteNotifications(), which is needed when the launch-time
      // native registration ran before Firebase.initializeApp() completed.
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      debugPrint('[MaidCafePush] Requested native APNs registration.');
    }
    final deviceName = await _deviceName();

    if (Platform.isAndroid) {
      _attachListeners();
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint(
        token == null || token.isEmpty
            ? '[MaidCafePush] FCM token was empty.'
            : '[MaidCafePush] FCM token obtained.',
      );
      if (token != null && token.isNotEmpty) {
        await client.registerPushSubscription(
          deviceId: await _deviceIdForRegistration(),
          deviceToken: token,
          provider: maidCafePushProviderFcm,
          deviceName: deviceName,
        );
        return true;
      }
      return false;
    }

    // iOS/macOS: obtain APNs before using the token as the Apple push
    // subscription identity. The Firebase guide requires APNs to be ready
    // before making other Apple messaging API calls.
    final apnsToken = await _apnsTokenWithRetry();
    debugPrint(
      apnsToken == null || apnsToken.isEmpty
          ? '[MaidCafePush] APNs token was empty.'
          : '[MaidCafePush] APNs token obtained.',
    );
    _attachListeners();
    if (apnsToken != null && apnsToken.isNotEmpty) {
      await client.registerPushSubscription(
        deviceId: await _deviceIdForRegistration(),
        deviceToken: apnsToken,
        provider: maidCafePushProviderApple,
        deviceName: deviceName,
      );
      return true;
    }
    return false;
  }

  /// Attaches the token-refresh and foreground-message listeners once.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (!pushAllowed()) {
        debugPrint(
          '[MaidCafePush] Ignoring token refresh: push is not allowed.',
        );
        onStatusChanged?.call(MaidCafePushRegistrationStatus.unavailable);
        return;
      }
      debugPrint('[MaidCafePush] Token refresh received.');
      onStatusChanged?.call(MaidCafePushRegistrationStatus.registering);
      try {
        var registered = false;
        if (Platform.isAndroid) {
          await client.registerPushSubscription(
            deviceId: await _deviceIdForRegistration(),
            deviceToken: token,
            provider: maidCafePushProviderFcm,
            deviceName: await _deviceName(),
          );
          registered = token.isNotEmpty;
        } else {
          final apnsToken = await _apnsTokenWithRetry();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            await client.registerPushSubscription(
              deviceId: await _deviceIdForRegistration(),
              deviceToken: apnsToken,
              provider: maidCafePushProviderApple,
              deviceName: await _deviceName(),
            );
            registered = true;
          }
        }
        _subscribed = registered;
        debugPrint(
          registered
              ? '[MaidCafePush] Refreshed token registered.'
              : '[MaidCafePush] Refreshed token was empty.',
        );
        onStatusChanged?.call(
          registered
              ? MaidCafePushRegistrationStatus.registered
              : MaidCafePushRegistrationStatus.waitingForToken,
        );
      } catch (error, stackTrace) {
        debugPrint('[MaidCafePush] Token refresh registration failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        onStatusChanged?.call(MaidCafePushRegistrationStatus.failed);
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
      unawaited(
        showSystemNotification(
          title: title,
          body: body,
          channelId: 'maidcafe_cloud',
          channelName: 'MaidCafe Cloud',
          channelDescription: 'Notifications from the MaidCafe cloud',
        ),
      );
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
