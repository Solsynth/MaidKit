import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The `User-Agent` MaidKit sends to Solar Network and MaidCafe servers.
///
/// Same shape as Solian's — `Solian/1.2.3+45 (MacOS; MacBookPro18,3; host)` —
/// so the gateway's audit log attributes both clients alike, with MaidKit's
/// name and this build's version in place of Solian's. Resolved once: package
/// and device info are platform-channel calls, and paying them per request
/// would put two round trips on every call.
Future<String> maidKitUserAgent() => _userAgent ??= _buildUserAgent();

Future<String>? _userAgent;

/// The header entries to send, empty in a browser: `User-Agent` is a forbidden
/// header there, so the platform drops it no matter what a client sets.
Future<Map<String, String>> maidKitUserAgentHeader() async => kIsWeb
    ? const <String, String>{}
    : <String, String>{'User-Agent': await maidKitUserAgent()};

/// Returns [dio], or a fresh client, with the MaidKit user agent attached.
///
/// The value is resolved inside the request queue, so a service built during
/// startup never has to await it. An injected client is stamped too, which is
/// what keeps a test's canned adapter on the same header path as production.
Dio maidKitDio([Dio? dio]) {
  final client = dio ?? Dio();
  if (!kIsWeb && !client.interceptors.any((i) => i is _UserAgentInterceptor)) {
    client.interceptors.add(_UserAgentInterceptor());
  }
  return client;
}

class _UserAgentInterceptor extends QueuedInterceptor {
  _UserAgentInterceptor();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['User-Agent'] ??= await maidKitUserAgent();
    handler.next(options);
  }
}

Future<String> _buildUserAgent() async {
  final package = await _try(PackageInfo.fromPlatform);
  final platformInfo = await _platformInfo();
  final version = package?.version.trim() ?? '';
  if (version.isEmpty) return 'MaidKit ($platformInfo)';
  final build = package!.buildNumber.trim();
  return 'MaidKit/$version${build.isEmpty ? '' : '+$build'} ($platformInfo)';
}

/// Device info is best effort: a host without the plugin (unit tests, a
/// stripped build) must still produce a header instead of failing the request.
Future<String> _platformInfo() async {
  try {
    if (kIsWeb) {
      final info = await DeviceInfoPlugin().webBrowserInfo;
      return 'Web; ${_sanitize(info.vendor ?? 'Unknown')}';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await DeviceInfoPlugin().androidInfo;
        return 'Android; ${_sanitize('${info.brand} ${info.model}')}; '
            '${_sanitize(info.id)}';
      case TargetPlatform.iOS:
        final info = await DeviceInfoPlugin().iosInfo;
        return 'iOS; ${_sanitize(info.model)}; ${_sanitize(info.name)}';
      case TargetPlatform.macOS:
        final info = await DeviceInfoPlugin().macOsInfo;
        return 'MacOS; ${_sanitize(info.model)}; ${_sanitize(info.hostName)}';
      case TargetPlatform.windows:
        final info = await DeviceInfoPlugin().windowsInfo;
        return 'Windows NT; ${_sanitize(info.productName)}; '
            '${_sanitize(info.computerName)}';
      case TargetPlatform.linux:
        final info = await DeviceInfoPlugin().linuxInfo;
        return 'Linux; ${_sanitize(info.prettyName)}';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  } catch (_) {
    // Fall through to the generic label.
  }
  return 'Unknown';
}

/// Keeps printable ASCII and replaces the rest with `_`, so a device name with
/// non-Latin characters or control codes cannot corrupt the header.
String _sanitize(String input) => input.runes
    .map((rune) => rune >= 32 && rune <= 126 ? String.fromCharCode(rune) : '_')
    .join();

Future<T?> _try<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (_) {
    return null;
  }
}
