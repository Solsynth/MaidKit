// Route selection for daemon data: a configured endpoint is what gets dialed,
// and no SSH port forward is opened for it. Both a live row and the snapshot a
// tab was opened with are covered — the second is what used to keep dialing the
// forward after an endpoint was saved.
//
// The HTTP layer is faked (any request answers the daemon's `/health`), so the
// tests never touch the network, and the SSH manager refuses both a port
// forward and every SSH command: a route that fell back to SSH cannot pass.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_repository.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/vault_service.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

/// Refuses every SSH route: if a port forward is opened, the test fails.
class _NoSshManager extends SshConnectionManager {
  _NoSshManager() : super(() => throw StateError('no ssh in this test'));
  var forwards = 0;

  @override
  SSHClient? clientFor(int serverId) => _FakeClient();

  @override
  Future<ActivePortForward> startPortForward({
    required Server server,
    required PortForwardDirection direction,
    required PortForwardKind kind,
    required String bindHost,
    required int bindPort,
    String targetHost = '',
    int targetPort = 0,
    PortForwardOwner owner = PortForwardOwner.user,
  }) async {
    forwards++;
    throw StateError('a port forward was opened');
  }

  @override
  Future<T> withClient<T>(
    int serverId,
    Future<T> Function(SSHClient client) run,
  ) async => throw StateError('an SSH command was run');
}

class _FakeClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no ssh in this test');
}

/// Answers every request with the daemon's `/health` payload.
class _FakeHttpOverrides extends HttpOverrides {
  final List<Uri> urls = [];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(urls);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.urls);
  final List<Uri> urls;
  @override
  Duration idleTimeout = Duration.zero;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    urls.add(url);
    return _FakeRequest();
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> values = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      values.putIfAbsent(name.toLowerCase(), () => []).add('$value');
  @override
  List<String>? operator [](String name) => values[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  final _headers = _FakeHeaders();
  @override
  HttpHeaders get headers => _headers;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  Future<HttpClientResponse> close() async => _FakeResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse implements HttpClientResponse {
  static final _body = Uint8List.fromList(utf8.encode('{"version":"1.2.3"}'));
  final _headers = _FakeHeaders()
    ..values['content-type'] = ['application/json'];
  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  HttpHeaders get headers => _headers;
  @override
  int get contentLength => _body.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  Stream<R> cast<R>() => Stream.value(_body).cast<R>();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
}

void main() {
  _mockPathProvider();
  late HttpOverrides? previous;

  setUp(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _FakeHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = previous);

  const server = Server(
    id: 1,
    name: 'proxied',
    host: '10.0.0.9',
    port: 22,
    username: 'root',
    collectStats: true,
    collectSystemInfo: true,
    connectionType: 'ssh',
    maidCafeTerminalUrl: 'https://daemon.example',
    maidCafeTerminalViaCloud: false,
  );

  test('a stored endpoint is dialed and no port forward is opened', () async {
    final manager = _NoSshManager();
    final session = await MaidCafeStreamSession.open(
      manager: manager,
      server: server,
      apiSecret: 'secret',
    );
    expect(session.version, '1.2.3');
    expect(manager.forwards, 0);
    final urls = (HttpOverrides.current as _FakeHttpOverrides).urls;
    expect(urls.single.toString(), 'https://daemon.example/health');
    await session.close();
  });

  test('a stale snapshot still routes on the stored endpoint', () async {
    final directory = Directory.systemTemp.createTempSync('route-smoke');
    addTearDown(() => directory.deleteSync(recursive: true));
    final database = AppDatabase(filePath: '${directory.path}/test.sqlite');
    addTearDown(database.close);
    final vault = VaultService(database, secureStorage: _MemoryStorage());
    await vault.create('password');
    final repository = ServerRepository(database, vault);
    final stored = await repository.create(
      ServerDraft(
        name: 'proxied',
        host: '10.0.0.9',
        port: 22,
        username: 'root',
        credential: const ServerCredential.password('test-password'),
      ),
    );
    await repository.setMaidCafeEndpointOverride(
      stored,
      'https://daemon.example',
    );
    await repository.setMaidCafeMetricsSecret(stored, 'secret');
    final row = (await repository.all()).single;

    // The snapshot a tab was opened with: no endpoint.
    final stale = Server(
      id: row.id,
      name: row.name,
      host: row.host,
      port: row.port,
      username: row.username,
      collectStats: true,
      collectSystemInfo: true,
      connectionType: 'ssh',
      maidCafeTerminalViaCloud: false,
    );
    expect(stale.maidCafeEndpointOverride, isNull);

    final manager = _NoSshManager();
    final registry = MaidCafeSessionRegistry(
      manager: manager,
      serverRepository: repository,
    );
    registry.retain(stale);
    final session = await registry.sessionFor(stale);
    addTearDown(() => session?.close());
    expect(session, isNotNull);
    expect(manager.forwards, 0);
    expect(
      (HttpOverrides.current as _FakeHttpOverrides).urls.single.toString(),
      'https://daemon.example/health',
    );
    registry.close();
  });
}
