import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

/// One tmux session running on a host, detached from any MaidKit pane.
class TmuxSessionInfo {
  const TmuxSessionInfo({
    required this.name,
    required this.windows,
    required this.createdAt,
    required this.attached,
  });

  final String name;
  final int windows;
  final DateTime createdAt;

  /// How many clients are attached right now. Zero means background.
  final int attached;
}

/// The result of listing a host's tmux sessions.
///
/// [tmuxInstalled] is false when the host has no tmux at all, which the sheet
/// reports instead of an error: it is a normal state, not a failure.
typedef TmuxSessionListing = ({
  List<TmuxSessionInfo> sessions,
  bool tmuxInstalled,
});

/// Sessions on a host that the user did not get from MaidKit itself.
///
/// MaidKit names its own session after [server], so opening a terminal there
/// lands in the session it made. Anything else on the host was started by the
/// user - by hand, by another client, or by a script - and is only reachable if
/// it is offered, which is what makes a picker worth showing. An empty result
/// means there is nothing to choose between and opening a terminal should just
/// proceed as it always has.
List<TmuxSessionInfo> attachableTmuxSessions(
  List<TmuxSessionInfo> sessions, {
  required String defaultName,
}) => [
  for (final session in sessions)
    if (session.name != defaultName) session,
];

/// Lists the tmux sessions [server]'s host has running.
///
/// A row with a resolvable daemon route asks the daemon over its HTTP API; any
/// other non-serial row asks over SSH. A serial row has no tmux at all, so it
/// reports the empty listing.
Future<TmuxSessionListing> listTmuxSessionsFor(
  WidgetRef ref,
  Server server,
) async {
  if (server.connectionType == ServerConnectionType.serial.name) {
    return (sessions: const <TmuxSessionInfo>[], tmuxInstalled: false);
  }
  final repository = ref.read(serverRepositoryProvider);
  final target = await repository.maidCafeTerminalTargetFor(server);
  if (target != null) {
    final session = await _openDaemonSession(ref, server);
    try {
      final payload = await session.terminalSessions();
      return _parseDaemonListing(payload);
    } finally {
      await session.close();
    }
  }
  final manager = ref.read(connectionManagerProvider);
  final sessions = await manager.withClient(server.id, readTmuxSessionsOverSsh);
  return (sessions: sessions, tmuxInstalled: true);
}

/// Reads the host's tmux sessions over [client].
///
/// Kept separate from the route decision so the one thing that can silently
/// produce an empty listing is testable on its own: `stdout` is a byte stream,
/// and joining it without decoding yields `[99, 97, ...]`, which parses no rows
/// at all and reads as "this host has no sessions".
Future<List<TmuxSessionInfo>> readTmuxSessionsOverSsh(SSHClient client) async {
  final session = await client.execute(
    "tmux list-sessions -F "
    "'#{session_name}\t#{session_windows}\t#{session_created}\t#{session_attached}'",
  );
  final stdout = await utf8.decoder.bind(session.stdout).join();
  await session.done;
  return parseTmuxSessionRows(stdout);
}

/// Attaches [name] on [server]'s host as a terminal tab.
///
/// Context-free on purpose: the sheet that calls it has already resolved the
/// route, so an attach only has to open the transport and mount the tab. A
/// refusal is thrown for the sheet to report where the user is looking.
Future<void> attachTmuxSession(WidgetRef ref, Server server, String name) => ref
    .read(terminalTabsProvider.notifier)
    .openTmuxSession(server, sessionName: name);

/// Ends [name] on [server]'s host, every process in it.
Future<void> killTmuxSession(WidgetRef ref, Server server, String name) async {
  final repository = ref.read(serverRepositoryProvider);
  final target = await repository.maidCafeTerminalTargetFor(server);
  if (target != null) {
    final session = await _openDaemonSession(ref, server);
    try {
      await session.killTerminalSession(name);
    } finally {
      await session.close();
    }
    return;
  }
  final manager = ref.read(connectionManagerProvider);
  await manager.withClient(server.id, (client) async {
    final session = await client.execute(
      "tmux kill-session -t ${_shellQuote(name)}",
    );
    await session.done;
  });
}

/// Parses the daemon's `/api/v1/terminal/sessions` payload.
TmuxSessionListing _parseDaemonListing(Map<String, dynamic> payload) {
  final installed = payload['tmux'] == true;
  final rows = payload['sessions'];
  if (rows is! List) {
    return (sessions: const <TmuxSessionInfo>[], tmuxInstalled: installed);
  }
  final sessions = <TmuxSessionInfo>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final name = row['name'];
    if (name is! String || name.isEmpty) continue;
    final created = row['created'];
    sessions.add(
      TmuxSessionInfo(
        name: name,
        windows: (row['windows'] as num?)?.toInt() ?? 0,
        createdAt: created is num
            ? DateTime.fromMillisecondsSinceEpoch(
                created.toInt() * 1000,
                isUtc: true,
              )
            : DateTime.now(),
        attached: (row['attached'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return (sessions: sessions, tmuxInstalled: installed);
}

/// Parses `session_name<TAB>windows<TAB>created<TAB>attached` rows, the format
/// both transports ask tmux for. A row that does not parse is skipped rather
/// than failing the listing.
List<TmuxSessionInfo> parseTmuxSessionRows(String output) {
  final sessions = <TmuxSessionInfo>[];
  for (final line in output.split(RegExp(r'\r?\n'))) {
    if (line.trim().isEmpty) continue;
    final fields = line.split('\t');
    if (fields.length < 4) continue;
    final windows = int.tryParse(fields[1].trim());
    final created = int.tryParse(fields[2].trim());
    final attached = int.tryParse(fields[3].trim());
    if (windows == null || created == null || attached == null) continue;
    sessions.add(
      TmuxSessionInfo(
        name: fields[0].trim(),
        windows: windows,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          created * 1000,
          isUtc: true,
        ),
        attached: attached,
      ),
    );
  }
  return sessions;
}

Future<MaidCafeStreamSession> _openDaemonSession(
  WidgetRef ref,
  Server server,
) async {
  final repository = ref.read(serverRepositoryProvider);
  final credential = await repository.credentialFor(server);
  final apiSecret = await repository.maidCafeMetricsSecretFor(server);
  return MaidCafeStreamSession.open(
    manager: ref.read(connectionManagerProvider),
    server: server,
    apiSecret: apiSecret,
    sudoPassword: credential.type == CredentialType.password
        ? credential.password
        : null,
  );
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
