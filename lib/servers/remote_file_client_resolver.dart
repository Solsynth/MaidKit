import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_file_system.dart';
import 'maidcafe_session_registry.dart';
import 'remote_file_system.dart';
import 'server_models.dart';
import 'ssh_connection_manager.dart';

/// Chooses the transport a file surface browses with.
///
/// SFTP is used whenever the server has a live SSH client, because it is the
/// richer transport: it can change permissions, extract archives and stream a
/// file past the daemon's read cap. When there is no SSH client, [daemonAllowed]
/// decides whether the MaidCafe daemon's file API takes over — which is what
/// makes the file surfaces usable in a browser, where no raw socket can be
/// opened.
///
/// The surfaces pass `kIsWeb`, mirroring how terminals choose their transport:
/// a browser has only the daemon, while a native client keeps SFTP and its
/// connect prompt unchanged rather than silently serving files from a root the
/// operator may have scoped differently.
///
/// A daemon-backed client retains the shared session for as long as it lives and
/// releases it on [RemoteFileClient.close]. Consumers keep their existing habit
/// of closing the client they opened, and the registry's reference count
/// decides when the session (and its port forward on a native client) actually
/// goes away — a file tab closing does not disturb the metrics or container
/// tabs sharing that session.
///
/// Throws [ServerConnectionRequiredException] when SSH is required but absent
/// (the native path, unchanged), and [RemoteFileRouteUnavailable] when the
/// daemon was allowed but the server carries no route to one.
Future<RemoteFileClient> resolveRemoteFileClient({
  required SshConnectionManager manager,
  required MaidCafeSessionRegistry registry,
  required Server server,
  required bool daemonAllowed,
  int? port,
}) async {
  final owner = manager.clientFor(server.id);
  if (owner != null) {
    return SftpRemoteFileClient(await owner.sftp());
  }
  if (!daemonAllowed) {
    throw const ServerConnectionRequiredException();
  }
  // Retained here rather than by each consumer, so the client's own close is
  // the matching release and no consumer can leak a session by forgetting to
  // un-retain it. Two live clients hold two references, which is what keeps a
  // second file tab from closing the first tab's session.
  registry.retain(server);
  final session = await registry.sessionFor(server, port: port);
  if (session == null) {
    registry.release(server);
    throw const RemoteFileRouteUnavailable();
  }
  return MaidCafeRemoteFileClient(
    session,
    onClose: () => registry.release(server),
  );
}

/// Raised when the MaidCafe daemon was the only possible file transport and the
/// server has no route to one.
class RemoteFileRouteUnavailable implements Exception {
  const RemoteFileRouteUnavailable();

  @override
  String toString() =>
      'This server has no reachable MaidCafe daemon to browse files through. '
      'Add its daemon endpoint, or connect over SSH.';
}
