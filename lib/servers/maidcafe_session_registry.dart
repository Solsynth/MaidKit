import 'dart:async';

import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_repository.dart';
import 'ssh_connection_manager.dart';

/// Shares one [MaidCafeStreamSession] per server across every consumer — the
/// Activity, Processes, Containers, Systemd and MaidCafe-management tabs — so
/// a server has exactly one SSH port forward and one daemon config read no
/// matter how many tabs are open at once.
///
/// Consumers call [retain] while mounted, [release] on dispose, and
/// [sessionFor] to obtain the live session. The session opens lazily on first
/// use (single-flight across concurrent callers), closes when the last
/// consumer releases, and is force-closed by [invalidate] after the daemon is
/// reconfigured or restarted so the next request reconnects.
class MaidCafeSessionRegistry {
  MaidCafeSessionRegistry({
    required SshConnectionManager manager,
    required ServerRepository serverRepository,
  }) : this._(manager, serverRepository);

  MaidCafeSessionRegistry._(this._manager, this._serverRepository);

  final SshConnectionManager _manager;
  final ServerRepository _serverRepository;

  final Map<int, MaidCafeSessionEntry> _entries = {};

  /// Marks [server] as in use. Pair with [release]; the entry (and any open
  /// session) survives until the last release.
  void retain(Server server) {
    _entries.putIfAbsent(server.id, MaidCafeSessionEntry.new).refs++;
  }

  /// Releases one reference; the session and its port forward close when the
  /// last consumer releases.
  void release(Server server) {
    final entry = _entries[server.id];
    if (entry == null) return;
    if (--entry.refs <= 0) {
      entry.closeSession();
      _entries.remove(server.id);
    }
  }

  /// Force-closes the shared session after the daemon was reconfigured or
  /// restarted. References are kept; the next [sessionFor] reconnects.
  void invalidate(Server server) {
    _entries[server.id]?.closeSession();
  }

  /// Returns the live shared session, opening it on first use. Returns null
  /// when the server is not retained, when a previous open failed (until
  /// [invalidate] or a forced attempt succeeds), or while opening fails.
  ///
  /// [port] is honored only when the session is opened by this call; a live
  /// session is returned as-is. [force] bypasses a cached failure so
  /// management flows can reconnect immediately after (re)installing the
  /// daemon.
  Future<MaidCafeStreamSession?> sessionFor(
    Server server, {
    int? port,
    bool force = false,
  }) async {
    final entry = _entries[server.id];
    if (entry == null) return null;
    return entry.resolve(
      (port) => _open(server, port),
      port: port,
      force: force,
    );
  }

  Future<MaidCafeStreamSession> _open(Server server, int? port) async {
    final credential = await _serverRepository.credentialFor(server);
    final sudoPassword = credential.type == CredentialType.password
        ? credential.password
        : null;
    final apiSecret = await _serverRepository.maidCafeMetricsSecretFor(server);
    return MaidCafeStreamSession.open(
      manager: _manager,
      server: server,
      port: port,
      apiSecret: apiSecret,
      sudoPassword: sudoPassword,
    );
  }
}

/// Per-server session state: the live session (or null while down), a cached
/// open failure, and single-flight in-flight opens. Public only so unit tests
/// can drive the state machine with a stub opener; not part of the API.
class MaidCafeSessionEntry {
  int refs = 0;
  MaidCafeStreamSession? session;
  bool failed = false;
  Future<MaidCafeStreamSession?>? pending;

  Future<MaidCafeStreamSession?> resolve(
    Future<MaidCafeStreamSession> Function(int? port) open, {
    int? port,
    bool force = false,
  }) {
    final live = session;
    if (live != null) return Future.value(live);
    if (!force && failed) return Future.value(null);
    final inFlight = pending;
    if (inFlight != null) return inFlight;
    final future = _openAndCache(port, open);
    pending = future;
    return future;
  }

  Future<MaidCafeStreamSession?> _openAndCache(
    int? port,
    Future<MaidCafeStreamSession> Function(int? port) open,
  ) async {
    try {
      final opened = await open(port);
      session = opened;
      failed = false;
      return opened;
    } catch (_) {
      failed = true;
      return null;
    } finally {
      pending = null;
    }
  }

  void closeSession() {
    final live = session;
    session = null;
    failed = false;
    if (live != null) unawaited(live.close());
    final inFlight = pending;
    pending = null;
    if (inFlight != null) {
      // A concurrent open may still complete after the close; shut it down
      // so no orphan forward outlives the entry.
      unawaited(inFlight.then((opened) => opened?.close()));
    }
  }
}
