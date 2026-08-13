import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_app_update/azhon_app_update.dart';
import 'package:flutter_app_update/result_model.dart';
import 'package:flutter_app_update/update_model.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:logging/logging.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:url_launcher/url_launcher.dart';

/// Data model for a Solsynth Express release we care about.
class DistributionReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String? htmlUrl;
  final DateTime createdAt;
  final List<DistributionArtifact> artifacts;

  const DistributionReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.createdAt,
    required this.artifacts,
  });

  DistributionArtifact? artifactFor(String platform, String architecture) {
    for (final artifact in artifacts) {
      if (artifact.platform == platform &&
          artifact.architecture == architecture &&
          artifact.downloadUrl.isNotEmpty) {
        return artifact;
      }
    }
    return null;
  }
}

class DistributionArtifact {
  final String platform;
  final String architecture;
  final String fileName;
  final String downloadUrl;

  const DistributionArtifact({
    required this.platform,
    required this.architecture,
    required this.fileName,
    required this.downloadUrl,
  });
}

class _UpdateTarget {
  final String platform;
  final String architecture;

  const _UpdateTarget(this.platform, this.architecture);
}

/// Parses version and build number from "x.y.z+build"
class _ParsedVersion implements Comparable<_ParsedVersion> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const _ParsedVersion(this.major, this.minor, this.patch, this.build);

  static _ParsedVersion? tryParse(String input) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?(?:[-+][0-9A-Za-z.-]+)?$',
    ).firstMatch(input.trim());
    if (match == null) return null;

    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    final build = int.tryParse(match.group(4) ?? '0');
    if (major == null || minor == null || patch == null || build == null) {
      return null;
    }

    return _ParsedVersion(major, minor, patch, build);
  }

  /// Normalize Android build numbers by removing architecture-based offsets.
  /// Android adds 1000 for x86, 2000 for ARMv7, 4000 for ARMv8.
  int get normalizedBuild {
    if (build >= 4000) {
      // Likely ARMv8 (arm64-v8a) with +4000 offset
      return build % 4000;
    } else if (build >= 2000) {
      // Likely ARMv7 (armeabi-v7a) with +2000 offset
      return build % 2000;
    } else if (build >= 1000) {
      // Likely x86/x86_64 with +1000 offset
      return build % 1000;
    }
    // No offset, return as-is
    return build;
  }

  @override
  int compareTo(_ParsedVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Use normalized build numbers for comparison to handle Android arch
    // offsets.
    return normalizedBuild.compareTo(other.normalizedBuild);
  }

  @override
  String toString() => '$major.$minor.$patch+$build';
}

const bool kEnableBuiltInUpdate = true;

Future<void> _cleanupFile(String? filePath) async {
  if (filePath == null || filePath.isEmpty) return;

  try {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    Logger.root.warning('[Update] Failed to delete file "$filePath": $e');
  }
}

Future<void> _cleanupDirectory(String? dirPath) async {
  if (dirPath == null || dirPath.isEmpty) return;

  try {
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e) {
    Logger.root.warning('[Update] Failed to delete directory "$dirPath": $e');
  }
}

class UpdateService {
  static const _configuredDistributionApiBaseUrl = String.fromEnvironment(
    'DISTRIBUTION_API_BASE_URL',
  );
  static const _configuredDistributionProductId = String.fromEnvironment(
    'DISTRIBUTION_PRODUCT_ID',
  );

  UpdateService({
    Dio? dio,
    String? distributionApiBaseUrl,
    String? distributionProductId,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               headers: const {
                 'Accept': 'application/json',
                 'User-Agent': 'maidkit-update-checker',
               },
               connectTimeout: Duration(seconds: 10),
               receiveTimeout: Duration(seconds: 15),
             ),
           ),
       _distributionApiBaseUrl =
           distributionApiBaseUrl ?? _configuredDistributionApiBaseUrl,
       _distributionProductId =
           distributionProductId ?? _configuredDistributionProductId;

