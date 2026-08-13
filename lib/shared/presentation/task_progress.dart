import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/routing/app_router.dart';

enum TaskProgressStatus {
  queued,
  inProgress,
  paused,
  completed,
  failed,
  canceled,
}

class AppTaskProgress {
  const AppTaskProgress({
    required this.id,
    required this.title,
    required this.totalBytes,
    required this.transferredBytes,
    required this.speedBytesPerSecond,
    required this.canPause,
    required this.canCancel,
    required this.status,
  });

  final String id;
  final String title;
  final int? totalBytes;
  final int transferredBytes;
  final double? speedBytesPerSecond;
  final bool canPause;
  final bool canCancel;
  final TaskProgressStatus status;

  bool get isActive =>
      status == TaskProgressStatus.queued ||
      status == TaskProgressStatus.inProgress ||
      status == TaskProgressStatus.paused;

  bool get isQueued => status == TaskProgressStatus.queued;

  bool get isPaused => status == TaskProgressStatus.paused;

  double? get progress => totalBytes == null
      ? null
      : (transferredBytes / totalBytes!).clamp(0, 1).toDouble();

  Duration? get eta {
    final total = totalBytes;
    final speed = speedBytesPerSecond;
    if (total == null || speed == null || speed <= 0) return null;
    final remaining = total - transferredBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / speed).ceil());
  }

  AppTaskProgress copyWith({
    TaskProgressStatus? status,
    int? transferredBytes,
    double? speedBytesPerSecond,
    bool? canPause,
    bool? canCancel,
  }) => AppTaskProgress(
    id: id,
    title: title,
    totalBytes: totalBytes,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
    canPause: canPause ?? this.canPause,
    canCancel: canCancel ?? this.canCancel,
    status: status ?? this.status,
  );
}

final taskProgressProvider =
    NotifierProvider<TaskProgressNotifier, List<AppTaskProgress>>(
      TaskProgressNotifier.new,
    );

class TaskProgressNotifier extends Notifier<List<AppTaskProgress>> {
  final _handlers = <String, _TaskControlHandlers>{};
  final _samples = <String, _TaskProgressSample>{};
  final _pendingRemovalTimers = <String, Timer>{};

  @override
  List<AppTaskProgress> build() => const [];

