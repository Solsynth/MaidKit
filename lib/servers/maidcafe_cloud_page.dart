import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'cloud_sync_service.dart';
import 'maidcafe_connect.dart';
import 'maidcafe_metoer.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Desktop workspace page for the MaidCafe cloud: Solarpass account and
/// workspace selection, daemon registration (the one-time `[daemon]` config
/// snippet), and the Metoer notification feed.
@RoutePage()
class MaidCafeCloudPage extends ConsumerStatefulWidget {
  const MaidCafeCloudPage({super.key});

  @override
  ConsumerState<MaidCafeCloudPage> createState() => _MaidCafeCloudPageState();
}

class _MaidCafeCloudPageState extends ConsumerState<MaidCafeCloudPage> {
  late final TextEditingController _cloudUrlController;
  String? _message;
  String? _cloudHealth;
  String? _busy;

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

  String? get _effectiveWorkspaceId =>
      ref.read(maidCafeWorkspaceIdProvider) ??
      ref.read(cloudWorkspacesProvider).asData?.value.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    final cloudUrl = ref.watch(maidCafeCloudUrlProvider);
    final cloudUser = ref.watch(cloudUserProvider);
    final workspaces = ref.watch(cloudWorkspacesProvider);
    final selectedWorkspaceId = ref.watch(maidCafeWorkspaceIdProvider);
    final effectiveWorkspaceId =
        selectedWorkspaceId ?? workspaces.asData?.value.firstOrNull?.id;
    if (_cloudUrlController.text != cloudUrl && _busy == null) {
      _cloudUrlController.text = cloudUrl;
    }
    // The Metoer list endpoint marks the fetched page viewed server-side, so
    // the unread count follows each feed refresh.
    ref.listen(maidCafeMetoerNotificationsProvider, (previous, next) {
      if (next.hasValue) ref.invalidate(maidCafeMetoerUnreadCountProvider);
    });
    return MaidKitAppScaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              const _MaidCafeCloudHeader(),
              const SizedBox(height: 24),
              _SettingsSectionCard(
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
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(_message!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSectionCard(
                child: cloudUser.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                  error: (_, _) => _accountSignedOut(context),
                  data: (user) => user == null
                      ? _accountSignedOut(context)
                      : _accountSignedIn(context, user),
                ),
              ),
              const SizedBox(height: 24),
              _daemonsCard(context, effectiveWorkspaceId),
              const SizedBox(height: 24),
              _credentialsCard(context),
              const SizedBox(height: 24),
              _notificationsCard(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- account

  Widget _accountSignedOut(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('maidCafeSignInRequired'.tr()),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => _signInCloud(context),
            child: Text('settingsCloudSignIn'.tr()),
          ),
        ),
      ],
    ),
  );

  Widget _accountSignedIn(BuildContext context, CloudUser user) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        leading: CircleAvatar(
          foregroundImage: user.avatarUrl == null
              ? null
              : NetworkImage(user.avatarUrl!),
          child: Text(user.initials),
        ),
        title: Text(user.name),
        subtitle: user.handle.isEmpty ? null : Text(user.handle),
        trailing: TextButton(
          onPressed: () => _signOutCloud(context),
          child: Text('settingsCloudSignOut'.tr()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _workspaceDropdown(context),
      ),
    ],
  );

  Widget _workspaceDropdown(BuildContext context) {
    final workspaces = ref.watch(cloudWorkspacesProvider);
    return workspaces.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => _recoverableError(
        context,
        error,
        () => ref.invalidate(cloudWorkspacesProvider),
      ),
      data: (items) {
        if (items.isEmpty) return Text('maidCafeNoWorkspaces'.tr());
        final selected = ref.watch(maidCafeWorkspaceIdProvider);
        return DropdownButtonFormField<String?>(
          initialValue: items.any((workspace) => workspace.id == selected)
              ? selected
              : null,
          decoration: InputDecoration(labelText: 'maidCafeWorkspace'.tr()),
          items: [
            for (final workspace in items)
              DropdownMenuItem<String?>(
                value: workspace.id,
                child: Text(workspace.name),
              ),
          ],
          onChanged: (id) =>
              ref.read(maidCafeWorkspaceIdProvider.notifier).save(id),
        );
      },
    );
  }

  Future<void> _signInCloud(BuildContext context) async {
    try {
      await ref.read(cloudSyncServiceProvider).signIn();
      ref.invalidate(cloudUserProvider);
      ref.invalidate(cloudWorkspacesProvider);
    } on CloudSyncException catch (error) {
      if (context.mounted) showSnackBar(error.message);
    } catch (_) {
      if (context.mounted) showSnackBar('commonSomethingWentWrong'.tr());
    }
  }

  Future<void> _signOutCloud(BuildContext context) async {
    try {
      await ref.read(cloudSyncServiceProvider).signOut();
      ref.invalidate(cloudUserProvider);
      ref.invalidate(cloudWorkspacesProvider);
      if (context.mounted) {
        showSnackBar('settingsCloudSignOutSuccess'.tr());
      }
    } on CloudSyncException catch (error) {
      if (context.mounted) showSnackBar(error.message);
    } catch (_) {
      if (context.mounted) showSnackBar('commonSomethingWentWrong'.tr());
    }
  }

  // ----------------------------------------------------------------- daemons

  Widget _daemonsCard(BuildContext context, String? workspaceId) {
    if (workspaceId == null) {
      return _SettingsSectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('maidCafeNoWorkspaces'.tr()),
        ),
      );
    }
    final daemons = ref.watch(maidCafeDaemonsProvider(workspaceId));
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'maidCafeDaemons'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy == null
                      ? () => _registerDaemon(context, workspaceId)
                      : null,
                  icon: const Icon(Symbols.add),
                  label: Text('maidCafeRegister'.tr()),
                ),
              ],
            ),
          ),
          daemons.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => _recoverableError(
              context,
              error,
              () => ref.invalidate(maidCafeDaemonsProvider(workspaceId)),
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
        ],
      ),
    );
  }

  Future<void> _registerDaemon(BuildContext context, String workspaceId) async {
    final result = await showDialog<MaidCafeConnectServerResult>(
      context: context,
      builder: (context) =>
          MaidCafeConnectServerDialog(workspaceId: workspaceId),
    );
    if (result == null || !context.mounted) return;
    if (result.manual) {
      await _registerDaemonManually(context, workspaceId);
      return;
    }
    final credential = result.credential!;
    ref.invalidate(maidCafeDaemonsProvider(workspaceId));
    if (context.mounted) {
      await _showSecret(
        context,
        credential.secret,
        credential.id,
        credential.name,
      );
    }
  }

  /// Name-only registration for hosts MaidKit does not manage: the one-time
  /// `[daemon]` snippet is shown for pasting into the daemon's `config.toml`.
  Future<void> _registerDaemonManually(
    BuildContext context,
    String workspaceId,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _RegisterDaemonDialog(),
    );
    if (name == null || !context.mounted) return;
    await _run(context, 'maidCafeRegister', () async {
      final credential = await ref
          .read(maidCafeServiceProvider)
          .createDaemon(name: name, workspaceId: workspaceId);
      ref.invalidate(maidCafeDaemonsProvider(workspaceId));
      if (context.mounted) {
        await _showSecret(
          context,
          credential.secret,
          credential.id,
          credential.name,
        );
      }
    });
  }

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
        _daemonHistory(context, daemon),
      ],
    ),
  );

  Widget _daemonHistory(BuildContext context, MaidCafeDaemon daemon) {
    final metrics = ref.watch(maidCafeMetricsProvider(daemon.id));
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
                    ? () => _requestPushNotification(context, daemon)
                    : null,
                child: Text('maidCafeRequestNotification'.tr()),
              ),
            ],
          ),
          _cloudActions(context, daemon),
        ],
      ),
    );
  }

  /// Actions the daemon reported to the cloud, invoked through the relay:
  /// the cloud page asks the cloud, the cloud queues it, and the daemon
  /// polls and runs it.
  Widget _cloudActions(BuildContext context, MaidCafeDaemon daemon) {
    final actions = ref.watch(maidCafeCloudActionsProvider(daemon.id));
    return actions.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'maidCafeActions'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in items)
                  ActionChip(
                    label: Text(action.label),
                    onPressed: _busy == null
                        ? () => _invokeCloudAction(context, daemon, action)
                        : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _invokeCloudAction(
    BuildContext context,
    MaidCafeDaemon daemon,
    MaidCafeCloudAction action,
  ) async {
    await _run(context, 'maidCafeInvokeAction', () async {
      final result = await ref
          .read(maidCafeServiceProvider)
          .invokeActionViaCloud(daemonId: daemon.id, actionName: action.name);
      if (context.mounted) {
        final stdout = utf8.decode(result.body, allowMalformed: true).trim();
        final stderr = result.error?.trim() ?? '';
        showSnackBar(
          stdout.isNotEmpty
              ? stdout
              : stderr.isNotEmpty
              ? stderr
              : 'maidCafeActionInvoked'.tr(),
        );
      }
    });
  }

  Future<void> _requestPushNotification(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    final requested = await showDialog<({String title, String body})>(
      context: context,
      builder: (context) => const _RequestPushNotificationDialog(),
    );
    if (requested == null || !context.mounted) return;
    await _run(context, 'maidCafeRequest', () async {
      await ref
          .read(maidCafeServiceProvider)
          .requestPushNotification(
            daemon.id,
            kind: 'user.request',
            title: requested.title,
            body: requested.body,
          );
      ref.invalidate(maidCafeMetoerNotificationsProvider);
      ref.invalidate(maidCafeMetoerUnreadCountProvider);
    });
  }

  Future<void> _renameDaemon(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDaemonDialog(initialName: daemon.name),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final normalizedName = name.trim();
    final workspaceId = _effectiveWorkspaceId;
    await _run(context, 'maidCafeSave', () async {
      await ref
          .read(maidCafeServiceProvider)
          .updateDaemon(daemon.id, name: normalizedName);
      if (workspaceId != null) {
        ref.invalidate(maidCafeDaemonsProvider(workspaceId));
      }
    });
  }

  Future<void> _setDaemonEnabled(
    BuildContext context,
    MaidCafeDaemon daemon,
    bool enabled,
  ) async {
    final workspaceId = _effectiveWorkspaceId;
    await _run(
      context,
      enabled ? 'maidCafeEnable' : 'maidCafeDisable',
      () async {
        await ref
            .read(maidCafeServiceProvider)
            .updateDaemon(daemon.id, enabled: enabled);
        if (workspaceId != null) {
          ref.invalidate(maidCafeDaemonsProvider(workspaceId));
        }
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
    final workspaceId = _effectiveWorkspaceId;
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
      if (workspaceId != null) {
        ref.invalidate(maidCafeDaemonsProvider(workspaceId));
      }
    });
  }

  /// The one-time secret dialog: the `[daemon]` block the user pastes into
  /// the daemon's `config.toml` to connect the instance.
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  snippet,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
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

  // ------------------------------------------------------------- credentials

  Widget _credentialsCard(BuildContext context) {
    final credentials = ref.watch(maidCafeCredentialsProvider);
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'maidCafeCredentials'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy == null
                      ? () => _createCredential(context)
                      : null,
                  icon: const Icon(Symbols.add),
                  label: Text('maidCafeCredentialCreate'.tr()),
                ),
              ],
            ),
          ),
          credentials.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => _recoverableError(
              context,
              error,
              () => ref.invalidate(maidCafeCredentialsProvider),
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('maidCafeNoCredentials'.tr()),
                  )
                : Column(
                    children: [
                      for (final credential in items)
                        _credentialTile(context, credential),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _credentialTile(BuildContext context, MaidCafeCredential credential) {
    final colors = Theme.of(context).colorScheme;
    final scopes = <String>[
      if (credential.daemonIds.isNotEmpty)
        'daemons: ${credential.daemonIds.join(', ')}',
      if (credential.hostIds.isNotEmpty)
        'hosts: ${credential.hostIds.join(', ')}',
      if (credential.actionNames.isNotEmpty)
        'actions: ${credential.actionNames.join(', ')}',
    ].join(' · ');
    final lastUsed = credential.lastUsedAt == null
        ? 'maidCafeCredentialNeverUsed'.tr()
        : '${'maidCafeCredentialLastUsed'.tr()} ${DateFormat('yyyy-MM-dd HH:mm').format(credential.lastUsedAt!.toLocal())}';
    return ListTile(
      title: Text(credential.label),
      subtitle: Text(
        scopes.isEmpty
            ? '$lastUsed · ${'maidCafeCredentialUnrestricted'.tr()}'
            : '$lastUsed\n$scopes',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'maidCafeCredentialDelete'.tr(),
        icon: const Icon(Symbols.delete_outline),
        onPressed: _busy == null
            ? () => _deleteCredential(context, credential)
            : null,
      ),
      textColor: colors.onSurface,
    );
  }

  Future<void> _createCredential(BuildContext context) async {
    final created = await showDialog<MaidCafeCredential>(
      context: context,
      builder: (context) => const _CreateCredentialDialog(),
    );
    if (created == null || !context.mounted) return;
    ref.invalidate(maidCafeCredentialsProvider);
    await _showCredentialToken(context, created);
  }

  Future<void> _deleteCredential(
    BuildContext context,
    MaidCafeCredential credential,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeCredentialDelete'.tr()),
        content: Text(
          'maidCafeCredentialDeleteConfirm'.tr(args: [credential.label]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('maidCafeCredentialDelete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, 'maidCafeCredentialDelete', () async {
      await ref.read(maidCafeServiceProvider).deleteCredential(credential.id);
      ref.invalidate(maidCafeCredentialsProvider);
    });
  }

  Future<void> _showCredentialToken(
    BuildContext context,
    MaidCafeCredential credential,
  ) async {
    final token = credential.token;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('maidCafeCredentialToken'.tr()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('maidCafeCredentialTokenHint'.tr()),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  token,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            child: Text('maidCafeCredentialCopy'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeDone'.tr()),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- notifications

  Widget _notificationsCard(BuildContext context) {
    final unread = ref.watch(maidCafeMetoerUnreadCountProvider).asData?.value;
    final notifications = ref.watch(maidCafeMetoerNotificationsProvider);
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'maidCafeNotifications'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (unread != null && unread > 0) ...[
                  Text(
                    'maidCafeUnreadCount'.tr(args: ['$unread']),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _markAllRead(context),
                    child: Text('maidCafeMarkAllRead'.tr()),
                  ),
                ],
                IconButton(
                  tooltip: 'maidCafeRefresh'.tr(),
                  icon: const Icon(Symbols.refresh),
                  onPressed: () {
                    ref.invalidate(maidCafeMetoerNotificationsProvider);
                    ref.invalidate(maidCafeMetoerUnreadCountProvider);
                  },
                ),
              ],
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
              () => ref.invalidate(maidCafeMetoerNotificationsProvider),
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('maidCafeNoNotifications'.tr()),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        _notificationTile(context, item),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _notificationTile(
    BuildContext context,
    MaidCafeMetoerNotification item,
  ) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: item.unread ? Colors.blue : Colors.transparent,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(item.title ?? item.topic),
      subtitle: Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt.toLocal()),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context) async {
    await _run(context, 'maidCafeMarkAllRead', () async {
      await ref.read(maidCafeMetoerClientProvider).markAllRead();
      ref.invalidate(maidCafeMetoerNotificationsProvider);
      ref.invalidate(maidCafeMetoerUnreadCountProvider);
    });
  }

  // -------------------------------------------------------------------- url

  Widget _urlEditor(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onSave,
    required VoidCallback onReset,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

  Future<void> _saveCloudUrl(BuildContext context) async {
    await _run(context, 'maidCafeSave', () async {
      await ref
          .read(maidCafeCloudUrlProvider.notifier)
          .save(_cloudUrlController.text);
      final workspaceId = _effectiveWorkspaceId;
      if (workspaceId != null) {
        ref.invalidate(maidCafeDaemonsProvider(workspaceId));
      }
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

  // ------------------------------------------------------------------ shared

  Widget _recoverableError(
    BuildContext context,
    Object error,
    VoidCallback retry,
  ) {
    final message = switch (error) {
      MaidCafeException(:final message) => message,
      MaidCafeMetoerException(:final message) => message,
      _ => error.toString(),
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: retry, child: Text('maidCafeRetry'.tr())),
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
    } on MaidCafeMetoerException catch (error) {
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

class _MaidCafeCloudHeader extends StatelessWidget {
  const _MaidCafeCloudHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Symbols.cloud_sync, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'maidCafeCloudEyebrow'.tr(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'maidCafeCloudTitle'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'maidCafePageDescription'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(child: child);
}

/// Register-daemon dialog. Owns its text controller so the field stays valid
/// through the route's exit animation.
/// Create-credential dialog: label plus optional comma-separated scopes.
/// Creates through the cloud service so the one-time token can be returned.
class _CreateCredentialDialog extends ConsumerStatefulWidget {
  const _CreateCredentialDialog();

  @override
  ConsumerState<_CreateCredentialDialog> createState() =>
      _CreateCredentialDialogState();
}

class _CreateCredentialDialogState
    extends ConsumerState<_CreateCredentialDialog> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _actionsController = TextEditingController();
  final TextEditingController _hostsController = TextEditingController();
  final TextEditingController _daemonsController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _actionsController.dispose();
    _hostsController.dispose();
    _daemonsController.dispose();
    super.dispose();
  }

  List<String> _split(String value) => [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  Future<void> _submit() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'maidCafeCredentialLabelRequired'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(maidCafeServiceProvider)
          .createCredential(
            label: label,
            actionNames: _split(_actionsController.text),
            hostIds: _split(_hostsController.text),
            daemonIds: _split(_daemonsController.text),
          );
      if (mounted) Navigator.pop(context, created);
    } on MaidCafeException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('maidCafeCredentialCreate'.tr()),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _labelController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'maidCafeCredentialLabel'.tr(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _actionsController,
                decoration: InputDecoration(
                  labelText: 'maidCafeCredentialActionsScope'.tr(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hostsController,
                decoration: InputDecoration(
                  labelText: 'maidCafeCredentialHostsScope'.tr(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _daemonsController,
                decoration: InputDecoration(
                  labelText: 'maidCafeCredentialDaemonsScope'.tr(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'maidCafeCredentialScopesHint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('maidCafeCancel'.tr()),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text('maidCafeCredentialCreate'.tr()),
        ),
      ],
    );
  }
}

class _RegisterDaemonDialog extends StatefulWidget {
  const _RegisterDaemonDialog();

  @override
  State<_RegisterDaemonDialog> createState() => _RegisterDaemonDialogState();
}

class _RegisterDaemonDialogState extends State<_RegisterDaemonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'maidCafeDaemonNameRequired'.tr());
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('maidCafeRegister'.tr()),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'maidCafeDaemonName'.tr(),
        errorText: _validationError,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('maidCafeCancel'.tr()),
      ),
      FilledButton(onPressed: _submit, child: Text('maidCafeRegister'.tr())),
    ],
  );
}

class _RenameDaemonDialog extends StatefulWidget {
  const _RenameDaemonDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDaemonDialog> createState() => _RenameDaemonDialogState();
}

class _RenameDaemonDialogState extends State<_RenameDaemonDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('maidCafeRename'.tr()),
    content: TextField(controller: _controller, autofocus: true),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('maidCafeCancel'.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text('maidCafeSave'.tr()),
      ),
    ],
  );
}

class _RequestPushNotificationDialog extends StatefulWidget {
  const _RequestPushNotificationDialog();

  @override
  State<_RequestPushNotificationDialog> createState() =>
      _RequestPushNotificationDialogState();
}

class _RequestPushNotificationDialogState
    extends State<_RequestPushNotificationDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('maidCafeRequestNotification'.tr()),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'maidCafeNotificationTitle'.tr(),
          ),
        ),
        TextField(
          controller: _bodyController,
          decoration: InputDecoration(
            labelText: 'maidCafeNotificationBody'.tr(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('maidCafeCancel'.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          title: _titleController.text,
          body: _bodyController.text,
        )),
        child: Text('maidCafeRequest'.tr()),
      ),
    ],
  );
}
