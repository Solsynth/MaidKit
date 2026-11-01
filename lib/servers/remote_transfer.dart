import 'dart:async';

import 'package:maid_kit/shared/presentation/task_progress.dart';

import 'remote_file_system.dart';

/// How long a remote read may produce nothing before the transfer gives up.
///
/// SFTP requests carry no timeout of their own: a peer that stops answering
/// parks a read forever, which freezes the progress bar and — because the task
/// queue runs one task at a time — leaves every later transfer queued behind
/// it. A live link delivers a 64 KB chunk far inside this window even on a
/// slow mobile connection.
const transferStallTimeout = Duration(seconds: 60);

/// How long a transport may take to abandon a read before the transfer stops
/// waiting for it.
const _abandonTimeout = Duration(seconds: 5);

/// Sends [file]'s chunks to [onChunk] until it ends, [control] is cancelled, or
/// no chunk arrives within [stallTimeout].
///
/// Racing cancellation against the read is what makes cancel real: the
/// transport has nothing to check between chunks, so [abandon] tears it down
/// and the parked request fails instead of waiting for a reply that will never
/// come. [abandon] is only called when the read is given up — a finished
/// transfer leaves its transport usable — and it must close the transport, not
/// merely mark it, because closing is what completes the pending request.
///
/// Throws [RemoteTransferStalled] when the peer goes quiet and [TaskCancelled]
/// when [control] is cancelled.
Future<void> pumpRemoteFile(
  RemoteFile file,
  TaskControl? control, {
  required Future<void> Function() abandon,
  required Future<void> Function(List<int> chunk) onChunk,
  int? length,
  Duration stallTimeout = transferStallTimeout,
}) async {
  final iterator = StreamIterator<List<int>>(
    file.read(length: length, chunkSize: 64 * 1024, maxPendingRequests: 4),
  );
  // One completer and one armed timer for the whole transfer: a fresh
  // `Future.delayed` per chunk would leave a 60 s timer behind for every 64 KB
  // of a large file.
  final interrupted = Completer<_ReadOutcome>();
  var reading = true;
  Timer? stallTimer;

  void interrupt(_ReadOutcome outcome) {
    if (interrupted.isCompleted || !reading) return;
    interrupted.complete(outcome);
  }

  void armStallTimer() {
    stallTimer?.cancel();
    stallTimer = Timer(stallTimeout, () => interrupt(const _Stalled()));
  }

  // A caller with no queue task in hand still gets the stall bound; only the
  // cancel race goes away, because nothing can cancel it.
  unawaited(control?.cancelled.then((_) => interrupt(const _Cancelled())));
  try {
    while (true) {
      armStallTimer();
      final outcome = await Future.any<_ReadOutcome>([
        iterator.moveNext().then<_ReadOutcome>(
          (hasChunk) => hasChunk ? const _ChunkReady() : const _EndOfFile(),
        ),
        interrupted.future,
      ]);
      stallTimer?.cancel();
      switch (outcome) {
        case _ChunkReady():
          // A cancel that raced this chunk still wins, so no bytes of a
          // cancelled transfer are written anywhere.
          control?.throwIfCancelled();
          await onChunk(iterator.current);
        case _EndOfFile():
          return;
        case _Stalled():
          await _abandonRead(abandon);
          throw RemoteTransferStalled(
            'no data arrived for ${stallTimeout.inSeconds} seconds',
          );
        case _Cancelled():
          await _abandonRead(abandon);
          throw const TaskCancelled();
      }
    }
  } finally {
    reading = false;
    stallTimer?.cancel();
    // A read that ended normally costs nothing to cancel; one that is still
    // parked was already abandoned above, which is what makes this return.
    try {
      await iterator.cancel().timeout(_abandonTimeout);
    } catch (_) {}
  }
}

/// Fails whatever request the pump is parked on.
///
/// This has to run before the iterator is cancelled: tearing down the transport
/// is the only thing that completes a read the peer stopped answering, and
/// `StreamIterator.cancel` waits for that read. The wait is bounded, so a
/// transport that ignores the close cannot hang the transfer either.
Future<void> _abandonRead(Future<void> Function() abandon) async {
  try {
    await abandon().timeout(_abandonTimeout);
  } catch (_) {
    // The transport is being thrown away regardless.
  }
}

/// Outcomes the read pump races against a chunk arriving. Private marker types
/// rather than enum values so a chunk payload can never be mistaken for one.
sealed class _ReadOutcome {
  const _ReadOutcome();
}

class _ChunkReady extends _ReadOutcome {
  const _ChunkReady();
}

class _EndOfFile extends _ReadOutcome {
  const _EndOfFile();
}

class _Stalled extends _ReadOutcome {
  const _Stalled();
}

class _Cancelled extends _ReadOutcome {
  const _Cancelled();
}
