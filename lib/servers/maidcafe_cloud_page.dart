import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/services/analytics_service.dart';
import 'cloud_sync_service.dart';
import 'maidcafe_connect.dart';
import 'maidcafe_metoer.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Desktop workspace page for the MaidCafe cloud: Solarpass account and
/// workspace selection, daemon registration (the one-time `[daemon]` config
/// snippet), and the Metoer notification feed.
///
/// Wide windows get a two-pane console: a fixed control rail (cloud
/// connection, account, credentials) beside a fluid fleet region (daemon
/// cards with a live metric strip, then the notification feed). Narrow
/// windows stack the same sections as cards.
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1000) {
            return _narrowLayout(context, cloudUser, effectiveWorkspaceId);
          }
          return _wideLayout(context, cloudUser, effectiveWorkspaceId);
        },
      ),
    );
  }

  // ----------------------------------------------------------------- layout

  /// Stacked single-column layout for narrow windows.
  Widget _narrowLayout(
    BuildContext context,
    AsyncValue<CloudUser?> cloudUser,
    String? workspaceId,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        const _MaidCafeCloudHeader(),
        const SizedBox(height: 24),
        _SettingsSectionCard(child: _connectionGroup(context)),
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
        _credentialsCard(context),
        const SizedBox(height: 24),
        _daemonsCard(context, workspaceId),
        const SizedBox(height: 24),
        _notificationsCard(context),
      ],
    );
  }

  /// Two-pane console for wide windows: fixed control rail beside the fleet.
  Widget _wideLayout(
    BuildContext context,
    AsyncValue<CloudUser?> cloudUser,
    String? workspaceId,
  ) {
    return Column(
      children: [
        const _MaidCafeCloudHeader(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CloudControlRail(
                children: [
                  _RailSection(
                    label: 'maidCafeCloudConnection'.tr(),
                    child: _connectionGroup(context),
                  ),
                  const SizedBox(height: 24),
                  _RailSection(
                    label: 'settingsAccount'.tr(),
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
                  _RailSection(
                    label: 'maidCafeCredentials'.tr(),
                    action: FilledButton.tonalIcon(
                      onPressed: _busy == null
                          ? () => _createCredential(context)
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Symbols.add, size: 18),
                      label: Text(
                        'maidCafeCredentialCreate'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    child: _credentialsBody(context),
                  ),
                ],
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: _daemonsSection(context, workspaceId),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(24),
                      sliver: SliverToBoxAdapter(
                        child: _notificationsCard(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cloud URL editor, health check and inline operation feedback.
  Widget _connectionGroup(BuildContext context) => Column(
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
  );

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
      final user = await ref.read(cloudSyncServiceProvider).signIn();
      ref.invalidate(cloudUserProvider);
      ref.invalidate(cloudWorkspacesProvider);
      MaidKitAnalytics.instance.setUserId(user.handle);
      MaidKitAnalytics.instance.logCloudSignIn();
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
      MaidKitAnalytics.instance.setUserId(null);
      MaidKitAnalytics.instance.logCloudSignOut();
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

  /// Bare fleet section for the wide layout; sits directly on the surface.
  Widget _daemonsSection(BuildContext context, String? workspaceId) {
    if (workspaceId == null) {
      return _SettingsSectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('maidCafeNoWorkspaces'.tr()),
        ),
      );
    }
    final daemons = ref.watch(maidCafeDaemonsProvider(workspaceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
        const SizedBox(height: 12),
        daemons.when(
          loading: () => const _SettingsSectionCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          ),
          error: (error, _) => _SettingsSectionCard(
            child: _recoverableError(
              context,
              error,
              () => ref.invalidate(maidCafeDaemonsProvider(workspaceId)),
            ),
          ),
          data: (items) => items.isEmpty
              ? _SettingsSectionCard(
                  child: _EmptyDaemons(
                    onRegister: () => _registerDaemon(context, workspaceId),
                  ),
                )
              : _daemonGrid(context, items),
        ),
      ],
    );
  }

  /// Card-wrapped fleet section for the narrow layout.
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
                ? _EmptyDaemons(
                    onRegister: () => _registerDaemon(context, workspaceId),
                  )
                : _daemonGrid(context, items),
          ),
        ],
      ),
    );
  }

  Widget _daemonGrid(BuildContext context, List<MaidCafeDaemon> items) =>
      _DaemonGrid(
        items: items,
        busy: _busy != null,
        onRename: (daemon) => _renameDaemon(context, daemon),
        onToggleEnabled: (daemon) =>
            _setDaemonEnabled(context, daemon, !daemon.enabled),
        onRotateSecret: (daemon) => _rotateSecret(context, daemon),
        onDisable: (daemon) => _disableDaemon(context, daemon),
        onRequestNotification: (daemon) =>
            _requestPushNotification(context, daemon),
        onInvokeAction: (daemon, action) =>
            _invokeCloudAction(context, daemon, action),
      );

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
    MaidKitAnalytics.instance.logDaemonRegistered();
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
      MaidKitAnalytics.instance.logDaemonRegistered();
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

  /// Actions the daemon reported to the cloud, invoked through the relay:
  /// the cloud page asks the cloud, the cloud queues it, and the daemon
  /// polls and runs it.
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
          _credentialsBody(context),
        ],
      ),
    );
  }

  Widget _credentialsBody(BuildContext context) {
    final credentials = ref.watch(maidCafeCredentialsProvider);
    return credentials.when(
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

/// Page identity band: cloud mark, title and description, plus a quiet state
/// cluster (daemon count, unread notifications) when a workspace is known.
/// Shares the recessed console tone with the control rail.
class _MaidCafeCloudHeader extends ConsumerWidget {
  const _MaidCafeCloudHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unread = ref.watch(maidCafeMetoerUnreadCountProvider).asData?.value;
    final workspaceId = ref.watch(maidCafeWorkspaceIdProvider);
    final workspaces = ref.watch(cloudWorkspacesProvider).asData?.value;
    final effectiveWorkspaceId = workspaceId ?? workspaces?.firstOrNull?.id;
    final daemonCount = effectiveWorkspaceId == null
        ? null
        : ref
              .watch(maidCafeDaemonsProvider(effectiveWorkspaceId))
              .asData
              ?.value
              .length;
    final pills = <Widget>[
      if (daemonCount != null)
        _HeaderPill(
          icon: Symbols.dns,
          label: 'maidCafeDaemonCount'.plural(daemonCount),
        ),
      if (unread != null && unread > 0)
        _HeaderPill(
          icon: Symbols.notifications,
          label: 'maidCafeUnreadCount'.tr(args: ['$unread']),
        ),
    ];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'maidCafeCloudEyebrow'.tr(),
          style: textTheme.labelMedium?.copyWith(
            color: colors.primary,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text('maidCafeCloudTitle'.tr(), style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'maidCafePageDescription'.tr(),
          style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720 || pills.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _CloudHeaderIcon(),
                    const SizedBox(width: 16),
                    Expanded(child: identity),
                  ],
                ),
                if (pills.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: pills),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CloudHeaderIcon(),
              const SizedBox(width: 16),
              Expanded(child: identity),
              const SizedBox(width: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: pills,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CloudHeaderIcon extends StatelessWidget {
  const _CloudHeaderIcon();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Symbols.cloud_sync, color: colors.onPrimaryContainer),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-width control rail: the recessed panel holding the connection,
/// account and credential groups. Scrolls independently of the fleet.
class _CloudControlRail extends StatelessWidget {
  const _CloudControlRail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 336,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 32),
        children: children,
      ),
    );
  }
}