  final Dio _dio;
  final String _distributionApiBaseUrl;
  final String _distributionProductId;

  /// Checks Solsynth Express for a newer release matching this device.
  /// Solsynth Express selects the compatible published artifact and returns
  /// its direct or signed download URL.
  Future<void> checkForUpdates(BuildContext context) async {
    if (!kEnableBuiltInUpdate) {
      Logger.root.info(
        '[Update] Built-in update is disabled via kEnableBuiltInUpdate',
      );
      return;
    }
    Logger.root.info('[Update] Checking Solsynth Express for updates...');
    try {
      final release = await _fetchUpdateRelease();
      if (release == null) {
        Logger.root.info(
          '[Update] No newer Solsynth Express release found or could not fetch.',
        );
        return;
      }
      Logger.root.info('[Update] Fetched latest release: ${release.tagName}');

      final info = await PackageInfo.fromPlatform();
      final localVersionStr = info.version;
      Logger.root.info('[Update] Local app version: $localVersionStr');

      final latest = _ParsedVersion.tryParse(release.tagName);
      final local = _ParsedVersion.tryParse(localVersionStr);
      if (latest == null || local == null) {
        Logger.root.info(
          '[Update] Failed to parse versions. Latest: ${release.tagName}, '
          'Local: $localVersionStr',
        );
        return;
      }
      Logger.root.info(
        '[Update] Parsed versions. Latest: $latest, Local: $local',
      );

      if (latest.compareTo(local) <= 0) {
        Logger.root.info('[Update] App is up to date. No update needed.');
        return;
      }
      Logger.root.info(
        '[Update] Update available! Latest: $latest, Local: $local',
      );

      if (!context.mounted) {
        Logger.root.info(
          '[Update] Context not mounted, cannot show update sheet.',
        );
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (context.mounted) {
        await showUpdateSheet(context, release);
        Logger.root.info('[Update] Update sheet shown.');
      }
    } catch (e) {
      Logger.root.severe('[Update] Error checking for updates: $e');
    }
  }

  /// Manually show the update sheet with a provided release.
  /// Useful for the About page or testing.
  Future<void> showUpdateSheet(
    BuildContext context,
    DistributionReleaseInfo release,
  ) async {
    if (!context.mounted) return;

    final target = await _updateTarget();
    if (!context.mounted) return;
    final artifact = target == null
        ? null
        : release.artifactFor(target.platform, target.architecture);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _UpdateSheet(
        release: release,
        onOpen: release.htmlUrl == null
            ? null
            : () async {
                final uri = Uri.parse(release.htmlUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
        androidUpdateUrl: Platform.isAndroid ? artifact?.downloadUrl : null,
        windowsUpdateUrl: Platform.isWindows ? artifact?.downloadUrl : null,
        linuxUpdateUrl: Platform.isLinux ? artifact?.downloadUrl : null,
      ),
    );
  }

  String _currentPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return '';
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
      final architecture =
          Platform.environment['PROCESSOR_ARCHITEW6432'] ??
          Platform.environment['PROCESSOR_ARCHITECTURE'];
      if (architecture != null) {
        return switch (architecture.toUpperCase()) {
          'AMD64' || 'X86_64' => 'amd64',
          'ARM64' => 'arm64',
          _ => architecture.toLowerCase(),
        };
      }
    }
    if (Platform.isLinux) return 'amd64';
    if (Platform.isMacOS) return 'arm64';
    if (Platform.isIOS) return 'arm64';
    return '';
  }

