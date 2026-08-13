import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';
import 'ansi_log_view.dart';
import 'cli_output_progress.dart';

enum DeploySessionStatus { running, succeeded, failed, cancelled }

class DeploySession {
  const DeploySession({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.command,
    required this.log,
    required this.status,
    required this.modalVisible,
    required this.canTerminate,
    this.error,
    this.progress,
    this.progressDetail,
  });

  final String id;
  final String title;
  final String subtitle;
  final String command;
  final String log;
  final DeploySessionStatus status;
  final bool modalVisible;
  final bool canTerminate;
  final String? error;

  /// Parsed CLI progress in `0..1` when available (e.g. docker pull layers).
  final double? progress;

  /// Short label such as `3 / 8 layers`.
  final String? progressDetail;

  bool get isRunning => status == DeploySessionStatus.running;

  DeploySession copyWith({
    String? log,
    DeploySessionStatus? status,
    bool? modalVisible,
    bool? canTerminate,
    String? error,
    double? progress,
    String? progressDetail,
    bool clearProgress = false,
  }) => DeploySession(
    id: id,
    title: title,
    subtitle: subtitle,
    command: command,
    log: log ?? this.log,
    status: status ?? this.status,
    modalVisible: modalVisible ?? this.modalVisible,
    canTerminate: canTerminate ?? this.canTerminate,
    error: error ?? this.error,
    progress: clearProgress ? progress : (progress ?? this.progress),
    progressDetail: clearProgress
        ? progressDetail
        : (progressDetail ?? this.progressDetail),
  );
}

final deploySessionsProvider =
    NotifierProvider<DeploySessionsNotifier, List<DeploySession>>(
      DeploySessionsNotifier.new,
    );

class DeploySessionsNotifier extends Notifier<List<DeploySession>> {
  final Map<String, CliOutputProgressTracker> _progressTrackers = {};
  final Map<String, FutureOr<void> Function()> _cancelHandlers = {};

  @override
  List<DeploySession> build() => const [];

  String start({
    required String title,
    required String subtitle,
    required String command,
    FutureOr<void> Function()? onCancel,
  }) {
    final id = 'deploy-${DateTime.now().microsecondsSinceEpoch}';
    _progressTrackers[id] = CliOutputProgressTracker();
    if (onCancel != null) _cancelHandlers[id] = onCancel;
    state = [
      ...state,
      DeploySession(
        id: id,
        title: title,
        subtitle: subtitle,
        command: command,
        log: '',
        status: DeploySessionStatus.running,
        modalVisible: true,
        canTerminate: onCancel != null,
      ),
    ];
    return id;
  }

  void append(String id, String chunk) {
    if (chunk.isEmpty) return;
    final tracker = _progressTrackers.putIfAbsent(
      id,
      CliOutputProgressTracker.new,
    );
    tracker.ingest(chunk);
    state = [
      for (final session in state)
        if (session.id == id)
          session.copyWith(
            log: '${session.log}$chunk',
            progress: tracker.progress,
            progressDetail: tracker.detail,
            clearProgress: true,
          )
        else
          session,
    ];
  }

  void complete(String id, {required bool success, String? error}) {
    if (isCancelled(id)) return;
    // Command has exited — treat progress as complete regardless of how much
    // of the CLI stream we managed to parse (layers may still show <100%).
    _progressTrackers[id]?.markFinished();
    state = [
      for (final session in state)
        if (session.id == id)
          session.copyWith(
            status: success
                ? DeploySessionStatus.succeeded
                : DeploySessionStatus.failed,
            error: error,
            progress: 1,
            progressDetail: success ? '100%' : session.progressDetail,
            clearProgress: true,
          )
        else
          session,
    ];
  }

  bool isCancelled(String id) => state.any(
    (session) =>
        session.id == id && session.status == DeploySessionStatus.cancelled,
  );

  Future<void> terminate(String id) async {
    final session = state.where((item) => item.id == id).firstOrNull;
    if (session == null || !session.isRunning) return;
    append(id, '\nTask terminated by user.\n');
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            status: DeploySessionStatus.cancelled,
            error: 'Task terminated by user.',
            clearProgress: true,
          )
        else
          item,
    ];
    await _cancelHandlers[id]?.call();
  }

  void setModalVisible(String id, bool visible) {
    state = [
      for (final session in state)
        if (session.id == id)
          session.copyWith(modalVisible: visible)
        else
          session,
    ];
  }

  void setAllModalVisible(bool visible) {
    state = [
      for (final session in state) session.copyWith(modalVisible: visible),
    ];
  }

  void remove(String id) {
    _progressTrackers.remove(id);
    _cancelHandlers.remove(id);
    state = state.where((session) => session.id != id).toList();
  }
}

