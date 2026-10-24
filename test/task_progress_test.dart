import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/shared/presentation/task_progress.dart';

void main() {
  late ProviderContainer container;
  late TaskProgressNotifier tasks;

  setUp(() {
    container = ProviderContainer();
    tasks = container.read(taskProgressProvider.notifier);
  });

  tearDown(() => container.dispose());

  /// A task that parks until the test releases it, so the queue stays busy.
  ({Future<void> Function() release, AppTaskRequest request}) pending(
    String title, {
    int? totalBytes,
    List<String>? log,
  }) {
    final gate = Completer<void>();
    return (
      release: () async {
        if (!gate.isCompleted) gate.complete();
      },
      request: AppTaskRequest(
        title: title,
        totalBytes: totalBytes,
        action: (control, report) async {
          log?.add('start:$title');
          await gate.future;
          control.throwIfCancelled();
          log?.add('end:$title');
        },
      ),
    );
  }

  test('runs one task at a time, in submission order', () async {
    final log = <String>[];
    final first = pending('a', log: log);
    final second = pending('b', log: log);

    tasks.run(first.request);
    tasks.run(second.request);
    await pumpEventQueue();
    expect(log, ['start:a'], reason: 'b waits for a');

    await first.release();
    await pumpEventQueue();
    expect(log, ['start:a', 'end:a', 'start:b']);

    await second.release();
    await pumpEventQueue();
    expect(log, ['start:a', 'end:a', 'start:b', 'end:b']);
  });

  test('a queued task starts queued and reports its size', () {
    final gate = pending('a');
    final running = tasks.run(gate.request, pauseable: false);
    final queued = tasks.run(pending('b').request);

    // Synchronous read: the drain has not run yet, so both are still pending.
    final byId = {
      for (final task in container.read(taskProgressProvider)) task.id: task,
    };
    expect(byId[running]!.status, TaskProgressStatus.queued);
    expect(byId[queued]!.status, TaskProgressStatus.queued);
    expect(byId[queued]!.canPause, isFalse, reason: 'nothing to hold');
  });

  test(
    'pause stops the action until resume, cancel settles as cancelled',
    () async {
      final log = <String>[];
      final gate = pending('a', log: log);
      final id = tasks.run(gate.request);
      await pumpEventQueue();

      await tasks.pause(id);
      expect(
        container.read(taskProgressProvider).single.status,
        TaskProgressStatus.paused,
      );

      await tasks.resume(id);
      expect(
        container.read(taskProgressProvider).single.status,
        TaskProgressStatus.inProgress,
      );

      await tasks.cancel(id);
      expect(
        container.read(taskProgressProvider).single.status,
        TaskProgressStatus.canceled,
      );

      await gate.release();
      await pumpEventQueue();
      expect(log, ['start:a'], reason: 'a cancelled task runs no completion');
    },
  );

  test('cancelling a queued task never starts it, yet finishes it', () async {
    final log = <String>[];
    final first = pending('a', log: log);
    final second = pending('b', log: log);
    tasks.run(first.request);
    final queued = tasks.run(
      second.request,
      onFinish: () => log.add('finish:b'),
    );

    await tasks.cancel(queued);
    await first.release();
    await pumpEventQueue();
    expect(log, ['start:a', 'end:a', 'finish:b']);
  });

  test('a skipped task completes without running onSuccess', () async {
    var succeeded = false;
    final id = tasks.run(
      AppTaskRequest(
        title: 'skip',
        action: (control, report) async => throw const TaskSkipped(),
      ),
      onSuccess: () => succeeded = true,
    );
    await pumpEventQueue();

    final task = container.read(taskProgressProvider).single;
    expect(task.id, id);
    expect(task.status, TaskProgressStatus.completed);
    expect(succeeded, isFalse);
  });

  test('a failing action fails the task and reports the error', () async {
    Object? reported;
    tasks.run(
      AppTaskRequest(
        title: 'boom',
        action: (control, report) async => throw StateError('boom'),
      ),
      onError: (error) => reported = error,
    );
    await pumpEventQueue();

    expect(
      container.read(taskProgressProvider).single.status,
      TaskProgressStatus.failed,
    );
    expect(reported, isA<StateError>());
  });

  test('completion fills the bar and drops the task after a moment', () async {
    tasks.run(
      AppTaskRequest(
        title: 'done',
        totalBytes: 100,
        action: (control, report) async => report(40),
      ),
    );
    await pumpEventQueue();

    final task = container.read(taskProgressProvider).single;
    expect(task.status, TaskProgressStatus.completed);
    expect(task.transferredBytes, 100, reason: 'a completed task is full');

    await Future<void>.delayed(const Duration(seconds: 4));
    expect(container.read(taskProgressProvider), isEmpty);
  });

  test('dispose cancels work that is still queued', () async {
    final log = <String>[];
    final first = pending('a', log: log);
    final second = pending('b', log: log);
    tasks.run(first.request);
    tasks.run(second.request);
    await pumpEventQueue();

    container.dispose();
    await first.release();
    await pumpEventQueue();
    expect(log, ['start:a'], reason: 'b never starts after disposal');

    // tearDown disposes again; a second dispose is a no-op on an owned ref.
    container = ProviderContainer();
    tasks = container.read(taskProgressProvider.notifier);
  });
}
