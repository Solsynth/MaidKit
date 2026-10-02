import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';

SshSessionInfo _session(int serverId, {SessionStatus? status}) =>
    SshSessionInfo(
      serverId: serverId,
      serverName: 'server-$serverId',
      connectedAt: DateTime.utc(2026),
      status: status ?? SessionStatus.connected,
    );

void main() {
  test('a plainly merged stream is what drops the other transports', () async {
    // The shape this helper replaces: StreamGroup forwards each event as it
    // arrives, so the event carries one transport's list and nothing else.
    final ssh = StreamController<List<SshSessionInfo>>.broadcast();
    final maidCafe = StreamController<List<SshSessionInfo>>.broadcast();
    addTearDown(() {
      unawaited(ssh.close());
      unawaited(maidCafe.close());
    });

    final merged = StreamGroup.merge([ssh.stream, maidCafe.stream]);
    final emitted = <List<SshSessionInfo>>[];
    final subscription = merged.listen(emitted.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    maidCafe.add([_session(1)]);
    await Future<void>.delayed(Duration.zero);

    // The SSH session that was there a moment ago is gone from the event.
    expect(emitted.last.map((session) => session.serverId), isNot(contains(2)));
  });

  test(
    'an event from one transport keeps the other transports\' sessions',
    () async {
      // Every transport emits its own complete list, so a merged event that only
      // forwards the emitting list drops the others: opening a daemon terminal
      // would make every SSH session read as disconnected across the app.
      final ssh = StreamController<List<SshSessionInfo>>.broadcast();
      final serial = StreamController<List<SshSessionInfo>>.broadcast();
      final maidCafe = StreamController<List<SshSessionInfo>>.broadcast();
      addTearDown(() {
        unawaited(ssh.close());
        unawaited(serial.close());
        unawaited(maidCafe.close());
      });

      final merged = mergeSessionStreams(
        sources: [ssh.stream, serial.stream, maidCafe.stream],
        initial: [
          [_session(1), _session(2)],
          const [],
          const [],
        ],
      );
      final emitted = <List<SshSessionInfo>>[];
      final subscription = merged.listen(emitted.add);
      addTearDown(subscription.cancel);

      // A daemon terminal opens on server 1 — the SSH sessions survive.
      maidCafe.add([_session(1)]);
      await Future<void>.delayed(Duration.zero);

      expect(
        emitted.last.map((session) => session.serverId),
        containsAll([1, 2]),
      );

      // A serial terminal opens too: all three transports stay visible.
      serial.add([_session(3)]);
      await Future<void>.delayed(Duration.zero);
      expect(
        emitted.last.map((session) => session.serverId),
        containsAll([1, 2, 3]),
      );

      // An SSH session closing still removes only that one.
      ssh.add([_session(2, status: SessionStatus.closed)]);
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last.length, 3);
    },
  );
}