/// Opens the shared task terminal and selects [sessionId]'s tab.
void showDeployTerminal(WidgetRef ref, String sessionId) {
  ref.read(deploySessionsProvider.notifier).setAllModalVisible(true);
  unawaited(
    showAttentionModal(
      id: 'deploy-terminal',
      replaceIfExists: true,
      barrierDismissible: false,
      builder: (context, dismiss) =>
          _DeployTerminalModal(initialSessionId: sessionId, dismiss: dismiss),
    ),
  );
}

/// Starts a deploy session, opens the terminal, and streams [run] output into it.
Future<void> runWithDeployTerminal({
  required WidgetRef ref,
  required String title,
  required String subtitle,
  required String command,
  required Future<void> Function(void Function(String chunk) onOutput) run,
  FutureOr<void> Function()? onCancel,
}) async {
  final sessions = ref.read(deploySessionsProvider.notifier);
  final id = sessions.start(
    title: title,
    subtitle: subtitle,
    command: command,
    onCancel: onCancel,
  );
  showDeployTerminal(ref, id);
  try {
    await run((chunk) => sessions.append(id, chunk));
    sessions.append(id, '\nCompleted successfully.\n');
    sessions.complete(id, success: true);
  } catch (error) {
    if (sessions.isCancelled(id)) return;
    sessions.append(id, '\n$error\n');
    sessions.complete(id, success: false, error: error.toString());
    rethrow;
  }
}

class _DeployTerminalModal extends ConsumerStatefulWidget {
  const _DeployTerminalModal({
    required this.initialSessionId,
    required this.dismiss,
  });

  final String initialSessionId;
  final VoidCallback dismiss;

  @override
  ConsumerState<_DeployTerminalModal> createState() =>
      _DeployTerminalModalState();
}

class _DeployTerminalModalState extends ConsumerState<_DeployTerminalModal> {
  late String _selectedSessionId = widget.initialSessionId;

  void _hide() {
    ref.read(deploySessionsProvider.notifier).setAllModalVisible(false);
    widget.dismiss();
  }

  void _close() {
    final sessions = ref.read(deploySessionsProvider);
    final closingSessionId = _selectedSessionId;
    final selectedIndex = sessions.indexWhere(
      (session) => session.id == closingSessionId,
    );
    if (selectedIndex < 0) return;

    final remainingSessions = [
      for (final session in sessions)
        if (session.id != closingSessionId) session,
    ];

    // Keep the selection in sync with the list before removing the current
    // tab. Otherwise the next close action can still target the already
    // removed session, leaving the visible task behind when the modal reopens.
    if (remainingSessions.isNotEmpty) {
      final nextIndex = selectedIndex < remainingSessions.length
          ? selectedIndex
          : remainingSessions.length - 1;
      setState(() => _selectedSessionId = remainingSessions[nextIndex].id);
    }
    ref.read(deploySessionsProvider.notifier).remove(closingSessionId);
    if (remainingSessions.isEmpty) widget.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sessions = ref.watch(deploySessionsProvider);

    if (sessions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.dismiss());
      return const SizedBox.shrink();
    }
    final selectedIndex = sessions.indexWhere(
      (item) => item.id == _selectedSessionId,
    );
    final session =
        sessions[selectedIndex < 0 ? sessions.length - 1 : selectedIndex];

    final statusColor = switch (session.status) {
      DeploySessionStatus.running => scheme.primary,
      DeploySessionStatus.succeeded => scheme.primary,
      DeploySessionStatus.failed => scheme.error,
      DeploySessionStatus.cancelled => scheme.onSurfaceVariant,
    };
    final statusLabel = switch (session.status) {
      DeploySessionStatus.running => 'deployRunning'.tr(),
      DeploySessionStatus.succeeded => 'deploySucceeded'.tr(),
      DeploySessionStatus.failed => 'deployFailed'.tr(),
      DeploySessionStatus.cancelled => 'deployCancelled'.tr(),
    };

