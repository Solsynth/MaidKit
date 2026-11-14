import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/remote_file_system.dart';
import 'package:maid_kit/servers/upload_tree.dart';

/// Records what an upload writes, keyed by absolute remote path.
class _RecordingClient implements RemoteFileClient {
  final directories = <String>[];
  final files = <String, List<int>>{};

  @override
  Future<void> mkdir(String path) async {
    directories.add(path);
  }

  @override
  Future<RemoteFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    final bytes = <int>[];
    files[path] = bytes;
    return _RecordingFile(bytes);
  }

  @override
  Future<String> absolute(String path) async => path;

  @override
  Future<List<SftpName>> listdir(String path) async => const [];

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async =>
      SftpFileAttrs(mode: SftpFileMode.value(0));

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> rmdir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> abort() async {}
}

class _RecordingFile implements RemoteFile {
  _RecordingFile(this._bytes);

  final List<int> _bytes;
  var closed = false;

  @override
  Future<void> writeBytes(List<int> data, {int offset = 0}) async {
    expect(offset, _bytes.length, reason: 'writes stay sequential');
    _bytes.addAll(data);
  }

  @override
  Future<List<int>> readBytes() async => _bytes;

  @override
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  }) => Stream.value(_bytes);

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('upload-tree-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> writeLocal(String relative, List<int> bytes) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  test('walks a dropped folder into a tree with its total size', () async {
    await writeLocal('site/index.html', List.filled(10, 1));
    await writeLocal('site/assets/app.css', List.filled(30, 2));
    await writeLocal('site/assets/nested/deep.bin', List.filled(5, 3));

    final node = await describeLocalDirectory('${root.path}/site');

    expect(node.map((n) => n.isDirectory), [false, true]);
    final assets = node.firstWhere((n) => n.name == 'assets');
    expect(
      assets.children.map((n) => n.name),
      unorderedEquals(['app.css', 'nested']),
    );
    final total = node.fold<int>(0, (sum, n) => sum + n.totalBytes);
    expect(total, 45);
  });

  test('skips symbolic links instead of following them', () async {
    await writeLocal('tree/real.txt', [1, 2]);
    await Link(
      '${root.path}/tree/alias.txt',
    ).create('${root.path}/tree/real.txt');

    final node = await describeLocalDirectory('${root.path}/tree');

    expect(node.map((n) => n.name), ['real.txt']);
  });

  test('uploads a tree depth-first, replacing an existing directory', () async {
    await writeLocal('tree/a.txt', [1, 2, 3]);
    await writeLocal('tree/sub/b.txt', [4, 5]);
    final tree = UploadNode.directory(
      name: 'tree',
      children: await describeLocalDirectory('${root.path}/tree'),
    );
    final client = _RecordingClient();
    final removed = <String>[];
    var bytes = 0;

    await uploadNode(
      client,
      tree,
      '/remote/tree',
      control: null,
      onBytes: (count) => bytes += count,
      removeExisting: (path) async => removed.add(path),
    );

    expect(client.directories, ['/remote/tree', '/remote/tree/sub']);
    expect(removed, ['/remote/tree', '/remote/tree/sub']);
    expect(client.files['/remote/tree/a.txt'], [1, 2, 3]);
    expect(client.files['/remote/tree/sub/b.txt'], [4, 5]);
    expect(bytes, 5);
  });

  test('creates an empty folder without writing files', () async {
    final tree = UploadNode.directory(name: 'empty', children: const []);
    final client = _RecordingClient();

    await uploadNode(
      client,
      tree,
      '/remote/empty',
      control: null,
      onBytes: (_) {},
      removeExisting: (_) async {},
    );

    expect(client.directories, ['/remote/empty']);
    expect(client.files, isEmpty);
    expect(tree.totalBytes, 0);
  });
}
