import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:solsynth_express/solsynth_express.dart';

/// Build-number-aware update checks for MaidKit.
///
/// Android commonly keeps the human-readable version name unchanged between
/// builds. Comparing only [PackageInfo.version] repeatedly offers the same APK
/// to users who have already installed it.
class MaidKitUpdateService extends UpdateService {
  MaidKitUpdateService({
    required SolsynthExpressApi api,
    super.channel,
    super.enabled,
  }) : _api = api,
       super(api: api);

  factory MaidKitUpdateService.forProduct({
    required String productId,
    String channel = 'stable',
    bool enabled = true,
  }) {
    final api = SolsynthExpressApi(
      baseUrl: const String.fromEnvironment('DISTRIBUTION_API_BASE_URL'),
      productId: productId,
    );
    return MaidKitUpdateService(api: api, channel: channel, enabled: enabled);
  }

  final SolsynthExpressApi _api;

  @override
  Future<void> checkForUpdates(BuildContext context) async {
    if (!enabled || kIsWeb || !_api.isConfigured) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final target = await _currentTarget();
      if (target == null) return;
      final currentVersion = installedUpdateVersion(info);
      final result = await _api.checkForUpdate(
        currentVersion: currentVersion,
        platform: target.platform,
        architecture: target.architecture,
        channel: channel,
        clientVersion: currentVersion,
      );
      final release = result.release;
      if (!result.updateAvailable ||
          release == null ||
          !isDistributionReleaseNewer(release.tagName, currentVersion) ||
          !context.mounted) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (context.mounted) await showUpdateSheet(context, release);
    } catch (error, stackTrace) {
      Logger.root.severe('[MaidKit] Update check failed', error, stackTrace);
    }
  }

  /// Returns null when the newest published release is already installed.
  Future<DistributionReleaseInfo?> fetchLatestAvailableRelease() async {
    final release = await fetchLatestRelease();
    if (release == null) return null;
    final currentVersion = installedUpdateVersion(
      await PackageInfo.fromPlatform(),
    );
    return isDistributionReleaseNewer(release.tagName, currentVersion)
        ? release
        : null;
  }

  Future<_UpdateTarget?> _currentTarget() async {
    if (kIsWeb) return null;
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : Platform.isLinux
        ? 'linux'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isIOS
        ? 'ios'
        : '';
    if (platform.isEmpty) return null;
    final architecture = await _currentArchitecture();
    return architecture.isEmpty ? null : _UpdateTarget(platform, architecture);
  }

  Future<String> _currentArchitecture() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      for (final abi in info.supportedAbis) {
        switch (abi) {
          case 'arm64-v8a':
            return 'arm64';
          case 'armeabi-v7a':
            return 'armeabi-v7a';
          case 'x86_64':
            return 'x86_64';
          case 'x86':
            return 'x86';
        }
      }
    }
    if (Platform.isWindows) {
      final value =
          Platform.environment['PROCESSOR_ARCHITEW6432'] ??
          Platform.environment['PROCESSOR_ARCHITECTURE'];
      if (value != null) {
        return switch (value.toUpperCase()) {
          'AMD64' || 'X86_64' => 'amd64',
          'ARM64' => 'arm64',
          _ => value.toLowerCase(),
        };
      }
    }
    if (Platform.isLinux) return 'amd64';
    if (Platform.isMacOS || Platform.isIOS) return 'arm64';
    return '';
  }
}

String installedUpdateVersion(PackageInfo info) {
  final build = info.buildNumber.trim();
  return build.isEmpty ? info.version : '${info.version}+$build';
}

bool isDistributionReleaseNewer(String release, String installed) {
  final remote = _tryParseVersion(release);
  final local = _tryParseVersion(installed);
  if (remote == null || local == null) return release != installed;
  final precedence = remote.compareTo(local);
  if (precedence != 0) return precedence > 0;

  final remoteBuild = int.tryParse(remote.build.firstOrNull?.toString() ?? '');
  final localBuild = int.tryParse(local.build.firstOrNull?.toString() ?? '');
  if (remoteBuild == null) return false;
  return remoteBuild > (localBuild ?? 0);
}

Version? _tryParseVersion(String value) {
  try {
    return Version.parse(value.replaceFirst(RegExp(r'^[vV]'), ''));
  } on FormatException {
    return null;
  }
}

class _UpdateTarget {
  const _UpdateTarget(this.platform, this.architecture);

  final String platform;
  final String architecture;
}
