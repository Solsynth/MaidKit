import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';

void main() {
  const base = ActivePortForward(
    id: 'forward-1',
    serverId: 1,
    serverName: 'server',
    direction: PortForwardDirection.local,
    kind: PortForwardKind.tcp,
    bindHost: '127.0.0.1',
    bindPort: 43123,
    targetHost: '127.0.0.1',
    targetPort: 8747,
  );

  test('user forwards remain manually managed by default', () {
    expect(base.owner, PortForwardOwner.user);
    expect(base.isManaged, isFalse);
  });

  test('managed ownership survives bound-port updates', () {
    const managed = ActivePortForward(
      id: 'forward-2',
      serverId: 1,
      serverName: 'server',
      direction: PortForwardDirection.local,
      kind: PortForwardKind.tcp,
      bindHost: '127.0.0.1',
      bindPort: 43124,
      targetHost: '127.0.0.1',
      targetPort: 8747,
      owner: PortForwardOwner.maidCafe,
    );

    final updated = managed.copyWith(bindPort: 43125);
    expect(updated.owner, PortForwardOwner.maidCafe);
    expect(updated.isManaged, isTrue);
    expect(updated.bindPort, 43125);
  });
}
