import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/remote_file_system.dart';
import 'package:maid_kit/servers/remote_transfer.dart';
import 'package:maid_kit/shared/presentation/task_progress.dart';

/// A read handle that emits [chunks] and then parks forever, standing in for a
/// server that stops answering mid-transfer.
class _StalledFile implements RemoteFile {
  _StalledFile({this.chunks = const [], this.parkAfterChunks});

  final List<List<int>> chunks;

  /// When set, the stream parks forever after emitting this many chunks;
  /// otherwise it ends after [chunks].
  final int? parkAfterChunks;

  var closeCalls = 0;

  @override
  Stream<List<int>> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 64 * 1024,
    int maxPendingRequests = 4,
  }) async* {
    final parkAt = parkAfterChunks ?? chunks.length;
    for (var i = 0; i < parkAt; i++) {
      yield chunks[i];
    }
    if (parkAfterChunks == null) return;
    // The peer never replies again; only abandoning the transport ends this.
    await Completer<void>().future;
  }

  @override
  Future<List<int>> readBytes() async => [
    for (final chunk in chunks) ...chunk,
  ];

  @override
  Future<void> writeBytes(List<int> data, {int offset = 0}) async {}

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

void main() {
  group('pumpRemoteFile', () {
    test('delivers every chunk and leaves the transport alone', () async {
      final file = _StalledFile(
        chunks: [
          [1, 2],
          [3],
        ],
      );
      var abandoned = false;
      final received = <int>[];

      await pumpRemoteFile(
        file,
        null,
        abandon: () async => abandoned = true,
        onChunk: (chunk) async => received.addAll(chunk),
      );

      expect(received, [1, 2, 3]);
      expect(abandoned, isFalse, reason: 'a finished read is not a failure');
    });

    test('fails with RemoteTransferStalled when nothing arrives', () async {
      final file = _StalledFile(chunks: [
        [1],
      ], parkAfterChunks: 1);
      var abandoned = false;

      await expectLater(
        pumpRemoteFile(
          file,
          null,
          stallTimeout: const Duration(milliseconds: 50),
          abandon: () async => abandoned = true,
          onChunk: (_) async {},
        ),
        throwsA(isA<RemoteTransferStalled>()),
      );
      expect(abandoned, isTrue, reason: 'the parked request had to be failed');
    });

    test('cancel aborts the transport instead of waiting for a chunk', () async {
      final file = _StalledFile(chunks: [
        [1],
      ], parkAfterChunks: 1);
      final control = TaskControl();
      var abandoned = false;
      final received = <int>[];

      final pump = pumpRemoteFile(
        file,
        control,
        abandon: () async {
          abandoned = true;
          // What a real transport does: fails the pending read, unparking it.
          file.close();
        },
        onChunk: (chunk) async => received.addAll(chunk),
      );

      // Let the first chunk land, then cancel while the read is parked.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      control.cancel();

      await expectLater(pump, throwsA(isA<TaskCancelled>()));
      expect(received, [1]);
      expect(abandoned, isTrue);
      expect(file.closeCalls, 1, reason: 'the transport was torn down once');
    });
  });

  group('TaskProgressNotifier', () {
    late ProviderContainer container;
    late TaskProgressNotifier tasks;

    setUp(() {
      container = ProviderContainer();
      tasks = container.read(taskProgressProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('a cancelled task that never unwinds releases the queue', () async {
      final log = <String>[];
      final started = Completer<void>();
      final id = tasks.run(
        AppTaskRequest(
          title: 'stuck',
          action: (control, report) async {
            log.add('start:stuck');
            started.complete();
            // Parks forever: no checkpoint is ever reached, so only the queue's
            // own cancellation race can settle this task.
            await Completer<void>().future;
          },
        ),
      );
      await started.future;

      final next = tasks.run(
        AppTaskRequest(
          title: 'next',
          action: (control, report) async => log.add('start:next'),
        ),
      );
      await pumpEventQueue();
      expect(log, ['start:stuck'], reason: 'the queue runs one task at a time');

      await tasks.cancel(id);
      await pumpEventQueue();

      final byId = {
        for (final task in container.read(taskProgressProvider)) task.id: task,
      };
      expect(byId[id]!.status, TaskProgressStatus.canceled);
      expect(byId[next]!.status, TaskProgressStatus.completed);
      expect(log.last, 'start:next', reason: 'the stuck task released the slot');
    });
  });
}
