import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/server_models.dart';

void main() {
  test('stores and updates the server card network ping', () {
    final session = SshSessionInfo(
      serverId: 1,
      serverName: 'example',
      connectedAt: DateTime(2026),
      status: SessionStatus.connected,
      networkLatency: const Duration(milliseconds: 45),
    );

    final updated = session.copyWith(
      networkLatency: const Duration(milliseconds: 47),
    );

    expect(updated.networkLatency, const Duration(milliseconds: 47));
  });
}
