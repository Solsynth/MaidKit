import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_connectivity.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/maidcafe_terminal_connection_manager.dart';
import 'package:maid_kit/servers/server_models.dart';

const _target = MaidCafeTerminalTarget(
  baseUrl: 'https://daemon.example',
  secret: 'secret',
);

MaidCafeDaemonHealth _health() => MaidCafeDaemonHealth.fromJson({
  'ok': true,
  'mode': 'daemon',
  'id': 'daemon-1',
});

/// Probes with per-step overrides, so each report can be driven exactly.
MaidCafeConnectivityProbes _probes({
  Object? resolveError,
  MaidCafeTerminalTarget? target = _target,
  Object? healthError,
  Object? terminalError,
}) => MaidCafeConnectivityProbes(
  resolveTarget: ({required relay}) async {
    if (resolveError != null) throw resolveError;
    return target;
  },
  checkHealth: (baseUrl, secret) async {
    if (healthError != null) throw healthError;
    return _health();
  },
  openTerminal: (target) async {
    if (terminalError != null) throw terminalError;
  },
);

Server _server({
  int? port,
  String? terminalUrl,
  String? daemonUrl,
  bool? terminalEnabled,
}) => Server(
  id: 1,
  name: 'host',
  host: '10.0.0.9',
  port: 22,
  username: 'root',
  collectStats: false,
  collectSystemInfo: false,
  connectionType: ServerConnectionType.ssh.name,
  maidCafeTerminalPort: port,
  maidCafeTerminalUrl: terminalUrl,
  maidCafeDaemonUrl: daemonUrl,
  maidCafeTerminalEnabled: terminalEnabled,
  maidCafeTerminalViaCloud: false,
);

