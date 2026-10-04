import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_terminal_connection_manager.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

void main() {
  test('the refusal is mapped to the policy that produced it', () {
    MaidCafeTerminalHandshakeFailure map(int status, Object? body) =>
        maidCafeHandshakeFailureFrom(status, body);

    // The daemon answers each pre-upgrade check with its own status and JSON.
    expect(
      map(403, {'error': 'terminal disabled'}),
      MaidCafeTerminalHandshakeFailure.disabled,
    );
    expect(
      map(403, {'error': 'terminal remote access is disabled'}),
      MaidCafeTerminalHandshakeFailure.remote,
    );
    expect(
      map(403, {'error': 'terminal user not allowed'}),
      MaidCafeTerminalHandshakeFailure.user,
    );
    expect(
      map(401, {'error': 'unauthorized'}),
      MaidCafeTerminalHandshakeFailure.credential,
    );
    expect(
      map(501, {'error': 'terminal unsupported on this platform'}),
      MaidCafeTerminalHandshakeFailure.unsupported,
    );
    expect(
      map(429, {'error': 'too many terminal sessions'}),
      MaidCafeTerminalHandshakeFailure.busy,
    );
    // A rejected Origin is written by the WebSocket library: 403, no body.
    expect(map(403, ''), MaidCafeTerminalHandshakeFailure.origin);
    expect(map(200, {'ok': true}), MaidCafeTerminalHandshakeFailure.unknown);
  });

  test('endpoint keeps the scheme security and any base path', () {
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'https://host.tailnet.ts.net',
        secret: 's',
      ).endpoint.toString(),
      'wss://host.tailnet.ts.net/api/v1/terminal',
    );
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'http://127.0.0.1:8747/',
        secret: 's',
      ).endpoint.toString(),
      'ws://127.0.0.1:8747/api/v1/terminal',
    );
    // A path-prefixed reverse proxy keeps its prefix.
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'https://host/maidcafe',
        secret: 's',
      ).endpoint.toString(),
      'wss://host/maidcafe/api/v1/terminal',
    );
  });

  test('a session endpoint carries the geometry and the run-as account', () {
    const target = MaidCafeTerminalTarget(
      baseUrl: 'https://host',
      secret: 's',
      user: 'deploy',
    );
    expect(
      target.sessionEndpoint(columns: 120, rows: 36).toString(),
      'wss://host/api/v1/terminal?cols=120&rows=36&user=deploy',
    );
    // No account selected: the daemon reads an absent `user` as its own.
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'https://host',
        secret: 's',
      ).sessionEndpoint(columns: 120, rows: 36).toString(),
      'wss://host/api/v1/terminal?cols=120&rows=36',
    );
    // Blank is the same as absent, not an account named "".
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'https://host',
        secret: 's',
        user: '   ',
      ).sessionEndpoint(columns: 120, rows: 36).toString(),
      'wss://host/api/v1/terminal?cols=120&rows=36',
    );
    // A relayed session takes them in the ticket body, not on the socket.
    expect(
      const MaidCafeTerminalTarget(
        baseUrl: 'https://mkc.solsynth.dev',
        secret: '',
        user: 'deploy',
        relayDaemonId: 'daemon-1',
      ).sessionEndpoint(columns: 120, rows: 36).toString(),
      'wss://mkc.solsynth.dev/api/daemons/daemon-1/terminal',
    );
  });

  test('credential token is unpadded base64url of the secret', () {
    expect(
      maidCafeTerminalToken('metrics-secret'),
      'maidcafe.terminal.bWV0cmljcy1zZWNyZXQ',
    );
    // 7 bytes encode with padding, which a subprotocol token cannot carry.
    expect(maidCafeTerminalToken('s3cret!'), 'maidcafe.terminal.czNjcmV0IQ');
  });

  test('cloud-relayed target mints a ticket and offers its token', () async {
    final offered = <String?>[];
    final paths = <String>[];
    final daemon = await _FakeDaemon.start((socket, request) {
      offered.add(request.headers.value('sec-websocket-protocol'));
      paths.add(request.uri.path);
      socket.add(
        jsonEncode({
          'type': 'hello',
          'version': 'v1',
          'session': 'session-1',
          'shell': '/bin/sh',
          'user': 'deploy',
          'cols': 80,
          'rows': 24,
        }),
      );
    });
    addTearDown(daemon.stop);

    final adapter = _RecordingAdapter();
    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(adapter),
    );
    addTearDown(manager.dispose);

    final minted = <(int, int, String?)>[];
    final target = MaidCafeTerminalTarget(
      baseUrl: daemon.baseUrl,
      secret: '',
      user: 'deploy',
      relayDaemonId: 'daemon-1',
      ticketProvider: (columns, rows, user) async {
        minted.add((columns, rows, user));
        return MaidCafeTerminalTicket(
          sessionId: 'session-1',
          ticket: 'ticket-abc',
          expiresAt: DateTime.utc(2026, 10, 1, 0, 1),
          daemonId: 'daemon-1',
        );
      },
    );

    final handle = await manager.openTerminal(
      _daemonServer(daemon.baseUrl),
      target,
    );
    addTearDown(() => manager.closeTerminal(handle.id));

    // The ticket was minted with the manager's initial geometry and the
    // target's run-as account, before the socket was dialed.
    expect(minted, [
      (maidCafeTerminalInitialColumns, maidCafeTerminalInitialRows, 'deploy'),
    ]);
    // The relay endpoint addresses the cloud daemon path.
    expect(paths.single, '/api/daemons/daemon-1/terminal');
    // The ticket rides the same encoding as a direct credential.
    expect(offered.single, 'maidcafe.terminal.c2Vzc2lvbi0xLnRpY2tldC1hYmM');
  });

  test('a refused ticket fails before any socket is opened', () async {
    var sockets = 0;
    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
      socketFactory: (endpoint, protocols) {
        sockets++;
        throw StateError('the socket must not be opened');
      },
    );
    addTearDown(manager.dispose);

    final target = MaidCafeTerminalTarget(
      baseUrl: 'https://mkc.solsynth.dev',
      secret: '',
      relayDaemonId: 'daemon-1',
      ticketProvider: (columns, rows, user) async =>
          throw const MaidCafeException(
            'Sign in with Solarpass before managing MaidCafe.',
            kind: MaidCafeErrorKind.signInRequired,
          ),
    );

    await expectLater(
      manager.openTerminal(_daemonServer(target.baseUrl), target),
      throwsA(
        isA<MaidCafeTerminalException>().having(
          (error) => error.message,
          'message',
          contains('Sign in with Solarpass'),
        ),
      ),
    );
    expect(sockets, 0);
    expect(manager.current, isEmpty);
  });

  test('a direct handshake asks for the selected account', () async {
    final queries = <Map<String, String>>[];
    final daemon = await _FakeDaemon.start((socket, request) {
      queries.add(request.uri.queryParameters);
      socket.add(
        jsonEncode({
          'type': 'hello',
          'version': 'v1',
          'session': 'session-1',
          'shell': '/bin/sh',
          'user': 'deploy',
          'cols': 80,
          'rows': 24,
        }),
      );
    });
    addTearDown(daemon.stop);

    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
    );
    addTearDown(manager.dispose);
    final server = _daemonServer(daemon.baseUrl);

    final selected = await manager.openTerminal(
      server,
      MaidCafeTerminalTarget(
        baseUrl: daemon.baseUrl,
        secret: 'metrics-secret',
        user: 'deploy',
      ),
    );
    addTearDown(() => manager.closeTerminal(selected.id));
    final daemonAccount = await manager.openTerminal(
      server,
      MaidCafeTerminalTarget(baseUrl: daemon.baseUrl, secret: 'metrics-secret'),
    );
    addTearDown(() => manager.closeTerminal(daemonAccount.id));

    expect(queries.first['user'], 'deploy');
    expect(queries.first['cols'], '$maidCafeTerminalInitialColumns');
    expect(queries.first['rows'], '$maidCafeTerminalInitialRows');
    // No selection: the parameter is absent, which the daemon reads as its own
    // account, rather than sent empty.
    expect(queries.last.containsKey('user'), isFalse);
  });

  test('drives a live daemon terminal session', () async {
    final received = <String>[];
    final offered = <String?>[];
    final sockets = <WebSocket>[];
    final daemon = await _FakeDaemon.start((socket, request) {
      sockets.add(socket);
      offered.add(request.headers.value('sec-websocket-protocol'));
      socket.add(
        jsonEncode({
          'type': 'hello',
          'version': 'v1',
          'session': 'session-1',
          'shell': '/bin/sh',
          'user': 'deploy',
          'cols': 80,
          'rows': 24,
        }),
      );
      socket.listen((frame) {
        if (frame is String) {
          final decoded = jsonDecode(frame) as Map<String, dynamic>;
          if (decoded['type'] == 'resize') {
            socket.add(
              Uint8List.fromList(
                utf8.encode('size ${decoded['cols']}x${decoded['rows']}\r\n'),
              ),
            );
          }
          return;
        }
        final text = utf8.decode((frame as List<int>));
        received.add(text);
        if (text.contains('exit')) {
          socket.add(jsonEncode({'type': 'exit', 'code': 0, 'reason': ''}));
        }
      });
    });
    addTearDown(daemon.stop);

    final adapter = _RecordingAdapter();
    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(adapter),
    );
    addTearDown(manager.dispose);
    final server = _daemonServer(daemon.baseUrl);

    final handle = await manager.openTerminal(
      server,
      MaidCafeTerminalTarget(baseUrl: daemon.baseUrl, secret: 'metrics-secret'),
    );
    addTearDown(() => manager.closeTerminal(handle.id));

    expect(handle.id, startsWith('maidcafe-'));
    expect(handle.adapter, same(adapter));
    // The daemon echoes the offered credential token.
    expect(offered.single, maidCafeTerminalToken('metrics-secret'));
    // The hello control frame is consumed, not rendered.
    expect(adapter.written, isEmpty);
    expect(manager.current.single.status, SessionStatus.connected);

    // PTY output arrives as binary frames and reaches the emulator.
    sockets.single.add(Uint8List.fromList(utf8.encode('echo hi\r\n')));
    await _until(() => adapter.writtenText.contains('echo hi'));

    // Keystrokes leave as binary frames.
    adapter.emitInput(Uint8List.fromList(utf8.encode('ls\n')));
    await _until(() => received.isNotEmpty);
    expect(received.first, 'ls\n');

    // A resize leaves as a text control frame and the daemon answers.
    adapter.emitResize(120, 40);
    await _until(() => adapter.writtenText.contains('size 120x40'));

    // An unknown control frame is ignored instead of tearing the session down.
    sockets.single.add(jsonEncode({'type': 'bogus'}));
    sockets.single.add(Uint8List.fromList(utf8.encode('still here\r\n')));
    await _until(() => adapter.writtenText.contains('still here'));

    // The daemon's exit frame completes the session as a normal close.
    adapter.emitInput(Uint8List.fromList(utf8.encode('exit\n')));
    await handle.done.timeout(const Duration(seconds: 5));
    await _until(
      () => manager.current.single.status == SessionStatus.closed,
      what: 'session status to become closed',
    );
    expect(manager.current.single.error, isNull);
  });

  test('reports a daemon error frame as a failed session', () async {
    final daemon = await _FakeDaemon.start((socket, request) {
      socket.add(jsonEncode({'type': 'error', 'message': 'terminal disabled'}));
    });
    addTearDown(daemon.stop);

    final adapter = _RecordingAdapter();
    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(adapter),
    );
    addTearDown(manager.dispose);

    final handle = await manager.openTerminal(
      _daemonServer(daemon.baseUrl),
      MaidCafeTerminalTarget(baseUrl: daemon.baseUrl, secret: 'metrics-secret'),
    );
    await handle.done.timeout(const Duration(seconds: 5));
    await _until(
      () => manager.current.single.status == SessionStatus.failed,
      what: 'session status to become failed',
    );
    expect(manager.current.single.error, 'terminal disabled');
  });

  test('rejects a daemon that speaks another protocol version', () async {
    final daemon = await _FakeDaemon.start((socket, request) {
      socket.add(
        jsonEncode({
          'type': 'hello',
          'version': 'v2',
          'session': 'session-1',
          'shell': '/bin/sh',
          'user': 'deploy',
          'cols': 80,
          'rows': 24,
        }),
      );
    });
    addTearDown(daemon.stop);

    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
    );
    addTearDown(manager.dispose);

    final handle = await manager.openTerminal(
      _daemonServer(daemon.baseUrl),
      MaidCafeTerminalTarget(baseUrl: daemon.baseUrl, secret: 'metrics-secret'),
    );
    await handle.done.timeout(const Duration(seconds: 5));
    await _until(
      () => manager.current.single.status == SessionStatus.failed,
      what: 'session status to become failed',
    );
    expect(manager.current.single.error, contains('v2'));
  });

  test('fails the handshake when the daemon refuses the credential', () async {
    // A daemon that answers like the real one does for a wrong secret.
    final daemon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    daemon.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('{"ok":false,"error":"unauthorized"}');
      await request.response.close();
    });
    addTearDown(() => daemon.close(force: true));

    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
    );
    addTearDown(manager.dispose);

    final baseUrl = 'http://127.0.0.1:${daemon.port}';
    await expectLater(
      manager.openTerminal(
        _daemonServer(baseUrl),
        MaidCafeTerminalTarget(baseUrl: baseUrl, secret: 'wrong'),
      ),
      throwsA(
        isA<MaidCafeTerminalException>()
            // The daemon answered 401, so the diagnosis names the credential
            // and does not send the user after the port or the origin list.
            .having(
              (error) => error.handshake,
              'handshake',
              MaidCafeTerminalHandshakeFailure.credential,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(
                contains('rejected this credential'),
                isNot(contains('allowedOrigins')),
              ),
            ),
      ),
    );
    expect(manager.current, isEmpty);
  });

  test('a switched-off terminal is reported as switched off', () async {
    // How the real daemon answers while daemon.terminal.enabled is false.
    final daemon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    daemon.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('{"ok":false,"error":"terminal disabled"}');
      await request.response.close();
    });
    addTearDown(() => daemon.close(force: true));

    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
    );
    addTearDown(manager.dispose);

    final baseUrl = 'http://127.0.0.1:${daemon.port}';
    await expectLater(
      manager.openTerminal(
        _daemonServer(baseUrl),
        MaidCafeTerminalTarget(baseUrl: baseUrl, secret: 'secret'),
      ),
      throwsA(
        isA<MaidCafeTerminalException>()
            .having(
              (error) => error.handshake,
              'handshake',
              MaidCafeTerminalHandshakeFailure.disabled,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(contains('switched off'), isNot(contains('origin'))),
            ),
      ),
    );
  });

  test('a switched-off terminal is reported as switched off', () async {
    // How the real daemon answers while daemon.terminal.enabled is false.
    final daemon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    daemon.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('{"ok":false,"error":"terminal disabled"}');
      await request.response.close();
    });
    addTearDown(() => daemon.close(force: true));

    final manager = MaidCafeTerminalConnectionManager(
      () => _AdapterFactory(_RecordingAdapter()),
    );
    addTearDown(manager.dispose);

    final baseUrl = 'http://127.0.0.1:${daemon.port}';
    await expectLater(
      manager.openTerminal(
        _daemonServer(baseUrl),
        MaidCafeTerminalTarget(baseUrl: baseUrl, secret: 'secret'),
      ),
      throwsA(
        isA<MaidCafeTerminalException>()
            .having(
              (error) => error.handshake,
              'handshake',
              MaidCafeTerminalHandshakeFailure.disabled,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(contains('switched off'), isNot(contains('origin'))),
            ),
      ),
    );
  });

  test(
    'serves an SSH server over the daemon, one socket per session',
    () async {
      final sockets = <WebSocket>[];
      final daemon = await _FakeDaemon.start((socket, request) {
        sockets.add(socket);
        socket.add(
          jsonEncode({
            'type': 'hello',
            'version': 'v1',
            'session': 'session-${sockets.length}',
            'shell': '/bin/sh',
            'user': 'deploy',
            'cols': 80,
            'rows': 24,
          }),
        );
      });
      addTearDown(daemon.stop);

      final manager = MaidCafeTerminalConnectionManager(
        () => _AdapterFactory(_RecordingAdapter()),
      );
      addTearDown(manager.dispose);

      // A browser cannot open a raw SSH socket, so an SSH server that carries a
      // daemon route is served here instead.
      final server = _daemonServer(
        daemon.baseUrl,
        connectionType: ServerConnectionType.ssh.name,
      );
      final target = MaidCafeTerminalTarget(
        baseUrl: daemon.baseUrl,
        secret: 'metrics-secret',
      );

      final first = await manager.openTerminal(server, target);
      final second = await manager.openTerminal(server, target);
      addTearDown(() => manager.closeTerminal(first.id));
      addTearDown(() => manager.closeTerminal(second.id));

      // Every session owns its socket, so any number run at the same time.
      expect(first.id, isNot(second.id));
      expect(sockets, hasLength(2));
    },
  );

  test('a server reports a daemon route only when it has one', () {
    expect(
      _daemonServer('http://127.0.0.1:8747').hasMaidCafeTerminalRoute,
      isTrue,
    );
    // The route is a transport, not a connection type.
    expect(
      _daemonServer(
        'http://127.0.0.1:8747',
        connectionType: ServerConnectionType.ssh.name,
      ).hasMaidCafeTerminalRoute,
      isTrue,
    );
    expect(_sshServer().hasMaidCafeTerminalRoute, isFalse);
    // A cloud route needs the daemon identity to address.
    expect(_sshServer(viaCloud: true).hasMaidCafeTerminalRoute, isFalse);
    expect(
      _sshServer(daemonId: 'daemon-1', viaCloud: true).hasMaidCafeTerminalRoute,
      isTrue,
    );
    expect(_sshServer(url: '   ').hasMaidCafeTerminalRoute, isFalse);
    // A port a native client learned is a route on its own.
    expect(_sshServer(daemonPort: 9000).hasMaidCafeTerminalRoute, isTrue);
  });

  test('a browser dials the server host on the learned daemon port', () {
    // The native client reaches the daemon through its SSH tunnel, so what it
    // stores is a loopback address; a browser has no tunnel and dials the host.
    expect(
      _sshServer(
        url: 'http://127.0.0.1:8747',
        daemonPort: 8747,
      ).maidCafeBrowserTerminalUrl,
      'http://ssh.local:8747',
    );
    // With no stored endpoint at all, the learned port is enough to try.
    expect(
      _sshServer(daemonPort: 9000).maidCafeBrowserTerminalUrl,
      'http://ssh.local:9000',
    );
    // Without a learned port the stored address still carries one.
    expect(
      _sshServer(url: 'http://127.0.0.1:8747').maidCafeBrowserTerminalUrl,
      'http://ssh.local:8747',
    );
    // A path-prefixed reverse proxy keeps its prefix.
    expect(
      _sshServer(
        url: 'http://127.0.0.1:8747/maidcafe',
        daemonPort: 8747,
      ).maidCafeBrowserTerminalUrl,
      'http://ssh.local:8747/maidcafe',
    );
    // An endpoint that is already reachable is left alone.
    expect(
      _sshServer(
        url: 'https://host.tailnet.ts.net',
        daemonPort: 8747,
      ).maidCafeBrowserTerminalUrl,
      'https://host.tailnet.ts.net',
    );
    // Nothing to dial.
    expect(_sshServer().maidCafeBrowserTerminalUrl, isNull);
    expect(_sshServer(url: '   ').maidCafeBrowserTerminalUrl, isNull);
    expect(
      _sshServer(
        url: 'http://127.0.0.1:8747',
        host: '',
      ).maidCafeBrowserTerminalUrl,
      'http://127.0.0.1:8747',
    );
    // A row that is itself loopback stays on loopback.
    expect(
      _sshServer(
        host: '127.0.0.1',
        daemonPort: 9000,
      ).maidCafeBrowserTerminalUrl,
      'http://127.0.0.1:9000',
    );
  });
}