  String start({
    required String title,
    int? totalBytes,
    TaskProgressStatus status = TaskProgressStatus.inProgress,
    FutureOr<void> Function()? onPause,
    FutureOr<void> Function()? onResume,
    FutureOr<void> Function()? onCancel,
  }) {
    final id = 'task-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    _handlers[id] = _TaskControlHandlers(
      onPause: onPause,
      onResume: onResume,
      onCancel: onCancel,
    );
    _samples[id] = _TaskProgressSample(bytes: 0, timestamp: now);
    state = [
      ...state,
      AppTaskProgress(
        id: id,
        title: title,
        totalBytes: totalBytes,
        transferredBytes: 0,
        speedBytesPerSecond: null,
        canPause:
            status == TaskProgressStatus.inProgress &&
            onPause != null &&
            onResume != null,
        canCancel: onCancel != null,
        status: status,
      ),
    ];
    return id;
  }

  void startRunning(
    String id, {
    FutureOr<void> Function()? onPause,
    FutureOr<void> Function()? onResume,
    FutureOr<void> Function()? onCancel,
  }) {
    _handlers[id] = _TaskControlHandlers(
      onPause: onPause,
      onResume: onResume,
      onCancel: onCancel,
    );
    _samples[id] = _TaskProgressSample(
      bytes:
          state.where((task) => task.id == id).firstOrNull?.transferredBytes ??
          0,
      timestamp: DateTime.now(),
    );
    state = state.map((task) {
      if (task.id != id || !task.isActive) return task;
      return task.copyWith(
        status: TaskProgressStatus.inProgress,
        canPause: onPause != null && onResume != null,
        canCancel: onCancel != null,
      );
    }).toList();
  }

  void update(String id, int transferredBytes) {
    final now = DateTime.now();
    final previous = _samples[id];
    var speed = previous == null
        ? null
        : _speed(previous, transferredBytes, now);
    _samples[id] = _TaskProgressSample(bytes: transferredBytes, timestamp: now);
    state = state.map((task) {
      if (task.id != id || !task.isActive) return task;
      speed ??= task.speedBytesPerSecond;
      return task.copyWith(
        transferredBytes: transferredBytes,
        speedBytesPerSecond: speed,
      );
    }).toList();
  }

  Future<void> pause(String id) async {
    final handler = _handlers[id]?.onPause;
    if (handler == null) return;
    state = state.map((task) {
      if (task.id != id || !task.isActive) return task;
      return task.copyWith(status: TaskProgressStatus.paused);
    }).toList();
    await handler();
  }

  Future<void> resume(String id) async {
    final handler = _handlers[id]?.onResume;
    if (handler == null) return;
    await handler();
    _samples[id] = _TaskProgressSample(
      bytes:
          state.where((task) => task.id == id).firstOrNull?.transferredBytes ??
          0,
      timestamp: DateTime.now(),
    );
    state = state.map((task) {
      if (task.id != id || task.status != TaskProgressStatus.paused) {
        return task;
      }
      return task.copyWith(status: TaskProgressStatus.inProgress);
    }).toList();
  }

  Future<void> cancel(String id) async {
    final handler = _handlers[id]?.onCancel;
    if (handler == null) return;
    await handler();
    _finish(id, TaskProgressStatus.canceled);
  }

  void complete(String id) => _finish(id, TaskProgressStatus.completed);

  void fail(String id) => _finish(id, TaskProgressStatus.failed);

  void _finish(String id, TaskProgressStatus status) {
    final task = state.where((task) => task.id == id).firstOrNull;
    if (task == null ||
        task.status == TaskProgressStatus.completed ||
        task.status == TaskProgressStatus.failed ||
        task.status == TaskProgressStatus.canceled) {
      return;
    }
    _handlers.remove(id);
    _samples.remove(id);
    _pendingRemovalTimers.remove(id)?.cancel();
    state = state.map((task) {
      if (task.id != id) return task;
      return task.copyWith(
        status: status,
        transferredBytes: status == TaskProgressStatus.completed
            ? (task.totalBytes ?? task.transferredBytes)
            : task.transferredBytes,
        canPause: false,
        canCancel: false,
      );
    }).toList();
    _pendingRemovalTimers[id] = Timer(const Duration(seconds: 3), () {
      _pendingRemovalTimers.remove(id);
      if (ref.mounted) {
        state = state.where((task) => task.id != id).toList();
      }
    });
  }

  double? _speed(
    _TaskProgressSample previous,
    int transferredBytes,
    DateTime now,
  ) {
    final elapsedMs = now.difference(previous.timestamp).inMilliseconds;
    final delta = transferredBytes - previous.bytes;
    if (elapsedMs <= 0 || delta <= 0) return null;
    return delta * 1000 / elapsedMs;
  }
}

class _TaskControlHandlers {
  const _TaskControlHandlers({this.onPause, this.onResume, this.onCancel});

  final FutureOr<void> Function()? onPause;
  final FutureOr<void> Function()? onResume;
  final FutureOr<void> Function()? onCancel;
}

class _TaskProgressSample {
  const _TaskProgressSample({required this.bytes, required this.timestamp});

  final int bytes;
  final DateTime timestamp;
}

class TaskProgressBar extends ConsumerWidget {
  const TaskProgressBar({super.key});