/// Labeled group inside the control rail; the eyebrow matches the page
/// header's label treatment so the rail reads as one instrument panel.
class _RailSection extends StatelessWidget {
  const _RailSection({required this.label, this.action, required this.child});

  final String label;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.primary,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    );
    final action = this.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: action == null
              ? Text(label, style: labelStyle)
              : Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: labelStyle),
                    action,
                  ],
                ),
        ),
        child,
      ],
    );
  }
}

/// Left-packed fleet grid with natural card heights; each row is as tall as
/// its tallest card so cloud-action chips never clip.
class _DaemonGrid extends StatelessWidget {
  const _DaemonGrid({
    required this.items,
    required this.busy,
    required this.onRename,
    required this.onToggleEnabled,
    required this.onRotateSecret,
    required this.onDisable,
    required this.onRequestNotification,
    required this.onInvokeAction,
  });

  final List<MaidCafeDaemon> items;
  final bool busy;
  final ValueChanged<MaidCafeDaemon> onRename;
  final ValueChanged<MaidCafeDaemon> onToggleEnabled;
  final ValueChanged<MaidCafeDaemon> onRotateSecret;
  final ValueChanged<MaidCafeDaemon> onDisable;
  final ValueChanged<MaidCafeDaemon> onRequestNotification;
  final void Function(MaidCafeDaemon daemon, MaidCafeCloudAction action)
  onInvokeAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final columns = ((constraints.maxWidth + gap) / (380 + gap))
            .floor()
            .clamp(1, 4);
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final daemon in items)
              SizedBox(
                width: cardWidth,
                child: _DaemonFleetCard(
                  daemon: daemon,
                  busy: busy,
                  onRename: () => onRename(daemon),
                  onToggleEnabled: () => onToggleEnabled(daemon),
                  onRotateSecret: () => onRotateSecret(daemon),
                  onDisable: () => onDisable(daemon),
                  onRequestNotification: () => onRequestNotification(daemon),
                  onInvokeAction: (action) => onInvokeAction(daemon, action),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One fleet card: status dot and name, the live metric strip, last-seen
/// line, and the notification/action controls.
class _DaemonFleetCard extends ConsumerWidget {
  const _DaemonFleetCard({
    required this.daemon,
    required this.busy,
    required this.onRename,
    required this.onToggleEnabled,
    required this.onRotateSecret,
    required this.onDisable,
    required this.onRequestNotification,
    required this.onInvokeAction,
  });

  final MaidCafeDaemon daemon;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onToggleEnabled;
  final VoidCallback onRotateSecret;
  final VoidCallback onDisable;
  final VoidCallback onRequestNotification;
  final ValueChanged<MaidCafeCloudAction> onInvokeAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final metrics = ref.watch(maidCafeMetricsProvider(daemon.id));
    final history = metrics.asData?.value ?? const <MaidCafeMetric>[];
    // The API returns newest-first; the strip reads oldest → newest.
    final ordered = [...history]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final samples = ordered.length > 5
        ? ordered.sublist(ordered.length - 5)
        : ordered;
    final actions =
        ref.watch(maidCafeCloudActionsProvider(daemon.id)).asData?.value ??
        const <MaidCafeCloudAction>[];
    final enabled = daemon.enabled;
    final lastSeen = daemon.lastSeenAt;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: enabled ? colors.primary : colors.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    daemon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'maidCafeRename'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.edit),
                  onPressed: busy ? null : onRename,
                ),
                IconButton(
                  tooltip: enabled
                      ? 'maidCafeDisable'.tr()
                      : 'maidCafeEnable'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(enabled ? Symbols.pause : Symbols.play_arrow),
                  onPressed: busy ? null : onToggleEnabled,
                ),
                IconButton(
                  tooltip: 'maidCafeRotateSecret'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.key),
                  onPressed: busy ? null : onRotateSecret,
                ),
                IconButton(
                  tooltip: 'maidCafeDisable'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.delete_outline),
                  onPressed: busy ? null : onDisable,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _MetricBars(
                samples: samples,
                unavailable: metrics.hasError,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                enabled
                    ? '${'maidCafeEnabled'.tr()} · ${lastSeen == null ? 'maidCafeNeverSeen'.tr() : 'maidCafeLastSeen'.tr(args: [DateFormat('yyyy-MM-dd HH:mm').format(lastSeen.toLocal())])}'
                    : 'maidCafeDisabled'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: busy ? null : onRequestNotification,
                icon: const Icon(Symbols.notifications, size: 18),
                label: Text('maidCafeRequestNotification'.tr()),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'maidCafeActions'.tr(),
                  style: textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      ActionChip(
                        label: Text(action.label),
                        onPressed: busy ? null : () => onInvokeAction(action),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The fleet card's signature: the last five CPU/RAM samples as a threshold
/// colored bar strip with tabular values. Values follow the dashboard's load
/// colors (tertiary ≥ 75%, error ≥ 90%).
class _MetricBars extends StatelessWidget {
  const _MetricBars({required this.samples, required this.unavailable});

  final List<MaidCafeMetric> samples;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: unavailable && samples.isEmpty
          ? Text(
              'maidCafeHistoryUnavailable'.tr(),
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _barRow(context, 'CPU', (sample) => sample.cpuPercent),
                const SizedBox(height: 6),
                _barRow(context, 'RAM', (sample) => sample.memoryUsedPercent),
              ],
            ),
    );
  }

  Widget _barRow(
    BuildContext context,
    String label,
    double Function(MaidCafeMetric) valueOf,
  ) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latest = samples.isEmpty ? null : valueOf(samples.last);
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                for (final sample in samples)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: FractionallySizedBox(
                          heightFactor: (valueOf(sample) / 100).clamp(
                            0.04,
                            1.0,
                          ),
                          // FractionallySizedBox lays its child out loosely;
                          // a bare DecoratedBox would collapse to zero size.
                          child: SizedBox.expand(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _barColor(valueOf(sample), colors),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            latest == null ? '—' : '${latest.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: textTheme.labelMedium?.copyWith(
              color: colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Color _barColor(double percent, ColorScheme colors) {
    if (percent >= 90) return colors.error;
    if (percent >= 75) return colors.tertiary;
    return colors.primary;
  }
}

/// Empty fleet state: invite to register the first daemon.
class _EmptyDaemons extends StatelessWidget {
  const _EmptyDaemons({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Symbols.dns, size: 36, color: colors.onSurfaceVariant, fill: 0),
          const SizedBox(height: 12),
          Text(
            'maidCafeNoDaemons'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: FilledButton.icon(
              onPressed: onRegister,
              icon: const Icon(Symbols.add),
              label: Text('maidCafeRegister'.tr()),
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
