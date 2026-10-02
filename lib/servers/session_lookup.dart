import 'server_models.dart';

/// The session that represents [serverId] in the merged session feed.
///
/// The feed is a union of every transport, so one server can appear in it more
/// than once: an SSH session and a MaidCafe terminal for the same server are
/// two entries, and the MaidCafe one carries no stats. The connected entry wins,
/// which keeps the readings — and the "connected" state — tied to the session
/// that actually has them rather than to whichever transport happens to come
/// first in the list.
SshSessionInfo? sessionForServer(List<SshSessionInfo> sessions, int serverId) {
  final matches = sessions.where((item) => item.serverId == serverId);
  if (matches.isEmpty) return null;
  return matches
          .where((item) => item.status == SessionStatus.connected)
          .firstOrNull ??
      matches.first;
}
