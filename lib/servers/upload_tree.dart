import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:maid_kit/shared/presentation/task_progress.dart';

import 'remote_file_system.dart';

/// Chunk size a dropped file's in-memory bytes are written in, matching what a
/// disk stream produces so both paths report progress at the same cadence.
const int kUploadChunkSize = 256 * 1024;

/// One local entry a drop uploads, described before the transfer is queued.
///
/// A file is either a [path] streamed from disk or a browser drop [source] that
/// carries bytes; a folder holds the children found under it.
class UploadNode {
  UploadNode.file({
    required this.name,
    required this.length,
    this.path,
    this.source,
  }) : isDirectory = false,
       children = const [];

  UploadNode.directory({required this.name, required this.children})
    : isDirectory = true,
      length = 0,
      path = null,
      source = null;

  final String name;
  final bool isDirectory;

  /// Byte length of a file; zero for a folder.
  final int length;

  /// Local path to stream, for a native drop.
  final String? path;

  /// The dropped item itself, whose bytes a browser hands over.
  final DropItem? source;

  final List<UploadNode> children;

  /// Size of the whole subtree, which is what the progress bar measures against.
  int get totalBytes => isDirectory
      ? children.fold(0, (sum, child) => sum + child.totalBytes)
      : length;
}

/// Describes a dropped entry as an upload tree.
///
/// A browser directory arrives with its children attached; every desktop
/// platform only hands over the top-level path, and only macOS says whether it
/// is a directory, so the tree under that path is walked here.
Future<UploadNode> describeDropItem(DropItem item) async {
  final isDirectory =
      item is DropItemDirectory ||
      (!kIsWeb && await FileSystemEntity.isDirectory(item.path));
  var name = item.name.isNotEmpty ? item.name : _fileNameOf(item.path);
  if (name.isEmpty) name = isDirectory ? 'folder' : 'upload.bin';
  if (!isDirectory) {
    final length = await item.length();
    return kIsWeb
        ? UploadNode.file(name: name, length: length, source: item)
        : UploadNode.file(name: name, length: length, path: item.path);
  }
  final children = <UploadNode>[];
  if (kIsWeb) {
    for (final child in (item as DropItemDirectory).children) {
      children.add(await describeDropItem(child));
    }
  } else {
    children.addAll(await describeLocalDirectory(item.path));
  }
  return UploadNode.directory(name: name, children: children);
}

/// Walks the local directory at [path] into upload nodes.
///
/// Symbolic links are skipped: a link can point outside the dropped folder or
/// back up its own tree, and following either would upload something the user
/// did not drop.
Future<List<UploadNode>> describeLocalDirectory(String path) async {
  final children = <UploadNode>[];
  await for (final entity in Directory(path).list(followLinks: false)) {
    final name = _fileNameOf(entity.path);
    if (entity is Directory) {
      children.add(
        UploadNode.directory(
          name: name,
          children: await describeLocalDirectory(entity.path),
        ),
      );
    } else if (entity is File) {
      children.add(
        UploadNode.file(
          name: name,
          length: await entity.length(),
          path: entity.path,
        ),
      );
    }
  }
  return children;
}

/// Writes [node] to [remotePath], creating a folder's remote tree as it goes.
///
/// [removeExisting] is called for each directory before it is created, so the
/// caller settles the destination conflict once per dropped entry and a folder
/// replaces whatever shared its name instead of merging into stale contents.
/// [onBytes] receives the size of every written chunk.
Future<void> uploadNode(
  RemoteFileClient files,
  UploadNode node,
  String remotePath, {
  required TaskControl? control,
  required void Function(int bytes) onBytes,
  required Future<void> Function(String path) removeExisting,
}) async {
  await control?.waitIfPaused();
  if (!node.isDirectory) {
    await _uploadFile(
      files,
      node,
      remotePath,
      control: control,
      onBytes: onBytes,
    );
    return;
  }
  await removeExisting(remotePath);
  await files.mkdir(remotePath);
  for (final child in node.children) {
    await uploadNode(
      files,
      child,
      joinRemotePath(remotePath, child.name),
      control: control,
      onBytes: onBytes,
      removeExisting: removeExisting,
    );
  }
}

/// Streams one file's bytes into [remotePath].
///
/// A native drop streams from disk so a large folder never has to fit in
/// memory; a browser drop only has the bytes the drop handed over.
Future<void> _uploadFile(
  RemoteFileClient files,
  UploadNode node,
  String remotePath, {
  required TaskControl? control,
  required void Function(int bytes) onBytes,
}) async {
  final remoteFile = await files.open(
    remotePath,
    mode:
        SftpFileOpenMode.write |
        SftpFileOpenMode.create |
        SftpFileOpenMode.truncate,
  );
  var offset = 0;
  Future<void> write(List<int> chunk) async {
    await control?.waitIfPaused();
    await remoteFile.writeBytes(chunk, offset: offset);
    offset += chunk.length;
    onBytes(chunk.length);
  }

  try {
    final path = node.path;
    if (path != null) {
      await for (final chunk in File(path).openRead()) {
        await write(chunk);
      }
    } else {
      final bytes = await node.source!.readAsBytes();
      for (var start = 0; start < bytes.length; start += kUploadChunkSize) {
        await write(
          bytes.sublist(
            start,
            math.min(start + kUploadChunkSize, bytes.length),
          ),
        );
      }
    }
  } finally {
    await remoteFile.close();
  }
}

String joinRemotePath(String directory, String name) =>
    directory == '/' ? '/$name' : '$directory/$name';

/// Last path segment of a local path, without pulling in the filesystem entity
/// types the callers do not otherwise use.
String _fileNameOf(String path) => Uri.file(
  path,
).pathSegments.lastWhere((segment) => segment.isNotEmpty, orElse: () => '');
