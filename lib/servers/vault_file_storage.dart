import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Owns vault database files after they have been selected or created by the
/// user.
///
/// New vaults created by the UI live in a user-selected folder instead of
/// application support, so file synchronization tools can see the database.
class VaultFileStorage {
  static const _directoryName = 'vaults';
  static const _extension = '.maidkit';
  final Uuid _uuid = const Uuid();

  /// Creates a new vault file in [directoryPath].
  ///
  /// The application-support fallback is retained only for callers that do
  /// not have a user-selected directory yet (and for legacy migration). New
  /// UI flows always pass an external directory so other applications can
  /// sync the file.
  Future<String> createVaultPath({String? name, String? directoryPath}) async {
    final directory = directoryPath == null
        ? await _vaultDirectory()
        : await Directory(directoryPath).create(recursive: true);
    final stem = _safeStem(fileName(name ?? 'MaidKit vault'));
    return '${directory.path}/$stem-${_uuid.v4()}$_extension';
  }

  /// Resolves a vault selected outside MaidKit without copying it.
  ///
  /// A selected vault remains in its original folder, which makes it
  /// available to file synchronization tools such as Syncthing or iCloud
  /// Drive. The caller is responsible for only opening trusted vault files.
  Future<String> importVault(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Vault file was not found.', sourcePath);
    }
    return source.absolute.path;
  }

  /// Moves a vault into a user-selected folder and returns its new path.
  ///
  /// Copying the SQLite sidecars before deleting the source keeps this
  /// operation valid across volumes. Callers should close the active database
  /// before invoking this method.
  Future<String> moveVault(
    String sourcePath, {
    required String directoryPath,
    String? name,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Vault file was not found.', sourcePath);
    }
    final target = await createVaultPath(
      name: name ?? fileName(sourcePath),
      directoryPath: directoryPath,
    );
    if (source.absolute.path == File(target).absolute.path) {
      return source.absolute.path;
    }
    final targetFile = File(target);
    await source.copy(targetFile.path);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${source.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy('${targetFile.path}$suffix');
      }
    }
    await source.delete();
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${source.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    return targetFile.absolute.path;
  }

  Future<void> deleteVault(String path) async {
    final file = File(path);
    if (!_isVaultFile(path) || !await file.exists()) {
      throw FileSystemException(
        'Only existing MaidKit vault files can be deleted.',
        path,
      );
    }
    await file.delete();
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$path$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  bool _isVaultFile(String path) {
    final lower = fileName(path).toLowerCase();
    return lower.endsWith('.maidkit') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.db');
  }

  Future<Directory> _vaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$_directoryName').create(recursive: true);
  }

  /// The final path segment, tolerating both '/' and '\' separators.
  ///
  /// Managed vault paths are built with '/' while path_provider and
  /// FilePicker may report native '\' paths on Windows, so splitting on
  /// [Platform.pathSeparator] alone would return the whole path there.
  String fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  /// Whether [path] points inside [directory], tolerant of '/' and '\'
  /// separators and of a trailing separator on [directory].
  bool isInDirectory(String path, String directory) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedDirectory = directory
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    return normalizedPath == normalizedDirectory ||
        normalizedPath.startsWith('$normalizedDirectory/');
  }

  String _safeStem(String value) {
    final withoutExtension = value.replaceFirst(RegExp(r'\.[^.]*$'), '');
    final sanitized = withoutExtension.replaceAll(
      RegExp(r'[^a-zA-Z0-9 _-]'),
      '_',
    );
    return sanitized.trim().isEmpty ? 'Vault' : sanitized.trim();
  }
}