/// An SSH server row that may also carry a MaidCafe daemon route.
Server _sshServer({
  String host = 'ssh.local',
  String? url,
  String? daemonId,
  int? daemonPort,
  bool viaCloud = false,
}) => Server(
  id: 3,
  name: 'SSH host',
  host: host,
  port: 22,
  username: 'deploy',
  collectStats: false,
  collectSystemInfo: false,
  connectionType: ServerConnectionType.ssh.name,
  maidCafeTerminalUrl: url,
  maidCafeDaemonId: daemonId,
  maidCafeTerminalPort: daemonPort,
  maidCafeTerminalViaCloud: viaCloud,
);

Server _daemonServer(String endpoint, {String connectionType = 'maidcafe'}) =>
    Server(
      id: 7,
      name: 'Daemon host',
      host: 'daemon.local',
      port: 8747,
      username: '',
      collectStats: false,
      collectSystemInfo: false,
      connectionType: connectionType,
      maidCafeTerminalUrl: endpoint,
      maidCafeTerminalViaCloud: false,
    );

/// A WebSocket endpoint that speaks the daemon's side of the terminal
/// protocol, so the transport is exercised over a real socket.
class _FakeDaemon {
  _FakeDaemon(this._server);

  final HttpServer _server;

  static Future<_FakeDaemon> start(
    void Function(WebSocket socket, HttpRequest request) onConnection,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) =>
            protocols.isEmpty ? null : protocols.first,
      );
      onConnection(socket, request);
    });
    return _FakeDaemon(server);
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);
}

