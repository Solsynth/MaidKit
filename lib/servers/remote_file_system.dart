import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// The remote filesystem operations MaidKit's file surfaces need, independent
/// of the transport that provides them.
///
/// Two transports implement this: SFTP over an SSH session
/// ([SftpRemoteFileClient]) and the MaidCafe daemon's file API
/// (`MaidCafeRemoteFileClient`). The method names, parameters and model types
/// deliberately mirror `SftpClient` so the file manager, the editor and the
/// file picker are written once and work on either — a browser build has no
/// SSH, and a native build keeps using SFTP.
///
/// The model types are dartssh2's (`SftpName`, `SftpFileAttrs`,
/// `SftpFileOpenMode`). They are plain data classes, so constructing them from
/// the daemon's JSON is what lets both transports present identical listings to
/// the UI without a second set of widget-facing types.
abstract class RemoteFileClient {
  /// Resolves [path] to an absolute path. A relative path resolves against the
  /// session's starting directory: the SSH account's home for SFTP, the first
  /// configured root for the daemon API.
  Future<String> absolute(String path);

  /// Lists [path]. A directory is not listed recursively.
  Future<List<SftpName>> listdir(String path);

  /// Reads the attributes of [path]. With [followLink] false a symbolic link is
  /// described itself rather than resolved.
  Future<SftpFileAttrs> stat(String path, {bool followLink = true});

  /// Removes a file or a symbolic link.
  Future<void> remove(String path);

  /// Removes an empty directory.
  Future<void> rmdir(String path);

  /// Creates one directory.
  Future<void> mkdir(String path);

  /// Renames [oldPath] to [newPath] within the same filesystem.
  Future<void> rename(String oldPath, String newPath);

  /// Opens [path] for reading or writing.
  Future<RemoteFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  });

  /// Releases the transport. Idempotent.
  Future<void> close();
}

/// One open remote file.
///
/// The API is the subset of `SftpFile` the file surfaces use, so an open call
/// site reads the same on either transport.
abstract class RemoteFile {
  /// Reads the whole file. Bounded by the transport's own limits; the editor
  /// refuses a file over its editable size before calling this.
  Future<List<int>> readBytes();

  /// Streams the file in chunks, for transfers rather than whole-file reads.
  ///
  /// [length] bounds how much is read (the rest of the file when null), which
  /// is what a caller copying a known size passes; [offset] starts elsewhere
  /// than the beginning. The parameters mirror `SftpFile.read` so a call site
  /// reads identically on either transport.
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  });

  /// Writes [data] at [offset], which defaults to the start of the file.
  ///
  /// A transport that writes the whole file at once (the daemon API) accepts
  /// only a sequential offset — the current end of what has been written — so a
  /// caller streaming chunks passes the running byte count, exactly as it would
  /// to SFTP.
  Future<void> writeBytes(List<int> data, {int offset = 0});

  /// Writes everything buffered so far and releases the handle. A write handle
  /// that is never closed on a transport that buffers (the daemon API) has its
  /// content discarded, so callers must close in a `finally`.
  Future<void> close();
}

/// Whether a listing entry resolves to a directory.
bool isRemoteDirectoryEntry(SftpFileAttrs listed, {SftpFileAttrs? followed}) {
  return listed.isDirectory ||
      (listed.isSymbolicLink && followed?.isDirectory == true);
}

/// Whether a listing entry resolves to a regular file.
bool isRemoteFileEntry(SftpFileAttrs listed, {SftpFileAttrs? followed}) {
  return listed.isFile || (listed.isSymbolicLink && followed?.isFile == true);
}

/// [RemoteFileClient] over an SFTP session.
///
/// A thin delegation: the point is that the call sites above this file speak
/// [RemoteFileClient], not that SFTP behaves differently. Nothing here holds
/// state, so [close] delegates to the underlying client, which the connection
/// manager owns (closing it twice is already safe there).
class SftpRemoteFileClient implements RemoteFileClient {
  SftpRemoteFileClient(this._sftp, {this.startDirectory = '.'});

  final SftpClient _sftp;

  /// The directory a relative path resolves against. SFTP resolves `.` itself,
  /// server-side, so the default performs no work.
  final String startDirectory;

  @override
  Future<String> absolute(String path) => _sftp.absolute(path);

  @override
  Future<List<SftpName>> listdir(String path) => _sftp.listdir(path);

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) =>
      _sftp.stat(path, followLink: followLink);

  @override
  Future<void> remove(String path) => _sftp.remove(path);

  @override
  Future<void> rmdir(String path) => _sftp.rmdir(path);

  @override
  Future<void> mkdir(String path) => _sftp.mkdir(path);

  @override
  Future<void> rename(String oldPath, String newPath) =>
      _sftp.rename(oldPath, newPath);

  @override
  Future<RemoteFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    final file = await _sftp.open(path, mode: mode);
    return _SftpRemoteFile(file, writable: _isWritable(mode));
  }

  @override
  Future<void> close() => _sftp.close();
}

/// Whether [mode] opens the file for writing, which decides whether [RemoteFile]
/// exposes the streaming write path.
bool _isWritable(SftpFileOpenMode mode) =>
    (mode.flag & SftpFileOpenMode.write.flag) != 0 ||
    (mode.flag & SftpFileOpenMode.append.flag) != 0;

class _SftpRemoteFile implements RemoteFile {
  _SftpRemoteFile(this._file, {required this.writable});

  final SftpFile _file;
  final bool writable;

  @override
  Future<List<int>> readBytes() => _file.readBytes();

  @override
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  }) => _file.read(
    length: length,
    offset: offset,
    onProgress: onProgress,
    chunkSize: chunkSize,
    maxPendingRequests: maxPendingRequests,
  );

  @override
  Future<void> writeBytes(List<int> data, {int offset = 0}) =>
      _file.writeBytes(
        data is Uint8List ? data : Uint8List.fromList(data),
        offset: offset,
      );

  @override
  Future<void> close() => _file.close();
}
