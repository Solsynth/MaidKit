import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'maidcafe_stream.dart';
import 'remote_file_system.dart';

/// [RemoteFileClient] over the MaidCafe daemon's file API.
///
/// This is what makes file management work in a browser build: it speaks HTTP
/// to a daemon endpoint instead of opening an SFTP channel, which a browser
/// cannot do. The daemon serves the same operations (list, stat, read, write,
/// mkdir, move, copy, delete) confined to the roots an operator declared in
/// `daemon.files.roots`, which is also why the daemon is the side that decides
/// whether a path is legal.
///
/// Two consequences of that confinement shape this class, and both are surfaced
/// rather than hidden:
///
/// * Paths must be absolute and inside a root. The file manager starts from the
///   relative `.`, so [absolute] resolves it to the first configured root — for
///   the UI that root is "home", the way the SSH account's home is over SFTP.
/// * The daemon's own operations are not identical to SFTP's: it has no
///   distinct remove/rmdir (one delete), it refuses a recursive delete, and it
///   refuses move/copy inside a privileged root. Where SFTP would do something
///   the daemon cannot, this client forwards the daemon's refusal as a
///   [RemoteFileSystemException] instead of silently degrading.
class MaidCafeRemoteFileClient implements RemoteFileClient {
  MaidCafeRemoteFileClient(this._session, {this.onClose});

  final MaidCafeStreamSession _session;

  /// Runs once when [close] releases the client: the resolver's matching
  /// release of the shared session reference. The session itself is shared
  /// with the metrics, log and container tabs, so this client never closes it.
  final void Function()? onClose;

  /// The root a relative path resolves against, resolved once from the daemon.
  String? _base;
  bool _closed = false;

  /// The daemon's configured roots, in the order it reports them.
  Future<List<String>> roots() async {
    final result = await _session.fileRoots();
    final raw = result['roots'];
    if (raw is! List) return const [];
    return <String>[
      for (final entry in raw)
        if (entry is Map && entry['path'] is String) entry['path'] as String,
    ];
  }

  @override
  Future<String> absolute(String path) async {
    _throwIfClosed();
    final base = await _basePath();
    final normalized = _normalize(path, base);
    return normalized;
  }

  /// Resolves a possibly relative path against the session base, lexically.
  ///
  /// The result is only a string: the daemon re-validates every path against
  /// its roots, so this exists to give the UI a stable absolute path, not to
  /// decide what is reachable.
  static String _normalize(String path, String base) {
    if (path.startsWith('/')) return _clean(path);
    if (path == '.' || path.isEmpty) return base;
    return _clean('$base/$path');
  }

  /// Collapses `.` and `..` segments and duplicate slashes.
  static String _clean(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isEmpty) continue;
        segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  Future<String> _basePath() async {
    final cached = _base;
    if (cached != null) return cached;
    final configured = await roots();
    if (configured.isEmpty) {
      throw const RemoteFileSystemException(
        'This MaidCafe daemon serves no file roots. Enable daemon.files with '
        'at least one root to browse files without SSH.',
      );
    }
    // The first root is the base, so `.` behaves like a home directory. A
    // client that wants a specific root opens it by absolute path.
    return _base = configured.first;
  }

