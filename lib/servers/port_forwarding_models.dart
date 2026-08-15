import 'package:easy_localization/easy_localization.dart';

enum PortForwardDirection { local, remote }

enum PortForwardKind { tcp, socks5 }

enum PortForwardOwner { user, maidCafe }

/// What a forward's listener speaks: a plain TCP byte pipe with a fixed
/// destination, or a SOCKS5 proxy where every connection picks its own
/// destination.
class ActivePortForward {
  const ActivePortForward({
    required this.id,
    required this.serverId,
    required this.serverName,
    required this.direction,
    required this.kind,
    required this.bindHost,
    required this.bindPort,
    this.targetHost = '',
    this.targetPort = 0,
    this.owner = PortForwardOwner.user,
  });

  ActivePortForward copyWith({
    String? bindHost,
    int? bindPort,
    String? targetHost,
    int? targetPort,
  }) => ActivePortForward(
    id: id,
    serverId: serverId,
    serverName: serverName,
    direction: direction,
    kind: kind,
    bindHost: bindHost ?? this.bindHost,
    bindPort: bindPort ?? this.bindPort,
    targetHost: targetHost ?? this.targetHost,
    targetPort: targetPort ?? this.targetPort,
    owner: owner,
  );

  final String id;
  final int serverId;
  final String serverName;
  final PortForwardDirection direction;
  final PortForwardKind kind;
  final String bindHost;
  final int bindPort;

  /// Destination for TCP forwards. Unused for SOCKS5, where the client
  /// chooses the destination per connection.
  final String targetHost;
  final int targetPort;
  final PortForwardOwner owner;

  bool get isManaged => owner != PortForwardOwner.user;

  String get directionLabel => switch (direction) {
    PortForwardDirection.local => 'portForwardingLocal'.tr(),
    PortForwardDirection.remote => 'portForwardingRemote'.tr(),
  };

  String get kindLabel => switch (kind) {
    PortForwardKind.tcp => 'portForwardingTcp'.tr(),
    PortForwardKind.socks5 => 'portForwardingSocks5'.tr(),
  };

  /// The tile title: the direction for plain TCP forwards, the kind for
  /// SOCKS5 (which has no direction).
  String get label => kind == PortForwardKind.tcp ? directionLabel : kindLabel;

  String get summary => switch (kind) {
    PortForwardKind.tcp => '$bindHost:$bindPort → $targetHost:$targetPort',
    PortForwardKind.socks5 => 'socks5://$bindHost:$bindPort',
  };
}
