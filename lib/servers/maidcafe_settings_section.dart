import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'maidcafe_service.dart';
import 'server_providers.dart';

class MaidCafeSettingsSection extends ConsumerStatefulWidget {
  const MaidCafeSettingsSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  ConsumerState<MaidCafeSettingsSection> createState() =>
      _MaidCafeSettingsSectionState();
}

class _MaidCafeSettingsSectionState
    extends ConsumerState<MaidCafeSettingsSection> {
  late final TextEditingController _cloudUrlController;
  String? _message;
  String? _cloudHealth;
  String? _busy;
  bool _unreadOnly = false;
  String? _daemonFilter;

  @override
  void initState() {
    super.initState();
    _cloudUrlController = TextEditingController(
      text: ref.read(maidCafeCloudUrlProvider),
    );
  }

  @override
  void dispose() {
    _cloudUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloudUser = ref.watch(cloudUserProvider);
    final daemons = ref.watch(maidCafeDaemonsProvider);
    final notifications = ref.watch(maidCafeNotificationsProvider);
    final cloudUrl = ref.watch(maidCafeCloudUrlProvider);
    if (_cloudUrlController.text != cloudUrl && _busy == null) {
      _cloudUrlController.text = cloudUrl;
    }
    return _SettingsSectionCard(
      title: widget.showTitle ? 'maidCafeTitle'.tr() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _urlEditor(
            context,
            controller: _cloudUrlController,
            label: 'maidCafeCloudUrl'.tr(),
            hint: 'maidCafeCloudUrlHint'.tr(),
            onSave: () => _saveCloudUrl(context),
            onReset: () => _resetCloudUrl(context),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy == null
                      ? () => _checkCloudHealth(context)
                      : null,
                  icon: const Icon(Symbols.health_and_safety),
                  label: Text('maidCafeCheckCloudHealth'.tr()),
                ),
                if (_cloudHealth != null) _healthStatus(context),
              ],
            ),
          ),
          const Divider(height: 32),
          cloudUser.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => _signedOut(context),
            data: (user) => user == null
                ? _signedOut(context)
                : _signedIn(context, daemons, notifications),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }

  Widget _signedOut(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text('maidCafeSignInRequired'.tr()),
  );

  Widget _signedIn(
    BuildContext context,
    AsyncValue<List<MaidCafeDaemon>> daemons,
    AsyncValue<List<MaidCafeNotification>> notifications,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('maidCafeCloudBoundary'.tr()),
      ),
      const SizedBox(height: 8),
      daemons.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
        error: (error, _) => _recoverableError(
          context,
          error,
          () => ref.invalidate(maidCafeDaemonsProvider),
        ),
        data: (items) => items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text('maidCafeNoDaemons'.tr()),
              )
            : Column(
                children: [
                  for (final daemon in items) _daemonTile(context, daemon),
                ],
              ),
      ),
      const SizedBox(height: 12),
      _notifications(context, notifications),
    ],
  );

  Widget _daemonTile(BuildContext context, MaidCafeDaemon daemon) => Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        ListTile(
          title: Text(daemon.name),
          subtitle: Text(
            daemon.enabled
                ? '${'maidCafeEnabled'.tr()} · ${daemon.lastSeenAt?.toLocal() ?? 'maidCafeNeverSeen'.tr()}'
                : 'maidCafeDisabled'.tr(),
          ),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'maidCafeRename'.tr(),
                icon: const Icon(Symbols.edit),
                onPressed: _busy == null
                    ? () => _renameDaemon(context, daemon)
                    : null,
              ),
              IconButton(
                tooltip: daemon.enabled
                    ? 'maidCafeDisable'.tr()
                    : 'maidCafeEnable'.tr(),
                icon: Icon(daemon.enabled ? Symbols.pause : Symbols.play_arrow),
                onPressed: _busy == null
                    ? () => _setDaemonEnabled(context, daemon, !daemon.enabled)
                    : null,
              ),
              IconButton(
                tooltip: 'maidCafeRotateSecret'.tr(),
                icon: const Icon(Symbols.key),
                onPressed: _busy == null
                    ? () => _rotateSecret(context, daemon)
                    : null,
              ),
              IconButton(
                tooltip: 'maidCafeDisable'.tr(),
                icon: const Icon(Symbols.delete_outline),
                onPressed: _busy == null
                    ? () => _disableDaemon(context, daemon)
                    : null,
              ),
            ],
          ),
        ),
        _daemonHistoryAndAlarms(context, daemon),
      ],
    ),
  );

  Widget _daemonHistoryAndAlarms(BuildContext context, MaidCafeDaemon daemon) {
    final metrics = ref.watch(maidCafeMetricsProvider(daemon.id));
    final alarms = ref.watch(maidCafeAlarmsProvider(daemon.id));
    final history = metrics.asData?.value ?? const <MaidCafeMetric>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final sample in history.take(5))
            Text(
              '${sample.sentAt.toLocal()} · CPU ${sample.cpuPercent.toStringAsFixed(1)}% · RAM ${sample.memoryUsedPercent.toStringAsFixed(1)}%',
            ),
          if (metrics.hasError) Text('maidCafeHistoryUnavailable'.tr()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy == null
                    ? () => _configureAlarm(context, daemon, 'cpu_percent')
                    : null,
                child: Text('maidCafeCpuAlarm'.tr()),
              ),
              OutlinedButton(
                onPressed: _busy == null
                    ? () => _configureAlarm(
                        context,
                        daemon,
                        'memory_used_percent',
                      )
                    : null,
                child: Text('maidCafeMemoryAlarm'.tr()),
              ),
              OutlinedButton(
                onPressed: _busy == null
                    ? () => _requestPushNotification(context, daemon)
                    : null,
                child: Text('maidCafeRequestNotification'.tr()),
              ),
              if (alarms.hasValue)
                Text('${'maidCafeAlarmCount'.tr()}: ${alarms.value!.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _requestPushNotification(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final requested = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeRequestNotification'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'maidCafeNotificationTitle'.tr(),
              ),
            ),
            TextField(
              controller: bodyController,
              decoration: InputDecoration(
                labelText: 'maidCafeNotificationBody'.tr(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('maidCafeRequest'.tr()),
          ),
        ],
      ),
    );
    final title = titleController.text;
    final body = bodyController.text;
    titleController.dispose();
    bodyController.dispose();
    if (requested != true || !context.mounted) return;
    await _run(context, 'maidCafeRequest', () async {
      await ref
          .read(maidCafeServiceProvider)
          .requestPushNotification(
            daemon.id,
            kind: 'user.request',
            title: title,
            body: body,
          );
      ref.invalidate(maidCafeNotificationsProvider);
    });
  }

  Future<void> _configureAlarm(
    BuildContext context,
    MaidCafeDaemon daemon,
    String kind,
  ) async {
    final controller = TextEditingController(text: '80');
    final threshold = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          kind == 'cpu_percent'
              ? 'maidCafeCpuAlarm'.tr()
              : 'maidCafeMemoryAlarm'.tr(),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'maidCafeThreshold'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: Text('maidCafeSave'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (threshold == null || !context.mounted) return;
    await _run(context, 'maidCafeSave', () async {
      await ref
          .read(maidCafeServiceProvider)
          .setAlarm(daemon.id, kind: kind, threshold: threshold);
      ref.invalidate(maidCafeAlarmsProvider(daemon.id));
    });
  }

  Widget _notifications(
    BuildContext context,
    AsyncValue<List<MaidCafeNotification>> notifications,
  ) {
    final daemons =
        ref.watch(maidCafeDaemonsProvider).asData?.value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'maidCafeNotifications'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilterChip(
                label: Text('maidCafeUnreadOnly'.tr()),
                selected: _unreadOnly,
                onSelected: (value) {
                  setState(() => _unreadOnly = value);
                  ref.invalidate(maidCafeNotificationsProvider);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String?>(
            initialValue: _daemonFilter,
            decoration: InputDecoration(labelText: 'maidCafeDaemonFilter'.tr()),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('maidCafeAllDaemons'.tr()),
              ),
              for (final daemon in daemons)
                DropdownMenuItem<String?>(
                  value: daemon.id,
                  child: Text(daemon.name),
                ),
            ],
            onChanged: (value) {
              setState(() => _daemonFilter = value);
              ref.invalidate(maidCafeNotificationsProvider);
            },
          ),
        ),
        notifications.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => _recoverableError(
            context,
            error,
            () => ref.invalidate(maidCafeNotificationsProvider),
          ),
          data: (items) {
            final visible = items
                .where((item) => !_unreadOnly || item.unread)
                .where(
                  (item) =>
                      _daemonFilter == null || item.daemonId == _daemonFilter,
                )
                .toList();
            if (visible.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('maidCafeNoNotifications'.tr()),
              );
            }
            return Column(
              children: [
                for (final item in visible)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(item.title),
                    subtitle: Text(item.body),
                    trailing: item.unread
                        ? TextButton(
                            onPressed: () => _markRead(context, item),
                            child: Text('maidCafeMarkRead'.tr()),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _urlEditor(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onSave,
    required VoidCallback onReset,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, helperText: hint),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy == null ? onSave : null,
              child: Text('maidCafeApply'.tr()),
            ),
            TextButton(
              onPressed: _busy == null ? onReset : null,
              child: Text('maidCafeReset'.tr()),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _recoverableError(
    BuildContext context,
    Object error,
    VoidCallback retry,
  ) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            error is MaidCafeException ? error.message : error.toString(),
          ),
        ),
        TextButton(onPressed: retry, child: Text('maidCafeRetry'.tr())),
      ],
    ),
  );

  Future<void> _saveCloudUrl(BuildContext context) async {
    await _run(context, 'maidCafeSave', () async {
      await ref
          .read(maidCafeCloudUrlProvider.notifier)
          .save(_cloudUrlController.text);
      ref.invalidate(maidCafeDaemonsProvider);
      ref.invalidate(maidCafeNotificationsProvider);
      _cloudUrlController.text = ref.read(maidCafeCloudUrlProvider);
    });
  }

  Future<void> _resetCloudUrl(BuildContext context) async {
    _cloudUrlController.text = maidCafeDefaultCloudUrl;
    await _saveCloudUrl(context);
  }

  Future<void> _checkCloudHealth(BuildContext context) async {
    await _run(context, 'maidCafeCheckCloudHealth', () async {
      final health = await ref.read(maidCafeServiceProvider).checkCloudHealth();
      if (mounted) {
        setState(
          () => _cloudHealth = health.ok
              ? 'OK (${health.mode ?? 'cloud'})'
              : 'Not healthy',
        );
      }
    });
  }

  Widget _healthStatus(BuildContext context) {
    final isHealthy = _cloudHealth!.startsWith('OK');
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHealthy ? colors.secondaryContainer : colors.errorContainer,
        border: Border.all(color: isHealthy ? colors.secondary : colors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHealthy ? Symbols.check_circle : Symbols.warning,
            size: 18,
            color: isHealthy
                ? colors.onSecondaryContainer
                : colors.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Text(
            _cloudHealth!,
            style: TextStyle(
              color: isHealthy
                  ? colors.onSecondaryContainer
                  : colors.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDaemon(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    final controller = TextEditingController(text: daemon.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeRename'.tr()),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('maidCafeSave'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final normalizedName = name.trim();
    await _run(context, 'maidCafeSave', () async {
      await ref
          .read(maidCafeServiceProvider)
          .updateDaemon(daemon.id, name: normalizedName);
      ref.invalidate(maidCafeDaemonsProvider);
    });
  }

  Future<void> _setDaemonEnabled(
    BuildContext context,
    MaidCafeDaemon daemon,
    bool enabled,
  ) async {
    await _run(
      context,
      enabled ? 'maidCafeEnable' : 'maidCafeDisable',
      () async {
        await ref
            .read(maidCafeServiceProvider)
            .updateDaemon(daemon.id, enabled: enabled);
        ref.invalidate(maidCafeDaemonsProvider);
      },
    );
  }

  Future<void> _rotateSecret(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    await _run(context, 'maidCafeRotateSecret', () async {
      final secret = await ref
          .read(maidCafeServiceProvider)
          .rotateDaemonSecret(daemon.id);
      if (context.mounted) {
        await _showSecret(context, secret, daemon.id, daemon.name);
      }
    });
  }

  Future<void> _disableDaemon(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeDisable'.tr()),
        content: Text('maidCafeDisableConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('maidCafeDisable'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, 'maidCafeDisable', () async {
      await ref.read(maidCafeServiceProvider).disableDaemon(daemon.id);
      ref.invalidate(maidCafeDaemonsProvider);
      ref.invalidate(maidCafeNotificationsProvider);
    });
  }

  Future<void> _markRead(
    BuildContext context,
    MaidCafeNotification notification,
  ) async {
    await _run(context, 'maidCafeMarkRead', () async {
      await ref
          .read(maidCafeServiceProvider)
          .markNotificationRead(notification.id);
      ref.invalidate(maidCafeNotificationsProvider);
    });
  }

  Future<void> _showSecret(
    BuildContext context,
    String secret,
    String id,
    String name,
  ) async {
    final snippet =
        '[daemon]\nid = "$id"\ncloudUrl = "${ref.read(maidCafeCloudUrlProvider)}"\ncloudSecret = "$secret"';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeOneTimeSecret'.tr()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('maidCafeOneTimeSecretWarning'.tr()),
              const SizedBox(height: 12),
              SelectableText(secret),
              const SizedBox(height: 12),
              SelectableText(snippet),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: snippet)),
            child: Text('maidCafeCopySnippet'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeDone'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    String operation,
    Future<void> Function() action,
  ) async {
    if (mounted) {
      setState(() {
        _busy = operation;
        _message = null;
      });
    }
    try {
      await action();
    } on MaidCafeException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _message = message);
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Text(title!, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
      Card(child: child),
    ],
  );
}
