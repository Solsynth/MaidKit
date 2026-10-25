import 'package:maid_kit/data/local/app_database.dart';

import 'server_models.dart';

/// The session that represents [serverId] in the merged session feed.
///
/// The feed is a union of every transport, so one server can appear in it more
/// than once: an SSH session and a MaidCafe terminal for the same server are
/// two entries, and the MaidCafe one carries no stats. A connected entry wins
/// over one that is not, and among those an SSH session wins outright — it is
/// the entry that carries the readings, and the only one that can run the
/// SSH-shaped work a reader may go on to ask for. Falls back to the first entry
/// so a server that is connecting, failed or closed still reports itself.
SshSessionInfo? sessionForServer(List<SshSessionInfo> sessions, int serverId) {
  final matches = sessions.where((item) => item.serverId == serverId).toList();
  if (matches.isEmpty) return null;
  return liveSshSession(matches, serverId) ??
      matches
          .where((item) => item.status == SessionStatus.connected)
          .firstOrNull ??
      matches.first;
}

/// The SSH session for [serverId] while it is connected, or null.
///
/// The daemon's terminal is a session on the same feed and it is `connected`
/// too, but it does not run the SSH-shaped work — statistics, SFTP, exec — so
/// it is not one of these. That distinction is the whole point of
/// [SessionTransport].
SshSessionInfo? liveSshSession(List<SshSessionInfo> sessions, int serverId) =>
    sessions
        .where((session) => isLiveSshSession(session, serverId))
        .firstOrNull;

/// Whether [session] is a connected SSH session for [serverId].
bool isLiveSshSession(SshSessionInfo? session, [int? serverId]) =>
    session != null &&
    (serverId == null || session.serverId == serverId) &&
    session.status == SessionStatus.connected &&
    session.transport == SessionTransport.ssh;

/// Whether [server] has an SSH route a failed daemon read can fall back to.
///
/// This is not a transport preference: the MaidCafe daemon leads every surface
/// it implements, and SSH answers only when there is no daemon route or the
/// daemon is older than the endpoint the surface asks for (see
/// `docs/ARCHITECTURE.md`). A `serial` row has no SSH transport, so a failed
/// daemon read has nothing to fall back to and the surface reports the daemon's
/// own reason instead.
bool sshFallbackAvailable(Server server) =>
    server.connectionType == ServerConnectionType.ssh.name;
