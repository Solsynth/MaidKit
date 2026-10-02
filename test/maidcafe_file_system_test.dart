import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_file_system.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

/// A stand-in for the daemon's file API: it records every request and answers
/// with the JSON shapes the Go daemon produces, so the client's URLs, headers,
/// body signature and JSON mapping are all exercised for real over HTTP.
class _FakeDaemon {
  _FakeDaemon({this.roots = const ['/srv/app']});

  final List<String> roots;
  HttpServer? _server;
  final requests = <_RecordedRequest>[];

  /// Entries the next listing returns, keyed by requested path.
  Map<String, List<Map<String, Object?>>> listings = {};
  Map<String, Map<String, Object?>> stats = {};

  /// The next content window: (offset, limit) → bytes.
  Uint8List Function(String path, int offset, int limit)? content;

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  List<String> get paths => [for (final r in requests) '${r.method} ${r.path}'];

  void _handle(HttpRequest request) async {
    final body = await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    requests.add(
      _RecordedRequest(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        headers: {
          for (final name in ['authorization', 'x-maidcafe-signature'])
            if (request.headers.value(name) != null)
              name: request.headers.value(name)!,
        },
        body: body,
      ),
    );
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    switch ('${request.method} $path') {
      case 'GET /health':
        _json(request, {'ok': true, 'mode': 'daemon', 'id': 'host-1'});
      case 'GET /api/v1/files/roots':
        _json(request, {
          'roots': [
            for (final root in roots)
              {'path': root, 'privileged': false},
          ],
          'writable': true,
        });
      case 'GET /api/v1/files/list':
        final requested = query['path'] ?? '';
        final entries = listings[requested];
        if (entries == null) {
          _error(request, 404, 'no such file or directory');
          return;
        }
        _json(request, {'path': requested, 'entries': entries});
      case 'GET /api/v1/files/stat':
        final entry = stats[query['path'] ?? ''];
        if (entry == null) {
          _error(request, 404, 'no such file or directory');
          return;
        }
        _json(request, entry);
      case 'GET /api/v1/files/content':
        final bytes =
            content?.call(
              query['path'] ?? '',
              int.parse(query['offset'] ?? '0'),
              int.parse(query['limit'] ?? '0'),
            ) ??
            Uint8List(0);
        request.response.headers.contentType = ContentType.binary;
        request.response.add(bytes);
        request.response.close();
      case 'PUT /api/v1/files/content':
        _json(request, {'path': query['path'], 'size': body.length});
      case 'POST /api/v1/files/mkdir':
      case 'POST /api/v1/files/move':
      case 'POST /api/v1/files/copy':
      case 'POST /api/v1/files/delete':
        _json(request, {'path': query['path'] ?? ''});
      default:
        _error(request, 404, 'unknown route');
    }
  }

  void _json(HttpRequest request, Object payload) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    request.response.close();
  }

  void _error(HttpRequest request, int status, String message) {
    request.response.statusCode = status;
    _json(request, {'ok': false, 'error': message});
  }
}

class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;
  final List<int> body;

  Map<String, Object?> get json =>
      jsonDecode(utf8.decode(body)) as Map<String, Object?>;
}

/// One directory entry as the Go daemon serializes it.
Map<String, Object?> _entry(
  String path,
  String name,
  String type, {
  int size = 0,
  int mode = 420, // 0644
  String? linkTarget,
  String? targetType,
}) => {
  'name': name,
  'path': '$path/$name',
  'type': type,
  'size': size,
  'mode': mode,
  'modified_at': '2026-08-15T12:00:00Z',
  'link_target': ?linkTarget,
  'target_type': ?targetType,
};