void main() {
  test(
    'the daemon terminal switch is reported before any network advice',
    () async {
      final disabled = await runMaidCafeConnectivityCheck(
        _probes(),
        relay: false,
        terminalEnabled: false,
      );
      final enabled = await runMaidCafeConnectivityCheck(
        _probes(),
        relay: false,
        terminalEnabled: true,
      );
      final unknown = await runMaidCafeConnectivityCheck(
        _probes(),
        relay: false,
      );

      expect(disabled.steps, hasLength(4));
      expect(disabled.steps[1].titleKey, 'maidCafeCheckTerminalEnabled');
      expect(disabled.steps[1].status, MaidCafeConnectivityStatus.failed);
      expect(enabled.steps[1].status, MaidCafeConnectivityStatus.ok);
      // An unread switch stays silent rather than claiming a state.
      expect(unknown.steps, hasLength(3));

      // Enabling the terminal comes before exposing a port.
      expect(
        maidCafeRouteFailureHint(disabled, 'expose port 8747'),
        isNot('expose port 8747'),
      );
      expect(
        maidCafeRouteFailureHint(enabled, 'expose port 8747'),
        'expose port 8747',
      );
    },
  );

  test('a registered daemon is matched to its server by name', () {
    MaidCafeDaemon daemon(String id, String name) => MaidCafeDaemon(
      id: id,
      name: name,
      enabled: true,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect(
      pickMaidCafeDaemonForServer([
        daemon('d1', 'web'),
        daemon('d2', 'prod-db'),
      ], 'prod-db')?.id,
      'd2',
    );
    // Case and padding are the server row's business, not the cloud's.
    expect(
      pickMaidCafeDaemonForServer([daemon('d1', 'Prod-DB')], ' prod-db ')?.id,
      'd1',
    );
    expect(
      pickMaidCafeDaemonForServer([daemon('d1', 'web')], 'prod-db'),
      isNull,
    );
    // Two daemons sharing a name are ambiguous and must be picked by hand.
    expect(
      pickMaidCafeDaemonForServer([
        daemon('d1', 'web'),
        daemon('d2', 'web'),
      ], 'web'),
      isNull,
    );
    expect(pickMaidCafeDaemonForServer([daemon('d1', 'web')], '  '), isNull);
  });

  test('a stale daemon uuid falls back to the registration by name', () {
    MaidCafeDaemon daemon2(String id, String name) => MaidCafeDaemon(
      id: id,
      name: name,
      enabled: true,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      terminalRelayEnabled: true,
    );
    final daemons = [daemon2('fresh', 'web'), daemon2('other', 'db')];

    // The stored uuid still exists: it wins over the name.
    expect(
      resolveMaidCafeDaemon(daemons, 'web', daemonId: 'other')?.id,
      'other',
    );
    // The stored uuid is gone (re-registered, deleted, foreign): fall back.
    expect(
      resolveMaidCafeDaemon(daemons, 'web', daemonId: 'stale-uuid')?.id,
      'fresh',
    );
    expect(resolveMaidCafeDaemon(daemons, 'web')?.id, 'fresh');
    expect(resolveMaidCafeDaemon(daemons, 'gone'), isNull);
  });

  test('the cloud relay opt-in is parsed from the daemon record', () {
    MaidCafeDaemon parse({bool? relay}) => MaidCafeDaemon.fromJson({
      'id': 'd1',
      'name': 'web',
      'enabled': true,
      'last_seen_at': '2026-01-01T00:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'terminal_relay_enabled': ?relay,
    });

    expect(parse(relay: true).terminalRelayEnabled, isTrue);
    expect(parse(relay: false).terminalRelayEnabled, isFalse);
    // A daemon that never opted in omits the field.
    expect(parse().terminalRelayEnabled, isFalse);
  });

  test('the report shows the endpoint the probe was handed', () async {
    // The check resolves the browser route and hands it to the probes, so the
    // address in the report is the one that was dialed — a tunnel port here
    // would mean the check answered for a client that cannot use it.
    final report = await runMaidCafeConnectivityCheck(
      MaidCafeConnectivityProbes(
        resolveTarget: ({required relay}) async => const MaidCafeTerminalTarget(
          baseUrl: 'http://host.example:8747',
          secret: 'secret',
        ),
        checkHealth: (baseUrl, secret) async => _health(),
        openTerminal: (target) async {},
      ),
      relay: false,
    );

    expect(
      report.steps
          .firstWhere((step) => step.titleKey == 'maidCafeCheckRoute')
          .detail,
      'http://host.example:8747',
    );
  });

  test('the advice matches the cause of a failed direct route', () {
    MaidCafeTerminalException refused(
      MaidCafeTerminalHandshakeFailure failure,
    ) => MaidCafeTerminalException('refused', handshake: failure);
    final server = _server(daemonUrl: 'http://127.0.0.1:8747', port: 8747);

    // The endpoint answered, so the port is open: no expose-the-port advice.
    expect(
      maidCafeRouteFailureSuffix(
        server,
        refused(MaidCafeTerminalHandshakeFailure.credential),
      ),
      '',
    );
    expect(
      maidCafeRouteFailureSuffix(
        server,
        refused(MaidCafeTerminalHandshakeFailure.origin),
      ),
      '',
    );
    // A terminal that is off has to be switched on, whatever else is wrong.
    expect(
      maidCafeRouteFailureSuffix(
        server,
        refused(MaidCafeTerminalHandshakeFailure.disabled),
      ),
      'maidCafeTerminalDisabledShort',
    );
    // Nothing answered: this is the case the port advice is for. This daemon
    // listens on loopback, so the advice names the bind as well as the port.
    expect(
      maidCafeRouteFailureSuffix(
        server,
        const MaidCafeTerminalException('connection refused'),
      ),
      'maidCafeExposePortBindShort',
    );
    // A daemon already reachable from another host only needs the port open.
    expect(
      maidCafeRouteFailureSuffix(
        _server(daemonUrl: 'http://10.0.0.5:8747', port: 8747),
        const MaidCafeTerminalException('connection refused'),
      ),
      'maidCafeExposePortShort',
    );
  });

  test(
    'a relay without a daemon says so instead of "not configured"',
    () async {
      final report = await runMaidCafeConnectivityCheck(
        _probes(target: null),
        relay: true,
        notConfiguredKey: 'maidCafeCheckRelayUnregistered',
      );

      expect(report.steps.single.detailKey, 'maidCafeCheckRelayUnregistered');
      // The direct route keeps its own wording.
      final direct = await runMaidCafeConnectivityCheck(
        _probes(target: null),
        relay: false,
      );
      expect(direct.steps.single.detailKey, 'maidCafeCheckNotConfigured');
    },
  );

  test('an unreachable direct route names the port to expose', () {
    // Nothing learned yet: the daemon default, listening on its own machine.
    expect(maidCafeExposure(_server()), (
      port: 8747,
      listenHost: '127.0.0.1',
      listensOnlyLocally: true,
    ));
    // A stored endpoint says the port, the address and that it is dialable.
    expect(
      maidCafeExposure(
        _server(
          terminalUrl: 'http://daemon.example:9443',
          daemonUrl: 'http://10.0.0.5:9443',
        ),
      ),
      (port: 9443, listenHost: '10.0.0.5', listensOnlyLocally: false),
    );
    // The port a probe or install learned wins over an endpoint's.
    expect(
      maidCafeExposure(
        _server(port: 9000, terminalUrl: 'http://daemon.example:9443'),
      ).port,
      9000,
    );
  });

  test('only a dialable endpoint counts as an override', () {
    // What the user pointed at the daemon: a TLS front on a real host name.
    expect(
      _server(terminalUrl: 'https://daemon.example').maidCafeEndpointOverride,
      'https://daemon.example',
    );
    // A loopback address is the route the app builds for itself (an SSH
    // forward), not an override, so resolving it must stay automatic.
    for (final url in [
      'http://127.0.0.1:8747',
      'http://localhost:8747',
      'http://[::1]:8747',
    ]) {
      expect(
        _server(terminalUrl: url).maidCafeEndpointOverride,
        isNull,
        reason: '$url is not reachable from another host',
      );
    }
    expect(_server().maidCafeEndpointOverride, isNull);
    expect(_server(terminalUrl: '   ').maidCafeEndpointOverride, isNull);
  });

  test('a loopback or wildcard bind is reported as unreachable', () {
    // Opening a port in front of a loopback bind changes nothing, so the advice
    // has to say which of the two is missing.
    for (final host in ['127.0.0.1', 'localhost', '::1', '0.0.0.0', '::']) {
      expect(
        maidCafeExposure(
          _server(daemonUrl: 'http://$host:8747'),
        ).listensOnlyLocally,
        isTrue,
        reason: '$host names no address another host can dial',
      );
    }
    // A concrete non-loopback address is dialable; only the firewall is left.
    for (final host in ['10.0.0.5', 'daemon.example']) {
      expect(
        maidCafeExposure(
          _server(daemonUrl: 'http://$host:8747'),
        ).listensOnlyLocally,
        isFalse,
        reason: '$host is reachable from another host',
      );
    }
  });

  test('a healthy daemon passes every step', () async {
    final report = await runMaidCafeConnectivityCheck(_probes(), relay: false);

    expect(report.relay, isFalse);
    expect(report.configured, isTrue);
    expect(report.ok, isTrue);
    expect(report.failed, isFalse);
    expect(report.steps.map((step) => step.titleKey), [
      'maidCafeCheckRoute',
      'maidCafeCheckReachability',
      'maidCafeCheckTerminal',
    ]);
    expect(report.steps.first.detail, 'https://daemon.example');
    expect(report.steps[1].detail, contains('daemon-1'));
  });

  test(
    'a relay report runs the same steps against the relay endpoint',
    () async {
      final report = await runMaidCafeConnectivityCheck(_probes(), relay: true);

      expect(report.relay, isTrue);
      expect(report.ok, isTrue);
      expect(report.steps, hasLength(3));
    },
  );

  test('an unconfigured route is skipped, not failed', () async {
    final report = await runMaidCafeConnectivityCheck(
      _probes(target: null),
      relay: true,
    );

    expect(report.configured, isFalse);
    expect(report.failed, isFalse);
    expect(report.steps, hasLength(1));
    expect(report.steps.single.status, MaidCafeConnectivityStatus.skipped);
    expect(report.steps.single.detailKey, 'maidCafeCheckNotConfigured');
  });

  test('an endpoint that never answers stops the report', () async {
    final report = await runMaidCafeConnectivityCheck(
      _probes(healthError: DioException(requestOptions: RequestOptions())),
      relay: false,
    );

    expect(report.failed, isTrue);
    // A transport that never answered cannot handshake either.
    expect(report.steps, hasLength(2));
    expect(report.steps.last.status, MaidCafeConnectivityStatus.failed);
    expect(report.steps.last.detail, isNotEmpty);
  });

  test('a refused handshake reports the transport message', () async {
    final report = await runMaidCafeConnectivityCheck(
      _probes(
        terminalError: const MaidCafeTerminalException(
          'Cannot open the MaidCafe daemon terminal at daemon.example: origin '
          'not allowed.',
        ),
      ),
      relay: false,
    );

    expect(report.failed, isTrue);
    expect(report.steps, hasLength(3));
    expect(report.steps.last.titleKey, 'maidCafeCheckTerminal');
    expect(report.steps.last.detail, contains('origin not allowed'));
  });

  test('the endpoint check reports what could not be resolved', () async {
    final report = await runMaidCafeConnectivityCheck(
      _probes(
        resolveError: const MaidCafeException('Cloud is not configured.'),
      ),
      relay: true,
    );

    expect(report.failed, isTrue);
    expect(report.steps, hasLength(1));
    expect(report.steps.single.detail, 'Cloud is not configured.');
  });

  test('transport errors are described for the report', () {
    expect(
      describeMaidCafeError(const MaidCafeTerminalException('refused')),
      'refused',
    );
    expect(
      describeMaidCafeError(const MaidCafeException('bad endpoint')),
      'bad endpoint',
    );
    expect(
      describeMaidCafeError(
        DioException(
          requestOptions: RequestOptions(),
          response: Response<void>(
            requestOptions: RequestOptions(),
            statusCode: 401,
          ),
          message: 'unauthorized',
        ),
      ),
      contains('HTTP 401'),
    );
    expect(describeMaidCafeError(StateError('boom')), contains('boom'));
  });
}