  @override
  Future<List<SftpName>> listdir(String path) async {
    _throwIfClosed();
    final target = await absolute(path);
    final result = await _session.fileList(target);
    final raw = result['entries'];
    if (raw is! List) return const [];
    final entries = <SftpName>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      entries.add(_nameFromJson(entry));
    }
    return entries;
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    _throwIfClosed();
    final result = await _session.fileStat(
      await absolute(path),
      follow: followLink,
    );
    return _attrsFromJson(result);
  }

  @override
  Future<void> remove(String path) async {
    _throwIfClosed();
    // The daemon deletes files and links with one operation, and answers a
    // directory with a conflict rather than removing it.
    await _session.fileDelete(await absolute(path));
  }

  @override
  Future<void> rmdir(String path) async {
    _throwIfClosed();
    // The daemon refuses to remove a directory at all: a recursive delete is
    // not something a root's profile authorizes, and removing an empty
    // directory needs the same primitive. Report its refusal verbatim.
    await _session.fileDelete(await absolute(path));
  }

  @override
  Future<void> mkdir(String path) async {
    _throwIfClosed();
    await _session.fileMkdir(await absolute(path));
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _throwIfClosed();
    await _session.fileMove(
      await absolute(oldPath),
      await _normalizeFromBase(newPath),
    );
  }

  /// Copies a file or tree, which the file manager offers alongside move. The
  /// daemon implements it, so it is served rather than emulated.
  Future<void> copy(
    String source,
    String destination, {
    bool overwrite = false,
  }) async {
    _throwIfClosed();
    await _session.fileCopy(
      await absolute(source),
      await _normalizeFromBase(destination),
      overwrite: overwrite,
    );
  }

  /// Normalizes [path] against the base without the closed check, for use from
  /// methods that already performed it.
  Future<String> _normalizeFromBase(String path) async =>
      _normalize(path, await _basePath());

  @override
  Future<RemoteFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    _throwIfClosed();
    final target = await absolute(path);
    final writable =
        (mode.flag & SftpFileOpenMode.write.flag) != 0 ||
        (mode.flag & SftpFileOpenMode.append.flag) != 0;
    if (!writable) return _MaidCafeReadFile(_session, target);
    return _MaidCafeWriteFile(_session, target);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onClose?.call();
  }

  void _throwIfClosed() {
    if (_closed) {
      throw const RemoteFileSystemException(
        'This file session was released. Reopen the file browser.',
      );
    }
  }

  /// Builds a listing entry from the daemon's JSON.
  static SftpName _nameFromJson(Map<dynamic, dynamic> entry) {
    final path = entry['path']?.toString() ?? '';
    final name = entry['name']?.toString() ?? _basename(path);
    return SftpName(
      filename: name,
      longname: name,
      attr: _attrsFromJson(entry),
    );
  }

  /// Builds attributes from the daemon's JSON.
  ///
  /// The daemon reports the permission bits separately from the entry kind, so
  /// the type bits SFTP carries in the same value are reconstructed here —
  /// that is what makes `isDirectory`, `isFile` and `isSymbolicLink` answer
  /// correctly for the widgets above.
  static SftpFileAttrs _attrsFromJson(Map<dynamic, dynamic> json) {
    final permissions = json['mode'] is num ? (json['mode'] as num).toInt() : 0;
    final type = json['type']?.toString() ?? 'file';
    var mode = permissions & 0xFFF;
    switch (type) {
      case 'directory':
        mode |= _SftpTypeBits.directory;
      case 'symlink':
        mode |= _SftpTypeBits.symbolicLink;
      case 'other':
        // Neither a regular file nor a directory nor a link: leave the type
        // bits clear so it is reported as an unknown kind rather than a file.
        mode |= _SftpTypeBits.unknown;
      default:
        mode |= _SftpTypeBits.regularFile;
    }
    final modified = DateTime.tryParse(json['modified_at']?.toString() ?? '');
    return SftpFileAttrs(
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
      mode: SftpFileMode.value(mode),
      modifyTime: modified == null
          ? null
          : modified.millisecondsSinceEpoch ~/ 1000,
    );
  }

  static String _basename(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }
}

/// SFTP mode type bits, reconstructed for entries the daemon describes with a
/// separate kind field.
abstract final class _SftpTypeBits {
  /// 0040000
  static const directory = 1 << 14;

  /// 0100000
  static const regularFile = 1 << 15;

  /// 0120000
  static const symbolicLink = (1 << 15) + (1 << 13);

  /// 0140000 (socket), used here as "some other kind", which is what the
  /// daemon's `other` means. SFTP reports sockets, devices and pipes distinctly;
  /// no listed type matches the daemon's catch-all exactly, and treating it as
  /// a socket would be a lie — this value exists only so the entry is neither a
  /// directory nor a regular file, which is what the UI checks.
  static const unknown = (1 << 15) + (1 << 14);
}

/// Read handle over the daemon's windowed content route.
///
/// The daemon serves a window rather than a whole-file stream, and refuses a
/// whole-file read past `maxReadBytes`. This handle pages the file transparently
/// so a download or a copy of a large file still works, and it reports a read
/// past the end as the end of the stream rather than an error.
class _MaidCafeReadFile implements RemoteFile {
  _MaidCafeReadFile(this._session, this._path);

  final MaidCafeStreamSession _session;
  final String _path;
  bool _closed = false;

