// Cross-repo integration: this client against a real MaidCafe daemon.
//
// Opt-in, because it needs a running daemon that this repository does not own.
// It skips unless both variables are set, so CI (which has neither) runs the
// fake-daemon test in maidcafe_file_system_test.dart instead; this one is what
// catches contract drift between the two repositories:
//
//   MAIDCAFE_SMOKE_URL=http://127.0.0.1:8747 \
//   MAIDCAFE_SMOKE_ROOT=/srv/app \
//   flutter test test/maidcafe_xrepo_integration_test.dart
//
// The root must be a directory the daemon serves (its `daemon.files.roots`),
// and the daemon's metrics secret must be `metrics-secret`. Lower
// `maxReadBytes` on the daemon to force the windowed read path to page.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_file_system.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

void main() {
  final base = Platform.environment['MAIDCAFE_SMOKE_URL'];
  if (base == null) {
    test('cross-repo integration', () {}, skip: 'MAIDCAFE_SMOKE_URL unset');
    return;
  }
  final root = Platform.environment['MAIDCAFE_SMOKE_ROOT']!;
  late MaidCafeRemoteFileClient client;

  setUpAll(() async {
    final session = await MaidCafeStreamSession.openAt(
      manager: SshConnectionManager(() => throw UnimplementedError()),
      baseUrl: base,
      apiSecret: 'metrics-secret',
    );
    client = MaidCafeRemoteFileClient(session);
  });

  setUp(() async {
    // Idempotent: a previous run's artifacts would otherwise make mkdir a
    // conflict rather than a test of creating something.
    for (final name in ['created', 'renamed.txt', 'copied.txt', 'big.bin']) {
      final target = '$root/$name';
      if (Directory(target).existsSync()) {
        Directory(target).deleteSync(recursive: true);
      } else if (File(target).existsSync()) {
        File(target).deleteSync();
      }
    }
  });

  test('browses real files, symlinks and directories', () async {
    expect(await client.absolute('.'), root);
    final entries = await client.listdir('.');
    final byName = {for (final e in entries) e.filename: e.attr};
    expect(byName.keys, containsAll(['greeting.txt', 'sub', 'link.txt']));
    expect(byName['sub']!.isDirectory, isTrue);
    expect(byName['greeting.txt']!.isFile, isTrue);
    expect(byName['greeting.txt']!.size, 22);
    expect(byName['link.txt']!.isSymbolicLink, isTrue);

    // A link described rather than followed, then followed.
    expect(
      (await client.stat('$root/link.txt', followLink: false)).isSymbolicLink,
      isTrue,
    );
    expect((await client.stat('$root/link.txt')).isFile, isTrue);
    expect((await client.stat('$root/sub')).isDirectory, isTrue);
  });

  test('reads and writes real bytes', () async {
    final handle = await client.open('$root/greeting.txt');
    expect(utf8.decode(await handle.readBytes()), 'hello from the daemon\n');
    await handle.close();

    final writer = await client.open(
      '$root/written.txt',
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    final payload = utf8.encode('written by MaidKit' * 100);
    await writer.writeBytes(payload.sublist(0, 1000), offset: 0);
    await writer.writeBytes(payload.sublist(1000), offset: 1000);
    await writer.close();
    expect(File('$root/written.txt').readAsStringSync(), utf8.decode(payload));
  });

  test('mutations land on disk', () async {
    await client.mkdir('$root/created');
    expect(Directory('$root/created').existsSync(), isTrue);

    await client.rename('$root/written.txt', '$root/renamed.txt');
    expect(File('$root/renamed.txt').existsSync(), isTrue);
    expect(File('$root/written.txt').existsSync(), isFalse);

    await client.copy('$root/renamed.txt', '$root/copied.txt');
    expect(File('$root/copied.txt').readAsStringSync(), isNotEmpty);

    await client.remove('$root/copied.txt');
    expect(File('$root/copied.txt').existsSync(), isFalse);
  });

  test('a windowed read pages a file larger than one window', () async {
    final big = List<int>.generate(3 * 1024 * 1024, (i) => i % 251);
    final writer = await client.open(
      '$root/big.bin',
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await writer.writeBytes(Uint8List.fromList(big), offset: 0);
    await writer.close();

    final reader = await client.open('$root/big.bin');
    var received = 0;
    await for (final chunk in reader.read()) {
      received += chunk.length;
    }
    await reader.close();
    expect(received, big.length);
    await client.remove('$root/big.bin');
  });
}