class _AdapterFactory implements TerminalSessionAdapterFactory {
  _AdapterFactory(this.adapter);

  final TerminalSessionAdapter adapter;

  @override
  TerminalSessionAdapter create() => adapter;
}

/// Terminal emulator double: records what the transport delivers and lets a
/// test push input and resize events back.
class _RecordingAdapter implements TerminalSessionAdapter {
  final _written = <int>[];
  final _input = StreamController<Uint8List>.broadcast();
  final _resize = StreamController<TerminalResize>.broadcast();

  String get writtenText => utf8.decode(_written, allowMalformed: true);

  /// Raw bytes the transport handed to the emulator.
  Uint8List get written => Uint8List.fromList(_written);

  void emitInput(Uint8List bytes) => _input.add(bytes);

  void emitResize(int columns, int rows) => _resize.add(
    TerminalResize(columns: columns, rows: rows, pixelWidth: 0, pixelHeight: 0),
  );

  @override
  Stream<Uint8List> get outgoingBytes => _input.stream;

  @override
  Stream<TerminalResize> get resizeEvents => _resize.stream;

  @override
  Stream<bool> get taskRunning => const Stream.empty();

  @override
  Stream<TerminalTaskActivity> get taskActivity => const Stream.empty();

  @override
  bool get isTaskRunning => false;

  @override
  TerminalTaskActivity get currentTaskActivity =>
      const TerminalTaskActivity(running: false);

  @override
  String? get currentDirectory => null;

  @override
  int get bufferRows => 0;

  @override
  String? dumpHistory({int maxLines = 4000}) => null;

  @override
  void replayHistory(String text) {}

  @override
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

  @override
  void write(Uint8List bytes) => _written.addAll(bytes);

  @override
  void sendInput(String text) =>
      emitInput(Uint8List.fromList(utf8.encode(text)));

  @override
  void showKeyboard() {}

  @override
  void hideKeyboard() {}

  @override
  Rect? get cursorGlobalRect => null;

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox.shrink();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {
    await _input.close();
    await _resize.close();
  }
}

/// Polls [predicate] until it holds, so tests do not race asynchronous frames.
Future<void> _until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String what = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $what.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