  @override
  Future<List<int>> readBytes() async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in read()) {
      buffer.add(chunk);
    }
    return buffer.takeBytes();
  }

  @override
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  }) async* {
    // Windows are fetched one at a time: the daemon caps how much one request
    // may carry, so the page size is whatever it accepts, and parallelism would
    // only add sockets without making the transfer faster than the daemon can
    // read from disk.
    final window = chunkSize <= 0 ? _defaultWindow : chunkSize;
    var cursor = offset;
    var remaining = length ?? -1;
    var size = await _size();
    while (cursor < size && remaining != 0) {
      final want = remaining > 0 && remaining < window ? remaining : window;
      final bytes = await _session.fileReadWindow(
        _path,
        offset: cursor,
        limit: want,
      );
      if (bytes.isEmpty) return;
      yield bytes;
      onProgress?.call(bytes.length);
      cursor += bytes.length;
      if (remaining > 0) remaining -= bytes.length;
      // The file may have grown or shrunk while it was being read; a window
      // that came back short is the end as far as this handle is concerned.
      if (bytes.length < want) return;
      if (cursor >= size) {
        size = await _size();
      }
    }
  }

  Future<int> _size() async {
    final attrs = await _session.fileStat(_path);
    final value = attrs['size'];
    return value is num ? value.toInt() : 0;
  }

  @override
  Future<void> writeBytes(List<int> data, {int offset = 0}) {
    throw const RemoteFileSystemException(
      'This handle was opened for reading.',
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  /// One window. Sized to the default read cap the daemon ships with, so a
  /// whole-file read is one request on an ordinary file and pages only when the
  /// operator lowered the cap — which the handle tolerates either way.
  static const _defaultWindow = 8 * 1024 * 1024;

  /// Whether [closed]; kept so the class documents that a read handle needs no
  /// cleanup on a transport with no server-side session per file.
  bool get isClosed => _closed;
}

/// Write handle that buffers in memory and writes once on [close].
///
/// A deliberate trade: the daemon has no partial-write API, so a streaming
/// upload would either be a sequence of truncating writes or a bespoke
/// protocol. Buffering keeps the semantics of `SftpFile` (writes accumulate
/// until the handle closes) and bounds the damage a half-written file could do
/// — the daemon's own write is atomic, so a reader never sees a partial file.
///
/// The cost is memory for the file being written, bounded by
/// [maxBufferedBytes]: past that the handle refuses rather than growing without
/// limit, which is the honest answer for a daemon whose write cap an operator
/// configured.
class _MaidCafeWriteFile implements RemoteFile {
  _MaidCafeWriteFile(this._session, this._path);

  final MaidCafeStreamSession _session;
  final String _path;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _closed = false;

  /// Bounds one upload. The daemon's own `maxWriteBytes` default is 8 MiB and
  /// this matches it, so a file the daemon would accept is one this can send.
  static const maxBufferedBytes = 8 * 1024 * 1024;

  @override
  Future<List<int>> readBytes() {
    throw const RemoteFileSystemException(
      'This handle was opened for writing.',
    );
  }

  @override
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  }) {
    throw const RemoteFileSystemException(
      'This handle was opened for writing.',
    );
  }

  @override
  Future<void> writeBytes(List<int> data, {int offset = 0}) async {
    if (_closed) {
      throw const RemoteFileSystemException('This file handle is closed.');
    }
    if (offset != _buffer.length) {
      // SFTP can write at an arbitrary offset; the daemon's write replaces the
      // whole file. Rewriting the head on every chunk would truncate, so out-of
      // -order writes are refused instead of silently producing a corrupt file.
      throw RemoteFileSystemException(
        'This daemon writes whole files; it cannot write at offset $offset.',
      );
    }
    if (_buffer.length + data.length > maxBufferedBytes) {
      throw RemoteFileSystemException(
        'This file is larger than ${maxBufferedBytes ~/ (1024 * 1024)} MiB, '
        'which the daemon file API writes in one request.',
      );
    }
    _buffer.add(data);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _session.fileWriteRaw(_path, _buffer.takeBytes());
  }
}

/// A refusal or a transport failure from a remote filesystem, with the message
/// the transport produced. Separate from [StateError] so a caller can tell
/// "this transport does not do that" from "the operation failed".
class RemoteFileSystemException implements Exception {
  const RemoteFileSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}
