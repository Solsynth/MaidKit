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
///
/// The registry also tracks each server's SSH transport. Port forwards die
/// with the transport, and the connection manager tears them down on
/// disconnect without notifying the registry — a cached session would
/// otherwise become a zombie that fails every request and never recovers on
/// its own. On disconnect the affected sessions are closed; on reconnect the
/// cached open failures are cleared, so consumers (dashboard pinned tiles,
/// polling tabs) heal across SSH blips without any tab being open.
class MaidCafeSessionRegistry {
  MaidCafeSessionRegistry({
    required SshConnectionManager manager,
    required ServerRepository serverRepository,
  }) : this._(manager, serverRepository);

  MaidCafeSessionRegistry._(this._manager, this._serverRepository) {
    _statesSubscription = _manager.sessions.listen((states) {
      for (final serverId in _entries.keys.toList()) {
        final info = states.where((s) => s.serverId == serverId).firstOrNull;
        if (info == null || info.status != SessionStatus.connected) {
          _entries[serverId]?.closeSession();
        } else {
          _entries[serverId]?.clearFailure();
        }
      }
    });
  }

  final SshConnectionManager _manager;
  final ServerRepository _serverRepository;
  late final StreamSubscription<List<SshSessionInfo>> _statesSubscription;

  final Map<int, MaidCafeSessionEntry> _entries = {};

  /// Stops tracking the SSH transports. The provider owns the registry for
  /// the app lifetime, so this only runs on teardown; it does not close any
  /// live session (consumers still holding one own its cleanup).
  void close() {
    unawaited(_statesSubscription.cancel());
  }

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
  /// [invalidate], a forced attempt, the retry cooldown, or a reconnect),
  /// or while opening fails.
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
/// open failure with retry cooldown, and single-flight in-flight opens.
/// Public only so unit tests can drive the state machine with a stub opener;
/// not part of the API.
class MaidCafeSessionEntry {
  MaidCafeSessionEntry({this._retryAfter = const Duration(seconds: 30)});

  int refs = 0;
  MaidCafeStreamSession? session;
  DateTime? failedAt;
  Future<MaidCafeStreamSession?>? pending;
  final Duration _retryAfter;

  bool get _failed =>
      failedAt != null && DateTime.now().difference(failedAt!) < _retryAfter;

  Future<MaidCafeStreamSession?> resolve(
    Future<MaidCafeStreamSession> Function(int? port) open, {
    int? port,
    bool force = false,
  }) {
    final live = session;
    if (live != null && !live.isClosed) return Future.value(live);
    // A closed session is never reusable; drop it so the next call reopens.
    session = null;
    if (!force && _failed) return Future.value(null);
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
      failedAt = null;
      return opened;
    } catch (_) {
      failedAt = DateTime.now();
      return null;
    } finally {
      pending = null;
    }
  }

  /// Clears a cached open failure so the next [resolve] retries. Called when
  /// the server's SSH transport (re)connects: a failure from the old
  /// transport says nothing about the new one.
  void clearFailure() => failedAt = null;

  void closeSession() {
    final live = session;
    session = null;
    failedAt = null;
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
