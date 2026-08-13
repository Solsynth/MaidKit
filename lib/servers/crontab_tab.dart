import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'crontab_models.dart';
import 'server_connection_actions.dart';
import 'server_providers.dart';

/// Manage the SSH user's personal crontab on a connected server.
class CrontabTab extends ConsumerStatefulWidget {
  const CrontabTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;

  @override
  ConsumerState<CrontabTab> createState() => _CrontabTabState();
}

class _CrontabTabState extends ConsumerState<CrontabTab> {
  AsyncValue<CrontabDocument> _document = const AsyncValue.loading();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(CrontabTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted || !widget.connected) return;
    setState(() => _document = const AsyncValue.loading());
    try {
      final document = await ref
          .read(connectionManagerProvider)
          .listCrontab(widget.server.id);
      if (mounted) setState(() => _document = AsyncValue.data(document));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _document = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _persist(
    CrontabDocument document, {
    required String success,
    bool canRetryConnection = true,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(connectionManagerProvider)
          .installCrontab(widget.server.id, document);
      if (!mounted) return;
      setState(() {
        _document = AsyncValue.data(document);
        _busy = false;
      });
      showStyledSnackBar(message: success, title: 'crontabTitle'.tr());
    } catch (error) {
      if (!mounted) return;
      final shouldRetry =
          canRetryConnection &&
          await shouldReconnectAndRetry(context, error, widget.server);
      if (!mounted) return;
      if (shouldRetry) {
        await widget.onConnect();
        if (mounted) {
          await _persist(document, success: success, canRetryConnection: false);
        }
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      showStyledSnackBar(
        message: error.toString(),
        title: 'crontabUpdateFailed'.tr(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _addJob() async {
    final current = _document.asData?.value;
    if (current == null) return;
    final draft = await _showJobSheet(context);
    if (draft == null || !mounted) return;
    final line = CronEntry.formatJob(
      minute: draft.minute,
      hour: draft.hour,
      dayOfMonth: draft.dayOfMonth,
      month: draft.month,
      dayOfWeek: draft.dayOfWeek,
      command: draft.command,
    );
    final job = CronEntry(
      raw: line,
      kind: CronEntryKind.job,
      minute: draft.minute.trim(),
      hour: draft.hour.trim(),
      dayOfMonth: draft.dayOfMonth.trim(),
      month: draft.month.trim(),
      dayOfWeek: draft.dayOfWeek.trim(),
      command: draft.command.trim(),
    );
    await _persist(current.addingJob(job), success: 'crontabJobAdded'.tr());
  }

  Future<void> _editJob(int jobIndex, CronEntry entry) async {
    final current = _document.asData?.value;
    if (current == null) return;
    final draft = await _showJobSheet(
      context,
      initial: _JobDraft(
        minute: entry.minute ?? '*',
        hour: entry.hour ?? '*',
        dayOfMonth: entry.dayOfMonth ?? '*',
        month: entry.month ?? '*',
        dayOfWeek: entry.dayOfWeek ?? '*',
        command: entry.command ?? '',
      ),
    );
    if (draft == null || !mounted) return;
    final line = CronEntry.formatJob(
      minute: draft.minute,
      hour: draft.hour,
      dayOfMonth: draft.dayOfMonth,
      month: draft.month,
      dayOfWeek: draft.dayOfWeek,
      command: draft.command,
    );
    final job = CronEntry(
      raw: line,
      kind: CronEntryKind.job,
      minute: draft.minute.trim(),
      hour: draft.hour.trim(),
      dayOfMonth: draft.dayOfMonth.trim(),
      month: draft.month.trim(),
      dayOfWeek: draft.dayOfWeek.trim(),
      command: draft.command.trim(),
    );
    await _persist(
      current.replacingJob(jobIndex, job),
      success: 'crontabJobUpdated'.tr(),
    );
  }

  Future<void> _deleteJob(int jobIndex, CronEntry entry) async {
    final current = _document.asData?.value;
    if (current == null) return;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SheetScaffold(
          titleText: 'crontabRemoveTitle'.tr(),
          heightFactor: 0.36,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                entry.command ?? entry.raw,
                style: theme.textTheme.bodyMedium,
              ),
              if (entry.scheduleSummary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.scheduleSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'IBM Plex Mono',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('commonCancel').tr(),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('commonRemove').tr(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (approved != true || !mounted) return;
    await _persist(
      current.removingJob(jobIndex),
      success: 'crontabJobRemoved'.tr(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _CrontabEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'crontabConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filled: true,
      );
    }

    return _document.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CrontabEmpty(
        icon: Symbols.error_outline,
        message: 'crontabLoadError'.tr(args: [error.toString()]),
        actionLabel: 'commonRetry'.tr(),
        onAction: _load,
      ),
      data: (document) {
        final jobs = document.jobs;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      jobs.isEmpty
                          ? 'crontabNoJobsForUser'.tr(
                              args: [widget.server.username],
                            )
                          : '${'detailProcessCount'.tr(args: ['${jobs.length}'])} · ${widget.server.username}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    tooltip: 'crontabRefresh'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Symbols.refresh),
                  ),
                  IconButton(
                    tooltip: 'crontabAddJob'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : _addJob,
                    icon: const Icon(Symbols.add),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: jobs.isEmpty
                  ? _CrontabEmpty(
                      icon: Symbols.schedule,
                      message: document.exists
                          ? 'crontabEmptyNoJobs'.tr()
                          : 'crontabEmptyNotInstalled'.tr(),
                      actionLabel: 'crontabAddJob'.tr(),
                      onAction: _addJob,
                    )
                  : ListView.separated(
                      itemCount: jobs.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Icon(
                            Symbols.schedule,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            job.command ?? job.raw,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            job.scheduleSummary.isEmpty
                                ? job.scheduleLabel
                                : job.scheduleSummary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: 'IBM Plex Mono',
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'crontabEdit'.tr(),
                                onPressed: _busy
                                    ? null
                                    : () => _editJob(index, job),
                                icon: const Icon(Symbols.edit, size: 20),
                              ),
                              IconButton(
                                tooltip: 'commonRemove'.tr(),
                                onPressed: _busy
                                    ? null
                                    : () => _deleteJob(index, job),
                                icon: const Icon(Symbols.delete, size: 20),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _JobDraft {
  const _JobDraft({
    required this.minute,
    required this.hour,
    required this.dayOfMonth,
    required this.month,
    required this.dayOfWeek,
    required this.command,
  });

  final String minute;
  final String hour;
  final String dayOfMonth;
  final String month;
  final String dayOfWeek;
  final String command;
}

Future<_JobDraft?> _showJobSheet(BuildContext context, {_JobDraft? initial}) {
  return showModalBottomSheet<_JobDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _CronJobSheet(initial: initial),
  );
}

class _CronJobSheet extends StatefulWidget {
  const _CronJobSheet({this.initial});

  final _JobDraft? initial;

  @override
  State<_CronJobSheet> createState() => _CronJobSheetState();
}

class _CronJobSheetState extends State<_CronJobSheet> {
  late final TextEditingController _minute;
  late final TextEditingController _hour;
  late final TextEditingController _dayOfMonth;
  late final TextEditingController _month;
  late final TextEditingController _dayOfWeek;
  late final TextEditingController _command;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _minute = TextEditingController(text: initial?.minute ?? '0');
    _hour = TextEditingController(text: initial?.hour ?? '*');
    _dayOfMonth = TextEditingController(text: initial?.dayOfMonth ?? '*');
    _month = TextEditingController(text: initial?.month ?? '*');
    _dayOfWeek = TextEditingController(text: initial?.dayOfWeek ?? '*');
    _command = TextEditingController(text: initial?.command ?? '');
  }

  @override
  void dispose() {
    _minute.dispose();
    _hour.dispose();
    _dayOfMonth.dispose();
    _month.dispose();
    _dayOfWeek.dispose();
    _command.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _JobDraft(
        minute: _minute.text,
        hour: _hour.text,
        dayOfMonth: _dayOfMonth.text,
        month: _month.text,
        dayOfWeek: _dayOfWeek.text,
        command: _command.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEdit = widget.initial != null;
    return SheetScaffold(
      titleText: isEdit ? 'crontabEditTitle'.tr() : 'crontabAddTitle'.tr(),
      heightFactor: 0.72,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'crontabScheduleLabel'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CronField(
                    controller: _minute,
                    label: 'crontabMinute'.tr(),
                    hint: 'crontabMinuteHint'.tr(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CronField(
                    controller: _hour,
                    label: 'crontabHour'.tr(),
                    hint: 'crontabHourHint'.tr(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CronField(
                    controller: _dayOfMonth,
                    label: 'crontabDay'.tr(),
                    hint: 'crontabDayHint'.tr(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CronField(
                    controller: _month,
                    label: 'crontabMonth'.tr(),
                    hint: 'crontabMonthHint'.tr(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CronField(
                    controller: _dayOfWeek,
                    label: 'crontabWeekday'.tr(),
                    hint: 'crontabWeekdayHint'.tr(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _command,
              decoration: InputDecoration(
                labelText: 'crontabCommandLabel'.tr(),
                hintText: 'crontabCommandHint'.tr(),
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'crontabCommandRequired'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text(
              'crontabExamples'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('commonCancel').tr(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(
                    isEdit ? 'commonSave'.tr() : 'crontabAddJob'.tr(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CronField extends StatelessWidget {
  const _CronField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      style: const TextStyle(fontFamily: 'IBM Plex Mono'),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'commonRequired'.tr();
        return null;
      },
    );
  }
}

class _CrontabEmpty extends StatelessWidget {
  const _CrontabEmpty({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filled = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              if (filled)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Symbols.link),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