  static const _showDuration = Duration(milliseconds: 220);
  static const _hideDuration = Duration(milliseconds: 180);
  static const _barHeight = 36.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskProgressProvider);
    final activeTasks = tasks.where((task) => task.isActive).toList();
    final visibleTasks = activeTasks.isEmpty ? tasks : activeTasks;
    final primaryTask = visibleTasks.isEmpty
        ? null
        : visibleTasks.where((task) => !task.isQueued).firstOrNull ??
              visibleTasks.first;
    final progress = primaryTask?.progress;
    final hasTask = primaryTask != null;

    return AnimatedSwitcher(
      duration: _showDuration,
      reverseDuration: _hideDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipRect(
          child: SizeTransition(
            sizeFactor: curved,
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            ),
          ),
        );
      },
      child: hasTask
          ? SizedBox(
              key: const ValueKey('task-progress-visible'),
              height: _barHeight,
              width: double.infinity,
              child: _TaskProgressBarContent(
                task: primaryTask,
                progress: progress,
              ),
            )
          : const SizedBox.shrink(key: ValueKey('task-progress-hidden')),
    );
  }
}

class _TaskProgressBarContent extends StatelessWidget {
  const _TaskProgressBarContent({required this.task, required this.progress});

  final AppTaskProgress task;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _taskLabel(task);
    final color = _taskColor(task, colorScheme);
    final icon = _taskIcon(task);
    final details = _transferDetails(task);
    final trackColor = colorScheme.surfaceContainerHighest;
    final fillColor = color.withValues(alpha: 0.18);

    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => _showTaskProgressSheet(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Soft determinate fill behind the content.
              if (progress != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * progress!.clamp(0.0, 1.0),
                        height: double.infinity,
                        color: fillColor,
                      ),
                    );
                  },
                )
              else if (task.status == TaskProgressStatus.inProgress ||
                  task.status == TaskProgressStatus.queued)
                LinearProgressIndicator(
                  minHeight: TaskProgressBar._barHeight,
                  color: fillColor,
                  backgroundColor: Colors.transparent,
                ),
              // Thin accent track along the top edge for hierarchy.
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 2,
                  width: double.infinity,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    color: color,
                    backgroundColor: trackColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (details != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                details,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${(progress! * 100).round()}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    _TaskProgressActions(task: task),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskProgressActions extends ConsumerWidget {
  const _TaskProgressActions({required this.task});

  final AppTaskProgress task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!task.isActive) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.canPause) ...[
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            tooltip: task.isPaused
                ? 'taskProgressResume'.tr()
                : 'taskProgressPause'.tr(),
            iconSize: 18,
            onPressed: () {
              final notifier = ref.read(taskProgressProvider.notifier);
              if (task.isPaused) {
                unawaited(notifier.resume(task.id));
              } else {
                unawaited(notifier.pause(task.id));
              }
            },
            icon: Icon(task.isPaused ? Symbols.play_arrow : Symbols.pause),
          ),
        ],
        if (task.canCancel) ...[
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            tooltip: 'taskProgressCancel'.tr(),
            iconSize: 18,
            onPressed: () {
              unawaited(
                ref.read(taskProgressProvider.notifier).cancel(task.id),
              );
            },
            icon: const Icon(Symbols.close),
          ),
        ],
      ],
    );
  }
}