  Uri _updateUri({
    required String currentVersion,
    required String platform,
    required String architecture,
  }) {
    final baseUrl = _distributionApiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$baseUrl/products/${Uri.encodeComponent(_distributionProductId)}/update',
    ).replace(
      queryParameters: {
        'current_version': currentVersion,
        'channel': 'stable',
        'os': platform,
        'architecture': architecture,
      },
    );
  }

  bool _isAndroidUpdateApk(String fileName) {
    return fileName.startsWith('maidkit-update-') && fileName.endsWith('.apk');
  }

  bool _isWindowsUpdateZip(String fileName) {
    return fileName.startsWith('maidkit-installer-') &&
        fileName.endsWith('.zip');
  }

  bool _isWindowsExtractDir(String fileName) {
    return fileName.startsWith('maidkit-installer-');
  }

  bool _isLinuxUpdateFile(String fileName) {
    return fileName.startsWith('maidkit-linux-') &&
        (fileName.endsWith('.zip') || fileName.endsWith('.AppImage'));
  }

  Future<int> cleanupPreviousUpdateArtifacts() async {
    final tempDir = await getTemporaryDirectory();
    var deleted = 0;

    for (final entity in tempDir.listSync(followLinks: false)) {
      final fileName = path.basename(entity.path);
      try {
        if (entity is File &&
            (_isAndroidUpdateApk(fileName) ||
                _isWindowsUpdateZip(fileName) ||
                _isLinuxUpdateFile(fileName))) {
          await entity.delete();
          deleted++;
        } else if (entity is Directory &&
            (_isWindowsExtractDir(fileName) ||
                fileName.startsWith('maidkit-linux-'))) {
          await entity.delete(recursive: true);
          deleted++;
        }
      } catch (e) {
        Logger.root.warning('[Update] Failed to clean "$fileName": $e');
      }
    }

    return deleted;
  }

  Future<void> installAndroidUpdate(
    String url, {
    required String apkName,
    required String fallbackUrl,
  }) async {
    if (!Platform.isAndroid) return;

    AzhonAppUpdate.dispose();
    final model = UpdateModel(url, apkName, 'launcher_icon', fallbackUrl);

    AzhonAppUpdate.listener((ResultModel result) {
      if (result.type == ResultType.done) {
        unawaited(() async {
          await Future<void>.delayed(const Duration(seconds: 10));
          await _cleanupFile(result.apk);
        }());
      }
    });

    try {
      await AzhonAppUpdate.update(model);
    } catch (e) {
      Logger.root.warning('[Update] Android update failed to start: $e');
      AzhonAppUpdate.dispose();
      rethrow;
    }
  }

  /// Performs automatic Windows update: download, extract, and install.
  Future<void> performAutomaticWindowsUpdate(
    BuildContext context,
    String url,
  ) async {
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WindowsUpdateDialog(
        updateUrl: url,
        onComplete: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Performs automatic Linux update: download and install AppImage.
  Future<void> performAutomaticLinuxUpdate(
    BuildContext context,
    String url,
  ) async {
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LinuxUpdateDialog(
        updateUrl: url,
        onComplete: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Fetches the newest compatible published release from Solsynth Express.
  /// This powers the settings and onboarding release information views.
  Future<DistributionReleaseInfo?> fetchLatestRelease() async {
    final target = await _updateTarget();
    if (target == null) return null;

    final baseUrl = _distributionApiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri =
        Uri.parse(
          '$baseUrl/products/${Uri.encodeComponent(_distributionProductId)}/releases',
        ).replace(
          queryParameters: {
            'channel': 'stable',
            'platform': target.platform,
            'architecture': target.architecture,
            'limit': '1',
          },
        );
    Logger.root.info('[Update] Fetching release from Solsynth Express: $uri');

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200 || resp.data is! Map) {
      Logger.root.severe(
        '[Update] Failed to fetch release. Status code: ${resp.statusCode}',
      );
      return null;
    }

    final data = Map<String, dynamic>.from(resp.data as Map);
    final releases = data['data'];
    if (releases is! List || releases.isEmpty || releases.first is! Map) {
      Logger.root.info('[Update] No published release is available.');
      return null;
    }
    return _parseRelease(Map<String, dynamic>.from(releases.first as Map));
  }

  Future<DistributionReleaseInfo?> _fetchUpdateRelease() async {
    final target = await _updateTarget();
    if (target == null) return null;

    final info = await PackageInfo.fromPlatform();
    final uri = _updateUri(
      currentVersion: info.version,
      platform: target.platform,
      architecture: target.architecture,
    );
    Logger.root.info('[Update] Checking Solsynth Express: $uri');

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200 || resp.data is! Map) {
      Logger.root.severe(
        '[Update] Failed to check for updates. Status code: ${resp.statusCode}',
      );
      return null;
    }

    final data = Map<String, dynamic>.from(resp.data as Map);
    if (data['update_available'] != true || data['release'] is! Map) {
      Logger.root.info('[Update] No compatible update is available.');
      return null;
    }
    return _parseRelease(Map<String, dynamic>.from(data['release'] as Map));
  }

  Future<_UpdateTarget?> _updateTarget() async {
    if (_distributionApiBaseUrl.trim().isEmpty ||
        _distributionProductId.trim().isEmpty) {
      Logger.root.warning(
        '[Update] Solsynth Express update configuration is missing.',
      );
      return null;
    }

    final platform = _currentPlatform();
    final architecture = await _currentArchitecture();
    if (platform.isEmpty || architecture.isEmpty) {
      Logger.root.warning(
        '[Update] Unsupported update target: '
        'platform=$platform architecture=$architecture',
      );
      return null;
    }
    return _UpdateTarget(platform, architecture);
  }

  DistributionReleaseInfo? _parseRelease(Map<String, dynamic> releaseData) {
    final version = (releaseData['version'] ?? '').toString();
    final artifacts = <DistributionArtifact>[];
    final artifactData = releaseData['artifacts'];
    if (artifactData is List) {
      for (final rawArtifact in artifactData) {
        if (rawArtifact is! Map) continue;
        final artifact = Map<String, dynamic>.from(rawArtifact);
        final downloadUrl = (artifact['download_url'] ?? '').toString();
        if (downloadUrl.isEmpty) continue;
        artifacts.add(
          DistributionArtifact(
            platform: (artifact['platform'] ?? '').toString(),
            architecture: (artifact['architecture'] ?? '').toString(),
            fileName: (artifact['file_name'] ?? '').toString(),
            downloadUrl: downloadUrl,
          ),
        );
      }
    }

    if (version.isEmpty || artifacts.isEmpty) {
      Logger.root.warning(
        '[Update] Solsynth Express returned an incomplete release.',
      );
      return null;
    }

    final publishedAt =
        DateTime.tryParse((releaseData['published_at'] ?? '').toString()) ??
        DateTime.now();
    Logger.root.info('[Update] Returning Solsynth Express release: $version');
    return DistributionReleaseInfo(
      tagName: version,
      name: (releaseData['title'] ?? version).toString(),
      body: (releaseData['release_notes'] ?? releaseData['description'] ?? '')
          .toString(),
      htmlUrl: (releaseData['html_url'] ?? '').toString().isEmpty
          ? null
          : releaseData['html_url'].toString(),
      createdAt: publishedAt,
      artifacts: artifacts,
    );
  }
}

class _WindowsUpdateDialog extends StatefulWidget {
  const _WindowsUpdateDialog({
    required this.updateUrl,
    required this.onComplete,
  });

  final String updateUrl;
  final VoidCallback onComplete;

  @override
  State<_WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<_WindowsUpdateDialog> {
  final ValueNotifier<double?> progressNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<String> messageNotifier = ValueNotifier<String>(
    'updateDownloadingInstaller'.tr(),
  );

  @override
  void initState() {
    super.initState();
    _startUpdate();
  }

  Future<void> _startUpdate() async {
    String? zipPath;
    String? extractDir;

    try {
      // Step 1: Download
      zipPath = await _downloadWindowsInstaller(
        widget.updateUrl,
        onProgress: (received, total) {
          if (total == -1) {
            progressNotifier.value = null;
          } else {
            progressNotifier.value = received / total;
          }
        },
      );
      if (zipPath == null) {
        _showError('updateFailedDownloadInstaller'.tr());
        return;
      }

      // Step 2: Extract
      messageNotifier.value = 'updateExtractingInstaller'.tr();
      progressNotifier.value = null; // Indeterminate for extraction

      extractDir = await _extractWindowsInstaller(zipPath);
      if (extractDir == null) {
        _showError('updateFailedExtractInstaller'.tr());
        return;
      }

      // Step 3: Run installer
      messageNotifier.value = 'updateRunningInstaller'.tr();

      final success = await _runWindowsInstaller(extractDir);
      if (!mounted) return;

      if (success) {
        messageNotifier.value = 'updateComplete'.tr();
        progressNotifier.value = 1.0;
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
          widget.onComplete();
        }
      } else {
        _showError('updateFailedRunInstaller'.tr());
      }
    } catch (e) {
      _showError('updateFailedGeneric'.tr(args: ['$e']));
    } finally {
      await _cleanupFile(zipPath);
      await _cleanupDirectory(extractDir);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('updateFailedTitle'.tr()),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('commonOk'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('updateInstallingTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: progressNotifier,
            builder: (context, progress, child) {
              return LinearProgressIndicator(value: progress);
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: messageNotifier,
            builder: (context, message, child) {
              return Text(message);
            },
          ),
        ],
      ),
    );
  }

  /// Downloads the Windows installer ZIP file
  Future<String?> _downloadWindowsInstaller(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      Logger.root.info(
        '[Update] Starting Windows installer download from: $url',
      );

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'maidkit-installer-${DateTime.now().millisecondsSinceEpoch}.zip';
      final filePath = path.join(tempDir.path, fileName);

      final response = await Dio().download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            Logger.root.info(
              '[Update] Download progress: '
              '${(received / total * 100).toStringAsFixed(1)}%',
            );
          }
          onProgress?.call(received, total);
        },
      );

      if (response.statusCode == 200) {
        Logger.root.info(
          '[Update] Windows installer downloaded successfully to: $filePath',
        );
        return filePath;
      } else {
        Logger.root.severe(
          '[Update] Failed to download Windows installer. Status: '
          '${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      Logger.root.severe('[Update] Error downloading Windows installer: $e');
      return null;
    }
  }

  /// Extracts the ZIP file to a temporary directory
  Future<String?> _extractWindowsInstaller(String zipPath) async {
    try {
      Logger.root.info('[Update] Extracting Windows installer from: $zipPath');

      final tempDir = await getTemporaryDirectory();
      final extractDir = path.join(
        tempDir.path,
        'maidkit-installer-${DateTime.now().millisecondsSinceEpoch}',
      );

      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final filePath = path.join(extractDir, filename);
          await Directory(path.dirname(filePath)).create(recursive: true);
          await File(filePath).writeAsBytes(data);
        } else {
          final dirPath = path.join(extractDir, filename);
          await Directory(dirPath).create(recursive: true);
        }
      }

      Logger.root.info(
        '[Update] Windows installer extracted successfully to: $extractDir',
      );
      return extractDir;
    } catch (e) {
      Logger.root.severe('[Update] Error extracting Windows installer: $e');
      return null;
    }
  }

  /// Runs the setup.exe file
  Future<bool> _runWindowsInstaller(String extractDir) async {
    try {
      Logger.root.info('[Update] Running Windows installer from: $extractDir');

      final dir = Directory(extractDir);
      final exeFiles = dir
          .listSync()
          .where((f) => f is File && f.path.endsWith('.exe'))
          .toList();

      if (exeFiles.isEmpty) {
        Logger.root.info('[Update] No .exe file found in extracted directory');
        return false;
      }

      final setupExePath = exeFiles.first.path;
      Logger.root.info('[Update] Found installer executable: $setupExePath');

      final shell = Shell();
      final results = await shell.run(setupExePath);
      final result = results.first;

      if (result.exitCode == 0) {
        Logger.root.info('[Update] Windows installer completed successfully');
        return true;
      } else {
        Logger.root.severe(
          '[Update] Windows installer failed with exit code: '
          '${result.exitCode}',
        );
        Logger.root.severe('[Update] Installer output: ${result.stdout}');
        Logger.root.severe('[Update] Installer errors: ${result.stderr}');
        return false;
      }
    } catch (e) {
      Logger.root.severe('[Update] Error running Windows installer: $e');
      return false;
    }
  }
}