void main() {
  late _FakeDaemon daemon;
  late MaidCafeStreamSession session;
  late MaidCafeRemoteFileClient client;
  const secret = 'metrics-secret';

  setUp(() async {
    daemon = _FakeDaemon();
    await daemon.start();
    session = await MaidCafeStreamSession.openAt(
      manager: SshConnectionManager(() => throw UnimplementedError()),
      baseUrl: daemon.baseUrl,
      apiSecret: secret,
    );
    client = MaidCafeRemoteFileClient(session);
  });

  tearDown(() async => daemon.stop());

  test('a relative path resolves to the first configured root', () async {
    expect(await client.absolute('.'), '/srv/app');
    expect(await client.absolute('logs/./today'), '/srv/app/logs/today');
    expect(await client.absolute('/srv/app/../other'), '/srv/other');
    expect(await client.absolute('/absolute/path'), '/absolute/path');
  });

  test('listing maps the daemon kinds onto SFTP attributes', () async {
    daemon.listings['/srv/app'] = [
      _entry('/srv/app', 'conf', 'directory', mode: 493), // 0755
      _entry('/srv/app', 'index.html', 'file', size: 512, mode: 420),
      _entry(
        '/srv/app',
        'current',
        'symlink',
        mode: 511,
        linkTarget: 'releases/v2',
        targetType: 'directory',
      ),
    ];

    final entries = await client.listdir('.');
    expect(entries.map((e) => e.filename), ['conf', 'index.html', 'current']);

    // The three predicates the whole file UI branches on must be right, which
    // is what makes reconstructing SFTP's type bits worth doing.
    final conf = entries[0].attr;
    expect(conf.isDirectory, isTrue);
    expect(conf.isFile, isFalse);
    expect(conf.size, 0);

    final file = entries[1].attr;
    expect(file.isFile, isTrue);
    expect(file.isDirectory, isFalse);
    expect(file.size, 512);
    expect(file.mode!.value & 0x1FF, 0x1A4); // permissions preserved
    expect(
      file.modifyTime,
      DateTime.utc(2026, 8, 15, 12).millisecondsSinceEpoch ~/ 1000,
    );

    final link = entries[2].attr;
    expect(link.isSymbolicLink, isTrue);
    expect(link.isDirectory, isFalse);

    // The request carried the absolute path and the credential.
    expect(daemon.paths, contains('GET /api/v1/files/list'));
    final request = daemon.requests.last;
    expect(request.query['path'], '/srv/app');
    expect(request.headers['authorization'], 'Bearer $secret');
  });

  test('stat follows a link by default and describes it when asked', () async {
    daemon.stats['/srv/app/current'] = _entry(
      '/srv/app',
      'current',
      'symlink',
      linkTarget: 'releases/v2',
      targetType: 'directory',
    );
    daemon.stats['/srv/app/index.html'] = _entry(
      '/srv/app',
      'index.html',
      'file',
      size: 512,
    );

    final followed = await client.stat('/srv/app/index.html');
    expect(followed.isFile, isTrue);
    expect(daemon.requests.last.query['follow'], 'true');

    // A link described rather than resolved: what a client needs before it
    // deletes or retargets one.
    final link = await client.stat('/srv/app/current', followLink: false);
    expect(link.isSymbolicLink, isTrue);
    expect(daemon.requests.last.query['follow'], 'false');
  });

  test('a missing path surfaces the daemon error', () async {
    await expectLater(
      client.stat('/srv/app/absent'),
      throwsA(isA<StateError>()),
    );
  });

  test('reads page the content route and stop at the file end', () async {
    daemon.stats['/srv/app/big.bin'] = _entry(
      '/srv/app',
      'big.bin',
      'file',
      size: 10,
    );
    daemon.content = (path, offset, limit) {
      const all = '0123456789';
      if (offset >= all.length) return Uint8List(0);
      final end = (offset + (limit == 0 ? all.length : limit)).clamp(
        0,
        all.length,
      );
      return Uint8List.fromList(utf8.encode(all.substring(offset, end)));
    };

    final handle = await client.open('/srv/app/big.bin');
    expect(utf8.decode(await handle.readBytes()), '0123456789');
    // The handle asked for windows, and the last one came back short.
    expect(daemon.requests.where((r) => r.path == '/api/v1/files/content'), isNotEmpty);
    await handle.close();
  });

  test('a write buffers and lands as one whole-file request', () async {
    final handle = await client.open(
      '.',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    // The file manager tracks the running offset and passes it, which is what
    // makes a sequence of chunk writes meaningful on a whole-file transport.
    await handle.writeBytes(utf8.encode('first '), offset: 0);
    await handle.writeBytes(utf8.encode('second'), offset: 6);
    // Nothing is sent until the handle closes, because the daemon's write
    // replaces the whole file.
    expect(
      daemon.requests.where((r) => r.method == 'PUT'),
      isEmpty,
    );
    await handle.close();

    final put = daemon.requests.last;
    expect(put.method, 'PUT');
    expect(put.path, '/api/v1/files/content');
    expect(put.query['path'], '/srv/app');
    expect(utf8.decode(put.body), 'first second');
    expect(put.headers['authorization'], 'Bearer $secret');
  });

  test('an out-of-order write is refused rather than corrupting the file', () async {
    final handle = await client.open(
      '.',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    await handle.writeBytes(utf8.encode('abc'));
    // The daemon replaces a file, so a mid-file write cannot be expressed.
    await expectLater(
      handle.writeBytes(utf8.encode('xyz'), offset: 99),
      throwsA(isA<RemoteFileSystemException>()),
    );
    await handle.close();
  });

  test('mutations carry a signature over the body they send', () async {
    await client.mkdir('/srv/app/new');
    await client.rename('/srv/app/a', '/srv/app/b');
    await client.copy('/srv/app/a', '/srv/app/c', overwrite: true);
    await client.remove('/srv/app/a');

    final byPath = <String, _RecordedRequest>{
      for (final request in daemon.requests.where((r) => r.body.isNotEmpty))
        request.path: request,
    };
    expect(byPath.keys, containsAll(['/api/v1/files/mkdir']));

    for (final request in daemon.requests.where((r) => r.method == 'POST')) {
      final signature = request.headers['x-maidcafe-signature'];
      expect(
        signature,
        isNotNull,
        reason: '${request.path} must be signed',
      );
      // The signature must be the HMAC of exactly the bytes sent, which is what
      // makes a credential lifted in transit unusable against another body.
      expect(
        signature,
        await maidCafeHmacSignature(secret, request.body),
        reason: '${request.path} signature does not match its body',
      );
    }

    final mkdir = daemon.requests.firstWhere(
      (r) => r.path == '/api/v1/files/mkdir',
    );
    expect(mkdir.json['path'], '/srv/app/new');

    final move = daemon.requests.firstWhere(
      (r) => r.path == '/api/v1/files/move',
    );
    expect(move.json['from'], '/srv/app/a');
    expect(move.json['to'], '/srv/app/b');

    final copy = daemon.requests.firstWhere(
      (r) => r.path == '/api/v1/files/copy',
    );
    expect(copy.json['overwrite'], isTrue);

    final delete = daemon.requests.firstWhere(
      (r) => r.path == '/api/v1/files/delete',
    );
    expect(delete.json['path'], '/srv/app/a');
  });

  test('a session with no file roots reports it instead of browsing', () async {
    final bare = _FakeDaemon(roots: const []);
    await bare.start();
    final bareSession = await MaidCafeStreamSession.openAt(
      manager: SshConnectionManager(() => throw UnimplementedError()),
      baseUrl: bare.baseUrl,
      apiSecret: secret,
    );
    await expectLater(
      MaidCafeRemoteFileClient(bareSession).listdir('.'),
      throwsA(isA<RemoteFileSystemException>()),
    );
    await bare.stop();
  });
}
