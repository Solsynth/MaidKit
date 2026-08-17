import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'package:maid_kit/shared/services/analytics_service.dart';
import 'package:styled_widget/styled_widget.dart';
import 'cloud_sync_service.dart';
import 'maidcafe_connect.dart';
import 'maidcafe_metoer.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Desktop workspace page for the MaidCafe cloud: Solarpass account and
/// workspace selection, daemon registration (the one-time `[daemon]` config
/// snippet), and the Metoer notification feed.
///
/// The page is a tabbed console — fleet (daemon cards with a live metric
/// strip), credentials and notifications — with the account and workspace
/// selection in a terminal-style bottom status bar that also carries a
/// manual refresh and a last-refreshed readout.
@RoutePage()
class MaidCafeCloudPage extends ConsumerStatefulWidget {
  const MaidCafeCloudPage({super.key});

  @override
  ConsumerState<MaidCafeCloudPage> createState() => _MaidCafeCloudPageState();
}

class _MaidCafeCloudPageState extends ConsumerState<MaidCafeCloudPage>
    with SingleTickerProviderStateMixin {
  static const _daemonsOp = 'daemons';
  static const _credentialsOp = 'credentials';
  static const _notificationsOp = 'notifications';

  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  )..addListener(_onTabChanged);

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Operations currently in flight. Only the control that started an
  /// operation is disabled while it runs; the rest of the page stays live.
  final Set<String> _busyOps = {};

  Timer? _refreshTimer;
  DateTime? _lastRefreshed;

  bool _isBusy(String op) => _busyOps.contains(op);

  static String _daemonOp(String daemonId) => 'daemon:$daemonId';

  String? get _effectiveWorkspaceId =>
      ref.read(maidCafeWorkspaceIdProvider) ??
      ref.read(cloudWorkspacesProvider).asData?.value.firstOrNull?.id;

  @override
  void initState() {
    super.initState();
    // Daemons report metrics roughly every minute; poll the cloud at the
    // same cadence so the metric strip and last-seen stay current.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshCloudData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Re-fetches the daemon records (last-seen) and each daemon's metric
  /// history and reported actions from the cloud.
  void _refreshCloudData() {
    if (!mounted) return;
    final workspaceId = _effectiveWorkspaceId;
    if (workspaceId == null) return;
    ref.invalidate(maidCafeDaemonsProvider(workspaceId));
    ref.invalidate(maidCafeQuotaProvider(workspaceId));
    final daemons = ref
        .read(maidCafeDaemonsProvider(workspaceId))
        .asData
        ?.value;
    if (daemons == null) return;
    for (final daemon in daemons) {
      ref.invalidate(maidCafeMetricsProvider(daemon.id));
      ref.invalidate(maidCafeCloudActionsProvider(daemon.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloudUser = ref.watch(cloudUserProvider);
    final workspaces = ref.watch(cloudWorkspacesProvider);
    final selectedWorkspaceId = ref.watch(maidCafeWorkspaceIdProvider);
    final effectiveWorkspaceId =
        selectedWorkspaceId ?? workspaces.asData?.value.firstOrNull?.id;
    // The Metoer list endpoint marks the fetched page viewed server-side, so
    // the unread count follows each feed refresh.
    ref.listen(maidCafeMetoerNotificationsProvider, (previous, next) {
      if (next.hasValue) ref.invalidate(maidCafeMetoerUnreadCountProvider);
    });
    // Track when the fleet data was last fetched: on the initial load, each
    // poll tick, and after a manual refresh.
    if (effectiveWorkspaceId != null) {
      ref.listen(maidCafeDaemonsProvider(effectiveWorkspaceId), (
        previous,
        next,
      ) {
        if (next.hasValue) _lastRefreshed = DateTime.now();
      });
    }
    return MaidKitAppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _cloudTabs(context, effectiveWorkspaceId)),
          _cloudStatusBar(context, cloudUser, effectiveWorkspaceId),
        ],
      ),
      floatingActionButton: _fabForTab(effectiveWorkspaceId),
    );
  }

  // ----------------------------------------------------------------- layout

  /// Tabbed main region: the fleet, credentials, and the notification feed.
  Widget _cloudTabs(BuildContext context, String? workspaceId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            IconLabelTab(
              icon: const Icon(Symbols.dns, size: 18),
              label: 'assetsConnections'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.key, size: 18),
              label: 'maidCafeCredentials'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.notifications, size: 18),
              label: 'maidCafeNotifications'.tr(),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _fleetTab(context, workspaceId),
              _credentialsTab(context),
              _notificationsTab(context),
            ],
          ),
        ),
      ],
    );
  }

  /// The unified create action: one floating button that follows the active
  /// tab. The notifications tab has no create action, so no FAB there.
  Widget? _fabForTab(String? workspaceId) {
    if (workspaceId == null) return null;
    return switch (_tabController.index) {
      0 => FloatingActionButton.extended(
        heroTag: 'maidcafe-create-fab',
        onPressed: _isBusy(_daemonsOp)
            ? null
            : () => _registerDaemon(context, workspaceId),
        icon: const Icon(Symbols.add),
        label: Text('maidCafeRegister'.tr()),
      ).padding(bottom: 40),
      1 => FloatingActionButton.extended(
        heroTag: 'maidcafe-create-fab',
        onPressed: _isBusy(_credentialsOp)
            ? null
            : () => _createCredential(context),
        icon: const Icon(Symbols.add),
        label: Text('maidCafeCredentialCreate'.tr()),
      ).padding(bottom: 40),
      _ => null,
    };
  }

  /// Terminal-style bottom status strip: account, workspace selector,
  /// manual refresh and the last-refreshed readout.
  Widget _cloudStatusBar(
    BuildContext context,
    AsyncValue<CloudUser?> cloudUser,
    String? workspaceId,
  ) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTimestamp = constraints.maxWidth >= 600;
          return Row(
            children: [
              cloudUser.when(
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => _statusSignIn(context),
                data: (user) => user == null
                    ? _statusSignIn(context)
                    : _statusAccount(context, user),
              ),
              const Spacer(),
              if (_lastRefreshed != null && showTimestamp) ...[
                Text(
                  'maidCafeLastRefreshed'.tr(
                    args: [DateFormat('HH:mm:ss').format(_lastRefreshed!)],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: 'maidCafeRefresh'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.refresh, size: 18),
                onPressed: _refreshCloudData,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Compact sign-in entry for the status bar.
  Widget _statusSignIn(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.person, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => _signInCloud(context),
          child: Text('settingsCloudSignIn'.tr()),
        ),
      ],
    );
  }

  /// Compact account chip for the status bar: avatar, name, workspace
  /// selector and sign-out.
  Widget _statusAccount(BuildContext context, CloudUser user) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          foregroundImage: user.avatarUrl == null
              ? null
              : NetworkImage(user.avatarUrl!),
          child: Text(user.initials, style: textTheme.labelSmall),
        ),
        const SizedBox(width: 8),
        _statusWorkspaceSelector(context),
      ],
    );
  }

  /// Compact workspace selector for the status bar.
  Widget _statusWorkspaceSelector(BuildContext context) {
    final workspaces = ref.watch(cloudWorkspacesProvider);
    return workspaces.when(
      loading: () => const SizedBox(
        width: 96,
        height: 14,
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final selected = ref.watch(maidCafeWorkspaceIdProvider);
        return DropdownButton<String?>(
          value: items.any((workspace) => workspace.id == selected)
              ? selected
              : null,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: Theme.of(context).textTheme.labelMedium,
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

  // ---------------------------------------------------------------- account

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
  /// Fleet tab: the daemon grid with the register action.
  Widget _fleetTab(BuildContext context, String? workspaceId) {
    if (workspaceId == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: _SettingsSectionCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('maidCafeNoWorkspaces'.tr()),
          ),
        ),
      );
    }
    final daemons = ref.watch(maidCafeDaemonsProvider(workspaceId));
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        _quotaSummary(context, workspaceId),
        daemons.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
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

  Widget _daemonGrid(BuildContext context, List<MaidCafeDaemon> items) =>
      _DaemonGrid(
        items: items,
        isBusy: (daemon) => _isBusy(_daemonOp(daemon.id)),
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

  /// Workspace quota readout above the fleet: daemon registration limit
  /// with current usage, the relay/metric poll throttle and metric
  /// retention. Skipped when the cloud exposes no quota view (older or
  /// self-hosted clouds).
  Widget _quotaSummary(BuildContext context, String workspaceId) {
    final quota = ref.watch(maidCafeQuotaProvider(workspaceId)).asData?.value;
    if (quota == null) return const SizedBox.shrink();
    final daemonCount =
        ref.watch(maidCafeDaemonsProvider(workspaceId)).asData?.value.length ??
        0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _QuotaCard(quota: quota, daemonCount: daemonCount),
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
    await _run(_daemonsOp, () async {
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
    await _run(_daemonOp(daemon.id), () async {
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
    final requested = await showModalBottomSheet<({String title, String body})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _RequestNotificationSheet(),
    );
    if (requested == null || !context.mounted) return;
    await _run(_daemonOp(daemon.id), () async {
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
    await _run(_daemonOp(daemon.id), () async {
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
    await _run(_daemonOp(daemon.id), () async {
      await ref
          .read(maidCafeServiceProvider)
          .updateDaemon(daemon.id, enabled: enabled);
      if (workspaceId != null) {
        ref.invalidate(maidCafeDaemonsProvider(workspaceId));
      }
    });
  }

  Future<void> _rotateSecret(
    BuildContext context,
    MaidCafeDaemon daemon,
  ) async {
    await _run(_daemonOp(daemon.id), () async {
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
    await _run(_daemonOp(daemon.id), () async {
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

  /// Credentials tab: create button above the credential list.
  Widget _credentialsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [_credentialsBody(context)],
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
        onPressed: _isBusy(_credentialsOp)
            ? null
            : () => _deleteCredential(context, credential),
      ),
      textColor: colors.onSurface,
    );
  }

  Future<void> _createCredential(BuildContext context) async {
    final workspaceId = _effectiveWorkspaceId;
    if (workspaceId == null) return;
    final created = await showModalBottomSheet<MaidCafeCredential>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CreateCredentialSheet(workspaceId: workspaceId),
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
    await _run(_credentialsOp, () async {
      await ref.read(maidCafeServiceProvider).deleteCredential(credential.id);
      ref.invalidate(maidCafeCredentialsProvider);
    });
  }

  Future<void> _showCredentialToken(
    BuildContext context,
    MaidCafeCredential credential,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CredentialTokenSheet(
        token: credential.token,
        cloudUrl: ref.read(maidCafeCloudUrlProvider),
      ),
    );
  }

  // ------------------------------------------------------------- notifications

  /// Notifications tab: feed actions above the Metoer feed.
  Widget _notificationsTab(BuildContext context) {
    final unread = ref.watch(maidCafeMetoerUnreadCountProvider).asData?.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
        const SizedBox(height: 4),
        _notificationsBody(context),
      ],
    );
  }

  Widget _notificationsBody(BuildContext context) {
    final notifications = ref.watch(maidCafeMetoerNotificationsProvider);
    return notifications.when(
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
                for (final item in items) _notificationTile(context, item),
              ],
            ),
    );
  }

  Widget _notificationTile(
    BuildContext context,
    MaidCafeMetoerNotification item,
  ) {
    final colors = Theme.of(context).colorScheme;
    final daemonName = item.meta['daemon_name']?.toString();
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (daemonName != null && daemonName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'maidCafeFromServer'.tr(args: [daemonName]),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
      trailing: Text(
        DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt.toLocal()),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context) async {
    await _run(_notificationsOp, () async {
      await ref.read(maidCafeMetoerClientProvider).markAllRead();
      ref.invalidate(maidCafeMetoerNotificationsProvider);
      ref.invalidate(maidCafeMetoerUnreadCountProvider);
    });
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

  /// Runs [action] with only its own busy key set, so the rest of the page
  /// stays interactive while it is in flight. Failures surface as a snackbar.
  Future<void> _run(String op, Future<void> Function() action) async {
    if (mounted) setState(() => _busyOps.add(op));
    try {
      await action();
    } on MaidCafeException catch (error) {
      showSnackBar(error.message);
    } on MaidCafeMetoerException catch (error) {
      showSnackBar(error.message);
    } catch (error) {
      showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busyOps.remove(op));
    }
  }
}

/// Fixed-width control rail: the recessed panel holding the account and
/// credential groups. Scrolls independently of the fleet.

/// Fixed-width control rail: the recessed panel holding the connection,
/// account and credential groups. Scrolls independently of the fleet.
/// Left-packed fleet grid with natural card heights; each row is as tall as
/// its tallest card so cloud-action chips never clip.
class _DaemonGrid extends StatelessWidget {
  const _DaemonGrid({
    required this.items,
    required this.isBusy,
    required this.onRename,
    required this.onToggleEnabled,
    required this.onRotateSecret,
    required this.onDisable,
    required this.onRequestNotification,
    required this.onInvokeAction,
  });

  final List<MaidCafeDaemon> items;

  /// Per-daemon busy state: only the card whose operation is running locks.
  final bool Function(MaidCafeDaemon daemon) isBusy;
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
                  busy: isBusy(daemon),
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
    final disconnected = enabled && daemon.disconnectedAt != null;
    final lastSeen = daemon.lastSeenAt;
    final uptime = samples.isEmpty ? null : samples.last.uptimeSeconds;
    final uptimeLabel = uptime != null && uptime > 0
        ? 'maidCafeUptime'.tr(args: [_formatUptime(uptime)])
        : null;

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
                    color: disconnected
                        ? colors.error
                        : enabled
                        ? colors.primary
                        : colors.outline,
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
            if (disconnected) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    border: Border(
                      left: BorderSide(color: colors.error, width: 3),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.cloud_off,
                        size: 18,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'maidCafeDisconnected'.tr(),
                          style: textTheme.labelLarge?.copyWith(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(daemon.disconnectedAt!.toLocal()),
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.onErrorContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 10),
            if (disconnected) const SizedBox(height: 2),
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
                    ? [
                        'maidCafeEnabled'.tr(),
                        lastSeen == null
                            ? 'maidCafeNeverSeen'.tr()
                            : 'maidCafeLastSeen'.tr(
                                args: [
                                  DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(lastSeen.toLocal()),
                                ],
                              ),
                        ?uptimeLabel,
                      ].join(' · ')
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

/// Workspace quota summary above the fleet: the registration limit with
/// current daemon usage (progress bar), the relay/metric poll throttle and
/// metric retention. Unenforced dimensions read "Unlimited".
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota, required this.daemonCount});

  final MaidCafeQuota quota;
  final int daemonCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final maxDaemons = quota.maxDaemons;
    final atLimit = maxDaemons != null && daemonCount >= maxDaemons;
    return _SettingsSectionCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.speed, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('maidCafeQuota'.tr(), style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            _quotaRow(
              context,
              label: 'maidCafeQuotaMaxDaemons'.tr(),
              value: maxDaemons == null
                  ? 'maidCafeQuotaUnlimited'.tr()
                  : '$daemonCount / $maxDaemons',
            ),
            if (maxDaemons != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (daemonCount / maxDaemons).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: atLimit ? colors.error : colors.primary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _quotaRow(
              context,
              label: 'maidCafeQuotaPollingInterval'.tr(),
              value: quota.pollingIntervalSeconds == null
                  ? 'maidCafeQuotaUnlimited'.tr()
                  : 'maidCafeQuotaSeconds'.tr(
                      args: ['${quota.pollingIntervalSeconds}'],
                    ),
            ),
            const SizedBox(height: 8),
            _quotaRow(
              context,
              label: 'maidCafeQuotaMetricsRetention'.tr(),
              value: quota.metricsRetentionDays == null
                  ? 'maidCafeQuotaUnlimited'.tr()
                  : 'maidCafeQuotaDays'.tr(
                      args: ['${quota.metricsRetentionDays}'],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quotaRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: colors.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The fleet card's signature: the last five samples of the daemon's four
/// host signals (CPU, RAM, load, disk) as threshold-colored bar strips with
/// tabular values. Percent series follow the dashboard's load colors
/// (tertiary ≥ 75%, error ≥ 90%); load is colored by the dashboard's
/// absolute load thresholds (busy ≥ 2, high ≥ 4).
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
                _barRow(
                  context,
                  'CPU',
                  (sample) => sample.cpuPercent / 100,
                  (sample) => '${sample.cpuPercent.round()}%',
                  (sample, colors) =>
                      _percentColor(sample.cpuPercent / 100, colors),
                ),
                const SizedBox(height: 6),
                _barRow(
                  context,
                  'RAM',
                  (sample) => sample.memoryUsedPercent / 100,
                  (sample) => '${sample.memoryUsedPercent.round()}%',
                  (sample, colors) =>
                      _percentColor(sample.memoryUsedPercent / 100, colors),
                ),
                const SizedBox(height: 6),
                _barRow(
                  context,
                  'LOAD',
                  (sample) => sample.cpuCount > 0
                      ? (sample.load1 / sample.cpuCount).clamp(0.0, 1.0)
                      : 0,
                  (sample) => sample.load1.toStringAsFixed(2),
                  (sample, colors) => _loadColor(sample.load1, colors),
                ),
                const SizedBox(height: 6),
                _barRow(
                  context,
                  'DISK',
                  (sample) => _diskRatio(sample),
                  (sample) => sample.diskTotalKb <= 0
                      ? '—'
                      : '${(_diskRatio(sample) * 100).round()}%',
                  (sample, colors) => _percentColor(_diskRatio(sample), colors),
                ),
              ],
            ),
    );
  }

  Widget _barRow(
    BuildContext context,
    String label,
    double Function(MaidCafeMetric) ratioOf,
    String Function(MaidCafeMetric) labelOf,
    Color Function(MaidCafeMetric sample, ColorScheme colors) colorOf,
  ) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latest = samples.isEmpty ? null : samples.last;
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
                          heightFactor: ratioOf(sample).clamp(0.04, 1.0),
                          // FractionallySizedBox lays its child out loosely;
                          // a bare DecoratedBox would collapse to zero size.
                          child: SizedBox.expand(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorOf(sample, colors),
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
            latest == null ? '—' : labelOf(latest),
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

  static double _diskRatio(MaidCafeMetric sample) => sample.diskTotalKb <= 0
      ? 0
      : ((sample.diskTotalKb - sample.diskAvailableKb) / sample.diskTotalKb)
            .clamp(0.0, 1.0);

  static Color _percentColor(double ratio, ColorScheme colors) {
    if (ratio >= 0.9) return colors.error;
    if (ratio >= 0.75) return colors.tertiary;
    return colors.primary;
  }

  static Color _loadColor(double load, ColorScheme colors) {
    if (load >= 4) return colors.error;
    if (load >= 2) return colors.tertiary;
    return colors.primary;
  }
}

String _formatUptime(int seconds) {
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
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
/// Create-credential sheet: label plus optional scopes picked from the
/// fleet's known actions and hosts. Creates through the cloud service so the
/// one-time token can be returned.
class _CreateCredentialSheet extends ConsumerStatefulWidget {
  const _CreateCredentialSheet({required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<_CreateCredentialSheet> createState() =>
      _CreateCredentialSheetState();
}

class _CreateCredentialSheetState
    extends ConsumerState<_CreateCredentialSheet> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _daemonsController = TextEditingController();
  final Set<String> _selectedActionNames = {};
  final Set<String> _selectedHostIds = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _daemonsController.dispose();
    super.dispose();
  }

  List<String> _split(String value) => [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// The actions every daemon in the workspace reported, deduplicated by
  /// name with the most recent label winning.
  List<({String value, String label})> get _actionOptions {
    final daemons =
        ref.watch(maidCafeDaemonsProvider(widget.workspaceId)).asData?.value ??
        const <MaidCafeDaemon>[];
    final labels = <String, String>{};
    for (final daemon in daemons) {
      final actions =
          ref.watch(maidCafeCloudActionsProvider(daemon.id)).asData?.value ??
          const <MaidCafeCloudAction>[];
      for (final action in actions) {
        labels[action.name] = action.label;
      }
    }
    final options = [
      for (final entry in labels.entries)
        (value: entry.key, label: entry.value),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options;
  }

  /// The stable host ids every daemon reported, deduplicated.
  List<({String value, String label})> get _hostOptions {
    final daemons =
        ref.watch(maidCafeDaemonsProvider(widget.workspaceId)).asData?.value ??
        const <MaidCafeDaemon>[];
    final hostIds = <String>{
      for (final daemon in daemons)
        if (daemon.hostId != null && daemon.hostId!.isNotEmpty) daemon.hostId!,
    };
    return [for (final id in hostIds.toList()..sort()) (value: id, label: id)];
  }

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
            actionNames: _selectedActionNames.toList(growable: false),
            hostIds: _selectedHostIds.toList(growable: false),
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
    return SizedBox(
      width: 560,
      child: SheetScaffold(
        titleText: 'maidCafeCredentialCreate'.tr(),
        heightFactor: 0.62,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
            _ScopeMultiSelectField(
              label: 'maidCafeCredentialActionsScope'.tr(),
              options: _actionOptions,
              selected: _selectedActionNames,
              onChanged: (next) => setState(
                () => _selectedActionNames
                  ..clear()
                  ..addAll(next),
              ),
            ),
            const SizedBox(height: 12),
            _ScopeMultiSelectField(
              label: 'maidCafeCredentialHostsScope'.tr(),
              options: _hostOptions,
              selected: _selectedHostIds,
              onChanged: (next) => setState(
                () => _selectedHostIds
                  ..clear()
                  ..addAll(next),
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
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text('maidCafeCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text('maidCafeCredentialCreate'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown-style multi-select for the credential scope pickers. Renders as
/// a form field; the menu lists every option with a checkbox and stays open
/// so several can be toggled in one pass.
class _ScopeMultiSelectField extends StatefulWidget {
  const _ScopeMultiSelectField({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<({String value, String label})> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_ScopeMultiSelectField> createState() => _ScopeMultiSelectFieldState();
}

class _ScopeMultiSelectFieldState extends State<_ScopeMultiSelectField> {
  final MenuController _menuController = MenuController();

  Widget _summary(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (widget.selected.length) {
      0 => Text(
        'maidCafeCredentialUnrestricted'.tr(),
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      1 => Text(
        widget.options
                .where((option) => option.value == widget.selected.first)
                .firstOrNull
                ?.label ??
            widget.selected.first,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      _ => Text(
        'maidCafeCredentialCountSelected'.plural(widget.selected.length),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      builder: (context, controller, child) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: Icon(
              controller.isOpen
                  ? Symbols.keyboard_arrow_up
                  : Symbols.keyboard_arrow_down,
            ),
          ),
          child: _summary(context),
        ),
      ),
      menuChildren: [
        if (widget.options.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'maidCafeCredentialNoOptions'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final option in widget.options)
            CheckboxListTile(
              dense: true,
              value: widget.selected.contains(option.value),
              title: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (checked) {
                final next = Set.of(widget.selected);
                if (checked == true) {
                  next.add(option.value);
                } else {
                  next.remove(option.value);
                }
                widget.onChanged(next);
              },
            ),
      ],
    );
  }
}

/// One-time credential token sheet: shows the freshly minted token in the
/// app's recessed monospace secret block, with a copy action and a curl
/// snippet for invoking daemon actions through the cloud webhook relay.
class _CredentialTokenSheet extends StatelessWidget {
  const _CredentialTokenSheet({required this.token, required this.cloudUrl});

  final String token;
  final String cloudUrl;

  /// Invokes an action through the cloud relay: the daemon polls pending
  /// webhook requests every minute and runs the named action. The body is
  /// the base64 of the JSON payload (`e30=` is `{}`).
  String get _curlSnippet =>
      "curl -sS -X POST '$cloudUrl/api/daemons/<daemon-id>/webhook-requests' \\\n"
      "  -H 'Authorization: Bearer $token' \\\n"
      "  -H 'Content-Type: application/json' \\\n"
      "  -d '{\"name\":\"<action-name>\",\"body\":\"e30=\",\"signature\":\"\"}'\n"
      "# Poll for the result (the daemon runs it within a minute):\n"
      "# curl -sS '$cloudUrl/api/daemons/<daemon-id>/webhook-requests/<request-id>' "
      "-H 'Authorization: Bearer $token'";

  Widget _secretBlock(BuildContext context, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SelectableText(
      text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 560,
      child: SheetScaffold(
        titleText: 'maidCafeCredentialToken'.tr(),
        heightFactor: 0.62,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('maidCafeCredentialTokenHint'.tr()),
            const SizedBox(height: 12),
            _secretBlock(context, token),
            const SizedBox(height: 20),
            Text(
              'maidCafeCredentialCurlTitle'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'maidCafeCredentialCurlHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _secretBlock(context, _curlSnippet),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _curlSnippet)),
                  child: Text('maidCafeCredentialCopyCurl'.tr()),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: token)),
                  child: Text('maidCafeCredentialCopy'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('maidCafeDone'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
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

class _RequestNotificationSheet extends StatefulWidget {
  const _RequestNotificationSheet();

  @override
  State<_RequestNotificationSheet> createState() =>
      _RequestNotificationSheetState();
}

class _RequestNotificationSheetState extends State<_RequestNotificationSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    child: SheetScaffold(
      titleText: 'maidCafeRequestNotification'.tr(),
      heightFactor: 0.5,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'maidCafeNotificationTitle'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: InputDecoration(
              labelText: 'maidCafeNotificationBody'.tr(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('maidCafeCancel'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  title: _titleController.text,
                  body: _bodyController.text,
                )),
                child: Text('maidCafeRequest'.tr()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