class _LinuxUpdateDialog extends StatefulWidget {
  const _LinuxUpdateDialog({required this.updateUrl, required this.onComplete});

  final String updateUrl;
  final VoidCallback onComplete;

  @override
  State<_LinuxUpdateDialog> createState() => _LinuxUpdateDialogState();
}

class _LinuxUpdateDialogState extends State<_LinuxUpdateDialog> {
  final ValueNotifier<double?> progressNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<String> messageNotifier = ValueNotifier<String>(
    'updateDownloadingAppImage'.tr(),
  );

  @override
  void initState() {
    super.initState();
    _startUpdate();
  }

  Future<void> _startUpdate() async {
    String? appImagePath;

    try {
      // Step 1: Download
      appImagePath = await _downloadLinuxAppImage(
        widget.updateUrl,
        onProgress: (received, total) {
          if (total == -1) {
            progressNotifier.value = null;
          } else {
            progressNotifier.value = received / total;
          }
        },
      );
      if (appImagePath == null) {
        _showError('updateFailedDownloadAppImage'.tr());
        return;
      }

      // Step 2: Make executable and move to applications directory
      messageNotifier.value = 'updateInstallingAppImage'.tr();
      progressNotifier.value = null;

      final success = await _installLinuxAppImage(appImagePath);
      if (!mounted) return;

      if (success) {
        messageNotifier.value = 'updateComplete'.tr();
        progressNotifier.value = 1.0;
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
          widget.onComplete();
        }
      } else {
        _showError('updateFailedInstallAppImage'.tr());
      }
    } catch (e) {
      _showError('updateFailedGeneric'.tr(args: ['$e']));
    } finally {
      await _cleanupFile(appImagePath);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('updateFailedTitle'.tr()),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('commonOk'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('updateInstallingTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: progressNotifier,
            builder: (context, progress, child) {
              return LinearProgressIndicator(value: progress);
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: messageNotifier,
            builder: (context, message, child) {
              return Text(message);
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _downloadLinuxAppImage(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      Logger.root.info('[Update] Starting Linux AppImage download from: $url');

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'maidkit-linux-${DateTime.now().millisecondsSinceEpoch}.zip';
      final filePath = path.join(tempDir.path, fileName);

      final response = await Dio().download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            Logger.root.info(
              '[Update] Download progress: '
              '${(received / total * 100).toStringAsFixed(1)}%',
            );
          }
          onProgress?.call(received, total);
        },
      );

      if (response.statusCode == 200) {
        Logger.root.info(
          '[Update] Linux AppImage downloaded successfully to: $filePath',
        );
        return filePath;
      } else {
        Logger.root.severe(
          '[Update] Failed to download Linux AppImage. Status: '
          '${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      Logger.root.severe('[Update] Error downloading Linux AppImage: $e');
      return null;
    }
  }

  Future<bool> _installLinuxAppImage(String zipPath) async {
    try {
      Logger.root.info('[Update] Installing Linux AppImage from: $zipPath');

      final tempDir = await getTemporaryDirectory();
      final extractDir = path.join(
        tempDir.path,
        'maidkit-linux-${DateTime.now().millisecondsSinceEpoch}',
      );

      // Extract the zip
      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      String? appImageFile;
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final filePath = path.join(extractDir, filename);
          await Directory(path.dirname(filePath)).create(recursive: true);
          await File(filePath).writeAsBytes(data);
          if (filename.endsWith('.AppImage')) {
            appImageFile = filePath;
          }
        } else {
          final dirPath = path.join(extractDir, filename);
          await Directory(dirPath).create(recursive: true);
        }
      }

      if (appImageFile == null) {
        Logger.root.severe('[Update] No AppImage file found in archive');
        return false;
      }

      // Make executable
      final shell = Shell();
      await shell.run('chmod +x $appImageFile');

      // Move to a permanent location (e.g., ~/.local/bin)
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) {
        Logger.root.severe('[Update] Cannot determine HOME directory');
        return false;
      }

      final appsDir = path.join(homeDir, '.local', 'bin');
      await Directory(appsDir).create(recursive: true);

      final destPath = path.join(appsDir, 'maidkit.AppImage');
      await File(appImageFile).copy(destPath);
      await File(destPath).setLastModified(DateTime.now());

      Logger.root.info('[Update] Linux AppImage installed to: $destPath');
      return true;
    } catch (e) {
      Logger.root.severe('[Update] Error installing Linux AppImage: $e');
      return false;
    }
  }
}