    return AttentionModalScaffold(
      titleText: session.title,
      onDismiss: session.isRunning ? _hide : _close,
      maxWidth: 800,
      maxHeightFactor: 0.85,
      actions: [
        if (session.isRunning)
          IconButton(
            tooltip: 'Hide (keeps running)',
            onPressed: _hide,
            icon: const Icon(Symbols.keyboard_arrow_down),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.length > 1)
            Padding(
              // The TabBar paints its divider across its own bounds. Keep its
              // bounds flush with the modal so that divider reaches both edges.
              padding: const EdgeInsets.only(bottom: 8),
              child: DefaultTabController(
                key: ValueKey(sessions.map((item) => item.id).join()),
                length: sessions.length,
                initialIndex: selectedIndex < 0
                    ? sessions.length - 1
                    : selectedIndex,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) =>
                      setState(() => _selectedSessionId = sessions[index].id),
                  tabs: [
                    for (final item in sessions)
                      Tab(
                        iconMargin: const EdgeInsets.only(right: 6),
                        icon: Icon(
                          item.status == DeploySessionStatus.running
                              ? Symbols.progress_activity
                              : item.status == DeploySessionStatus.succeeded
                              ? Symbols.check_circle
                              : item.status == DeploySessionStatus.cancelled
                              ? Symbols.cancel
                              : Symbols.error,
                          size: 16,
                        ),
                        text: item.subtitle,
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                if (session.isRunning)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                else
                  Icon(
                    session.status == DeploySessionStatus.succeeded
                        ? Symbols.check_circle
                        : session.status == DeploySessionStatus.cancelled
                        ? Symbols.cancel
                        : Symbols.error,
                    size: 16,
                    color: statusColor,
                  ),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    session.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (session.progress != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(session.progress! * 100).round()}%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SelectableText(
              session.command,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: MaidKitFonts.mono,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _SessionProgressBar(session: session, color: statusColor),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF111315),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: session.log.isEmpty
                    ? Center(
                        child: Text(
                          'Waiting for remote output…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: MaidKitFonts.mono,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : AnsiLogView(
                        text: session.log,
                        streaming: true,
                        borderRadius: BorderRadius.circular(12),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.isRunning
                        ? (session.progressDetail == null
                              ? 'Hide to keep working; progress stays in the sidebar.'
                              : session.progressDetail!)
                        : session.status == DeploySessionStatus.succeeded
                        ? 'Finished successfully.'
                        : session.status == DeploySessionStatus.cancelled
                        ? 'Task terminated.'
                        : 'Finished with an error.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (session.isRunning)
                  if (session.canTerminate)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        ref
                            .read(deploySessionsProvider.notifier)
                            .terminate(session.id),
                      ),
                      icon: const Icon(Symbols.stop_circle, size: 18),
                      label: Text('deployTerminate'.tr()),
                    ),
                if (session.isRunning) const SizedBox(width: 8),
                if (session.isRunning)
                  OutlinedButton.icon(
                    onPressed: _hide,
                    icon: const Icon(Symbols.keyboard_arrow_down, size: 18),
                    label: Text('deployHide'.tr()),
                  )
                else
                  FilledButton(
                    onPressed: _close,
                    child: Text('commonDone'.tr()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionProgressBar extends StatelessWidget {
  const _SessionProgressBar({required this.session, required this.color});

  final DeploySession session;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = session.isRunning;
    final value = session.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            // Indeterminate while running without a parsed percentage;
            // determinate once docker/podman reports % or layer sizes.
            value: running && value == null
                ? null
                : (value ?? (running ? null : 0)),
            minHeight: 6,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        if (session.progressDetail != null && session.isRunning) ...[
          const SizedBox(height: 6),
          Text(
            session.progressDetail!,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Compact rail control for deploy sessions that are hidden from the modal.
class DeploySessionsRailButton extends ConsumerWidget {
  const DeploySessionsRailButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(deploySessionsProvider);
    final hidden = sessions.where((session) => !session.modalVisible).toList();
    if (hidden.isEmpty) return const SizedBox.shrink();

    final primary = hidden.last;
    final running = hidden.any((session) => session.isRunning);
    final failed = hidden.any(
      (session) => session.status == DeploySessionStatus.failed,
    );
    final scheme = Theme.of(context).colorScheme;
    final color = failed
        ? scheme.error
        : running
        ? scheme.primary
        : scheme.onSurfaceVariant;

    final progressLabel = primary.progress == null
        ? null
        : '${(primary.progress! * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: running
            ? '${primary.title} (running${progressLabel == null ? '' : ' · $progressLabel'} — click to show)'
            : '${primary.title} (click to show)',
        child: Badge(
          isLabelVisible: hidden.length > 1 || progressLabel != null,
          label: Text(
            hidden.length > 1 ? '${hidden.length}' : (progressLabel ?? ''),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showDeployTerminal(ref, primary.id),
            child: SizedBox(
              width: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Symbols.terminal, color: color),
                      if (running)
                        Positioned(
                          right: 10,
                          bottom: 2,
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: color,
                              value: primary.progress,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    running
                        ? (progressLabel ?? 'deployTaskLabel'.tr())
                        : 'deployLogLabel'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