class _TaskProgressSheet extends ConsumerWidget {
  const _TaskProgressSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskProgressProvider);
    final activeCount = tasks.where((task) => task.isActive).length;
    final title = activeCount == 0
        ? 'taskProgressTransfers'.tr()
        : 'taskProgressTransfersCount'.tr(args: ['$activeCount']);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.56,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Symbols.sync, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Symbols.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'taskProgressNoTransfers'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) =>
                          _TaskProgressListTile(task: tasks[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskProgressListTile extends StatelessWidget {
  const _TaskProgressListTile({required this.task});

  final AppTaskProgress task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = task.progress;
    final details = _transferDetails(task, includeFinished: true);
    final color = _taskColor(task, colorScheme);

    return ListTile(
      leading: Icon(_taskIcon(task), color: color),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _taskStatusText(task),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (details != null) ...[
            const SizedBox(height: 2),
            Text(
              details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: color,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress != null)
            Text(
              '${(progress * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          _TaskProgressActions(task: task),
        ],
      ),
    );
  }
}

void _showTaskProgressSheet(BuildContext context) {
  // TaskProgressBar lives in MaidKitWindowScaffold (outside the router
  // Navigator), so prefer the app navigator key when available.
  final navigatorContext =
      maidKitNavigatorKey.currentContext ??
      (Navigator.maybeOf(context) != null ? context : null);
  if (navigatorContext == null) return;

  showModalBottomSheet<void>(
    context: navigatorContext,
    showDragHandle: false,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _TaskProgressSheet(),
  );
}

String _taskLabel(AppTaskProgress task) {
  return switch (task.status) {
    TaskProgressStatus.queued => 'taskProgressQueued'.tr(args: [task.title]),
    TaskProgressStatus.inProgress => task.title,
    TaskProgressStatus.paused => 'taskProgressPaused'.tr(args: [task.title]),
    TaskProgressStatus.completed => 'taskProgressComplete'.tr(
      args: [task.title],
    ),
    TaskProgressStatus.failed => 'taskProgressFailed'.tr(args: [task.title]),
    TaskProgressStatus.canceled => 'taskProgressCanceled'.tr(
      args: [task.title],
    ),
  };
}

String _taskStatusText(AppTaskProgress task) {
  return switch (task.status) {
    TaskProgressStatus.queued => 'taskProgressStatusQueued'.tr(),
    TaskProgressStatus.inProgress => 'taskProgressStatusRunning'.tr(),
    TaskProgressStatus.paused => 'taskProgressStatusPaused'.tr(),
    TaskProgressStatus.completed => 'taskProgressStatusCompleted'.tr(),
    TaskProgressStatus.failed => 'taskProgressStatusFailed'.tr(),
    TaskProgressStatus.canceled => 'taskProgressStatusCanceled'.tr(),
  };
}

Color _taskColor(AppTaskProgress task, ColorScheme colorScheme) {
  return switch (task.status) {
    TaskProgressStatus.queued => colorScheme.secondary,
    TaskProgressStatus.inProgress => colorScheme.primary,
    TaskProgressStatus.paused => colorScheme.secondary,
    TaskProgressStatus.completed => colorScheme.primary,
    TaskProgressStatus.failed => colorScheme.error,
    TaskProgressStatus.canceled => colorScheme.onSurfaceVariant,
  };
}

IconData _taskIcon(AppTaskProgress task) {
  return switch (task.status) {
    TaskProgressStatus.queued => Symbols.schedule,
    TaskProgressStatus.inProgress => Symbols.sync,
    TaskProgressStatus.paused => Symbols.pause_circle,
    TaskProgressStatus.completed => Symbols.check_circle,
    TaskProgressStatus.failed => Symbols.error,
    TaskProgressStatus.canceled => Symbols.cancel,
  };
}

String? _transferDetails(AppTaskProgress task, {bool includeFinished = false}) {
  if (!task.isActive && !includeFinished) return null;
  final showLiveDetails = task.isActive && !task.isPaused && !task.isQueued;
  final speed = task.speedBytesPerSecond == null
      ? null
      : _formatBytes(task.speedBytesPerSecond!.round());
  final eta = task.eta == null ? null : _formatDuration(task.eta!);
  final size = task.totalBytes == null
      ? _formatBytes(task.transferredBytes)
      : '${_formatBytes(task.transferredBytes)} / ${_formatBytes(task.totalBytes!)}';
  final parts = [
    size,
    if (speed != null && showLiveDetails) '$speed/s',
    if (eta != null && showLiveDetails) 'ETA $eta',
  ];
  return parts.join(' · ');
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final precision = value >= 10 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds <= 0) return 'now';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