/// Renders the release changelog as markdown, following the same
/// configuration MaidKit uses for agent messages.
class _ChangelogBody extends StatelessWidget {
  const _ChangelogBody({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark
        ? MarkdownConfig.darkConfig
        : MarkdownConfig.defaultConfig;
    return MarkdownBlock(
      data: content,
      selectable: true,
      config: base.copy(
        configs: [
          PConfig(textStyle: theme.textTheme.bodyMedium!),
          PreConfig(
            textStyle: const TextStyle(fontSize: 13),
            styleNotMatched: const TextStyle(fontSize: 13),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          CodeConfig(
            style: TextStyle(backgroundColor: scheme.surfaceContainerHighest),
          ),
          TableConfig(
            wrapper: (child) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
          LinkConfig(
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
      generator: MarkdownGenerator(
        linesMargin: const EdgeInsets.symmetric(vertical: 4),
      ),
    );
  }
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({
    required this.release,
    this.onOpen,
    this.androidUpdateUrl,
    this.windowsUpdateUrl,
    this.linuxUpdateUrl,
  });

  final String? androidUpdateUrl;
  final String? windowsUpdateUrl;
  final String? linuxUpdateUrl;
  final DistributionReleaseInfo release;
  final VoidCallback? onOpen;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      titleText: 'updateAvailable'.tr(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.release.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.release.tagName,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: widget.release.body.isEmpty
                    ? Text('noChangelogProvided'.tr())
                    : _ChangelogBody(content: widget.release.body),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 8,
                children: [
                  if (!kIsWeb &&
                      Platform.isAndroid &&
                      widget.androidUpdateUrl != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          UpdateService().installAndroidUpdate(
                            widget.androidUpdateUrl!,
                            apkName:
                                'maidkit-update-${widget.release.tagName}.apk',
                            fallbackUrl: widget.androidUpdateUrl!,
                          );
                        },
                        icon: const Icon(Symbols.update),
                        label: Text('installUpdate'.tr()),
                      ),
                    ),
                  if (!kIsWeb &&
                      Platform.isWindows &&
                      widget.windowsUpdateUrl != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          UpdateService().performAutomaticWindowsUpdate(
                            context,
                            widget.windowsUpdateUrl!,
                          );
                        },
                        icon: const Icon(Symbols.update),
                        label: Text('installUpdate'.tr()),
                      ),
                    ),
                  if (!kIsWeb &&
                      Platform.isLinux &&
                      widget.linuxUpdateUrl != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          UpdateService().performAutomaticLinuxUpdate(
                            context,
                            widget.linuxUpdateUrl!,
                          );
                        },
                        icon: const Icon(Symbols.update),
                        label: Text('installUpdate'.tr()),
                      ),
                    ),
                  if (widget.onOpen != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onOpen,
                        icon: const Icon(Icons.open_in_new),
                        label: Text('openReleasePage'.tr()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
