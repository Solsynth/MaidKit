import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
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
/// snippet), notification delivery preferences, and the cloud notification
/// history.
///
/// The page is a tabbed console — fleet (daemon cards with live metric
/// history), credentials and notifications — with the account and workspace
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
  bool _notificationsTopHovered = false;
  bool _notificationsRefreshing = false;
  bool _notificationsUnreadOnly = false;

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
              _notificationsTab(context, workspaceId),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _MaidCafeQuotaCard(workspaceId: workspaceId),
        const SizedBox(height: 16),
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
      final workspaceId = _effectiveWorkspaceId;
      if (workspaceId != null) {
        ref.invalidate(maidCafeNotificationsProvider(workspaceId));
        ref.invalidate(maidCafeUnreadNotificationCountProvider(workspaceId));
      }
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
          ? _SettingsSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('maidCafeNoCredentials'.tr()),
              ),
            )
          : _SettingsSectionCard(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _credentialTile(context, items[i]),
                    if (i < items.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                ],
              ),
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

  /// Notifications tab: a quiet, scan-friendly feed with pull-to-refresh.
  /// On desktop the refresh action appears when the pointer reaches the top
  /// edge, keeping the feed itself free of permanent toolbar chrome.
  Widget _notificationsTab(BuildContext context, String? workspaceId) {
    final unread = workspaceId == null
        ? null
        : ref
              .watch(maidCafeUnreadNotificationCountProvider(workspaceId))
              .asData
              ?.value;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refreshNotifications,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            children: [
              _notificationsHeader(context, unread),
              const SizedBox(height: 16),
              if (workspaceId == null)
                _SettingsSectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('maidCafeNoWorkspaces'.tr()),
                  ),
                )
              else ...[
                _notificationPreferencesBody(context, workspaceId),
                const SizedBox(height: 16),
                _notificationsBody(context, workspaceId),
              ],
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 52,
          child: MouseRegion(
            onEnter: (_) {
              if (mounted) setState(() => _notificationsTopHovered = true);
            },
            onExit: (_) {
              if (mounted && !_notificationsRefreshing) {
                setState(() => _notificationsTopHovered = false);
              }
            },
            child: _notificationsRefreshAffordance(context),
          ),
        ),
      ],
    );
  }

  Widget _notificationPreferencesBody(
    BuildContext context,
    String workspaceId,
  ) {
    return _MaidCafeNotificationPreferencesPanel(
      workspaceId: workspaceId,
      isBusy: (daemonId, topic) =>
          _isBusy(_notificationPreferenceOp(daemonId, topic)),
      onChanged: (daemonId, topic, preference) => _setNotificationPreference(
        context,
        workspaceId,
        daemonId,
        topic,
        preference,
      ),
    );
  }

  String _notificationPreferenceOp(String? daemonId, String topic) =>
      'notification-preference:${daemonId ?? 'all'}:$topic';

  Future<void> _setNotificationPreference(
    BuildContext context,
    String workspaceId,
    String? daemonId,
    String topic,
    MaidCafeNotificationPreferenceLevel? preference,
  ) async {
    await _run(_notificationPreferenceOp(daemonId, topic), () async {
      final service = ref.read(maidCafeServiceProvider);
      if (preference == null) {
        await service.resetNotificationPreference(
          workspaceId: workspaceId,
          daemonId: daemonId,
          topic: topic,
        );
      } else {
        await service.setNotificationPreference(
          workspaceId: workspaceId,
          daemonId: daemonId,
          topic: topic,
          preference: preference,
        );
      }
      ref.invalidate(maidCafeNotificationPreferencesProvider(workspaceId));
    });
  }

  Widget _notificationsHeader(BuildContext context, int? unread) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final markAllBusy = _isBusy(_notificationsOp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Symbols.notifications,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'maidCafeNotifications'.tr(),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    unread == null
                        ? 'maidCafeUnreadCount'.tr(args: ['…'])
                        : 'maidCafeUnreadCount'.tr(args: ['$unread']),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              selected: _notificationsUnreadOnly,
              avatar: const Icon(Symbols.mark_email_unread, size: 18),
              label: Text('maidCafeUnreadOnly'.tr()),
              onSelected: (selected) {
                setState(() => _notificationsUnreadOnly = selected);
              },
            ),
            if (unread != null && unread > 0)
              TextButton.icon(
                onPressed: markAllBusy ? null : () => _markAllRead(context),
                icon: const Icon(Symbols.done_all, size: 18),
                label: Text('maidCafeMarkAllRead'.tr()),
              ),
          ],
        ),
      ],
    );
  }

  Widget _notificationsRefreshAffordance(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _notificationsTopHovered || _notificationsRefreshing;
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.35),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              elevation: 2,
              child: IconButton(
                key: const ValueKey('maidcafe-notifications-refresh'),
                tooltip: 'maidCafeRefresh'.tr(),
                onPressed: _notificationsRefreshing
                    ? null
                    : () {
                        _notificationsTopHovered = false;
                        _refreshNotifications();
                      },
                icon: _notificationsRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.refresh, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshNotifications() async {
    if (_notificationsRefreshing) return;
    final workspaceId = _effectiveWorkspaceId;
    if (workspaceId == null) return;
    if (mounted) {
      setState(() {
        _notificationsRefreshing = true;
        _notificationsTopHovered = true;
      });
    }
    try {
      await Future.wait([
        ref.refresh(maidCafeNotificationsProvider(workspaceId).future),
        ref.refresh(
          maidCafeUnreadNotificationCountProvider(workspaceId).future,
        ),
        ref.refresh(maidCafeNotificationTopicsProvider(workspaceId).future),
        ref.refresh(
          maidCafeNotificationPreferencesProvider(workspaceId).future,
        ),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _notificationsRefreshing = false;
          _notificationsTopHovered = false;
        });
      }
    }
  }

  Widget _notificationsBody(BuildContext context, String workspaceId) {
    final notifications = ref.watch(maidCafeNotificationsProvider(workspaceId));
    return notifications.when(
      loading: () => _NotificationsLoading(),
      error: (error, _) => _SettingsSectionCard(
        child: _recoverableError(context, error, _refreshNotifications),
      ),
      data: (items) {
        final visibleItems = _notificationsUnreadOnly
            ? items.where((item) => item.unread).toList(growable: false)
            : items;
        if (visibleItems.isEmpty) {
          return _NotificationsEmptyState(unreadOnly: _notificationsUnreadOnly);
        }
        return _SettingsSectionCard(
          child: Column(
            children: [
              for (var i = 0; i < visibleItems.length; i++) ...[
                _notificationTile(context, visibleItems[i]),
                if (i < visibleItems.length - 1)
                  const Divider(height: 1, indent: 72, endIndent: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _notificationTile(BuildContext context, MaidCafeNotification item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final daemonName = item.metadata['daemon_name']?.toString();
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : _notificationTopicLabel(item.kind);
    final metadata = [
      item.kind,
      if (daemonName != null && daemonName.isNotEmpty)
        'maidCafeFromServer'.tr(args: [daemonName]),
    ];
    return Container(
      color: item.unread
          ? colors.primaryContainer.withValues(alpha: 0.16)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.unread
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _notificationIcon(item.kind),
              size: 20,
              color: item.unread
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: item.unread ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat(
                        'MMM d, HH:mm',
                      ).format(item.createdAt.toLocal()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (item.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (item.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.82),
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    for (var i = 0; i < metadata.length; i++) ...[
                      if (i > 0)
                        Text(
                          '·',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      Text(
                        metadata[i],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (item.unread) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _notificationIcon(String topic) {
    if (topic.contains('alarm') || topic.contains('failure')) {
      return Symbols.warning;
    }
    if (topic.contains('success') || topic.contains('completed')) {
      return Symbols.check_circle;
    }
    if (topic.contains('daemon') || topic.contains('metric')) {
      return Symbols.dns;
    }
    if (topic.contains('request') || topic.contains('message')) {
      return Symbols.chat;
    }
    return Symbols.notifications;
  }

  String _notificationTopicLabel(String topic) {
    final words = topic.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (words.isEmpty) return 'maidCafeNotifications'.tr();
    return words[0].toUpperCase() + words.substring(1);
  }

  Future<void> _markAllRead(BuildContext context) async {
    final workspaceId = _effectiveWorkspaceId;
    if (workspaceId == null) return;
    await _run(_notificationsOp, () async {
      await ref
          .read(maidCafeServiceProvider)
          .markAllNotificationsRead(workspaceId: workspaceId);
      ref.invalidate(maidCafeNotificationsProvider(workspaceId));
      ref.invalidate(maidCafeUnreadNotificationCountProvider(workspaceId));
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

class _MaidCafeQuotaCard extends ConsumerWidget {
  const _MaidCafeQuotaCard({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(maidCafeQuotaProvider(workspaceId)).asData?.value;
    if (quota == null) return const SizedBox.shrink();
    final daemonCount =
        ref.watch(maidCafeDaemonsProvider(workspaceId)).asData?.value.length ??
        0;
    final maxDaemons = quota.maxDaemons;
    final atLimit = maxDaemons != null && daemonCount >= maxDaemons;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final rows = [
              _QuotaValue(
                label: 'maidCafeQuotaMaxDaemons'.tr(),
                value: maxDaemons == null
                    ? 'maidCafeQuotaUnlimited'.tr()
                    : '$daemonCount / $maxDaemons',
                color: atLimit ? scheme.error : null,
              ),
              _QuotaValue(
                label: 'maidCafeQuotaPollingInterval'.tr(),
                value: quota.pollingIntervalSeconds == null
                    ? 'maidCafeQuotaUnlimited'.tr()
                    : 'maidCafeQuotaSeconds'.tr(
                        args: ['${quota.pollingIntervalSeconds}'],
                      ),
              ),
              _QuotaValue(
                label: 'maidCafeQuotaMetricsRetention'.tr(),
                value: quota.metricsRetentionDays == null
                    ? 'maidCafeQuotaUnlimited'.tr()
                    : 'maidCafeQuotaDays'.tr(
                        args: ['${quota.metricsRetentionDays}'],
                      ),
              ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'maidCafeQuota'.tr(),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                if (compact)
                  Column(
                    children: [
                      for (final row in rows) ...[
                        row,
                        if (row != rows.last) const SizedBox(height: 8),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          SizedBox(
                            height: 34,
                            child: VerticalDivider(
                              color: scheme.outlineVariant,
                              width: 24,
                            ),
                          ),
                        Expanded(child: rows[i]),
                      ],
                    ],
                  ),
                if (maxDaemons != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (daemonCount / maxDaemons).clamp(0.0, 1.0),
                      minHeight: 6,
                      color: atLimit ? scheme.error : scheme.primary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuotaValue extends StatelessWidget {
  const _QuotaValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.end,
          style: theme.textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

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
    // The API returns newest-first; the chart reads oldest → newest.
    final ordered = [...history]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final samples = ordered.length > 24
        ? ordered.sublist(ordered.length - 24)
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        daemon.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        daemon.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: 'IBM Plex Mono',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'maidCafeCopyDaemonId'.tr(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.content_copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: daemon.id)),
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
              child: _MetricHistoryChart(
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

/// The fleet card's signature: a compact history plot for the daemon's four
/// host signals. It uses the same fl_chart vocabulary as the server Activity
/// tab, but keeps the series intentionally small enough for a fleet card.
class _MetricHistoryChart extends StatelessWidget {
  const _MetricHistoryChart({required this.samples, required this.unavailable});

  final List<MaidCafeMetric> samples;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    if (unavailable && samples.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'maidCafeHistoryUnavailable'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (samples.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'maidCafeHistoryUnavailable'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final series = _series(scheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final item in series)
                _MetricLegend(label: item.label, color: item.color),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(samples.length - 1, 1).toDouble(),
                minY: 0,
                maxY: 1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 0.5,
                      getTitlesWidget: (value, meta) => Text(
                        '${(value * 100).toInt()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    maxContentWidth: 180,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (touchedSpots) {
                      if (touchedSpots.isEmpty) return const [];
                      final firstIndex = touchedSpots.first.spotIndex
                          .clamp(0, samples.length - 1)
                          .toInt();
                      final sampledAt = DateFormat(
                        'yyyy-MM-dd HH:mm:ss',
                      ).format(samples[firstIndex].sentAt.toLocal());
                      final items = <LineTooltipItem?>[];
                      for (var i = 0; i < touchedSpots.length; i++) {
                        final spot = touchedSpots[i];
                        if (spot.barIndex < 0 ||
                            spot.barIndex >= series.length) {
                          items.add(null);
                          continue;
                        }
                        final sampleIndex = spot.spotIndex
                            .clamp(0, samples.length - 1)
                            .toInt();
                        final metric = series[spot.barIndex];
                        final prefix = i == 0
                            ? '${'maidCafeMetricSampleTime'.tr(args: [sampledAt])}\n'
                            : '';
                        items.add(
                          LineTooltipItem(
                            '$prefix${metric.label}: '
                            '${metric.valueLabelOf(samples[sampleIndex])}',
                            TextStyle(
                              color: scheme.onInverseSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        );
                      }
                      return items;
                    },
                  ),
                ),
                lineBarsData: [
                  for (final item in series)
                    LineChartBarData(
                      spots: item.spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: item.color,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: samples.length == 1,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 2.5,
                              color: item.color,
                              strokeWidth: 0,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: item == series.first,
                        color: item.color.withValues(alpha: 0.08),
                      ),
                    ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final item in series)
                _MetricLatestValue(
                  label: item.label,
                  value: samples.isEmpty
                      ? '—'
                      : item.valueLabelOf(samples.last),
                  color: item.color,
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<_MetricSeries> _series(ColorScheme scheme) =>
      [
            _MetricSeries(
              label: 'maidCafeMetricCpuUsage'.tr(),
              color: scheme.primary,
              ratioOf: (sample) => (sample.cpuPercent / 100).clamp(0.0, 1.0),
              valueLabelOf: (sample) => '${sample.cpuPercent.round()}%',
            ),
            _MetricSeries(
              label: 'maidCafeMetricMemoryUsage'.tr(),
              color: scheme.tertiary,
              ratioOf: (sample) =>
                  (sample.memoryUsedPercent / 100).clamp(0.0, 1.0),
              valueLabelOf: (sample) => '${sample.memoryUsedPercent.round()}%',
            ),
            _MetricSeries(
              label: 'maidCafeMetricLoadPerCpu'.tr(),
              color: scheme.secondary,
              ratioOf: (sample) => sample.cpuCount > 0
                  ? (sample.load1 / sample.cpuCount).clamp(0.0, 1.0)
                  : 0,
              valueLabelOf: (sample) => sample.cpuCount > 0
                  ? '${sample.load1.toStringAsFixed(2)} '
                        '(${(sample.load1 / sample.cpuCount * 100).round()}%)'
                  : sample.load1.toStringAsFixed(2),
            ),
            _MetricSeries(
              label: 'maidCafeMetricDiskUsed'.tr(),
              color: scheme.error,
              ratioOf: _diskRatio,
              valueLabelOf: (sample) => sample.diskTotalKb <= 0
                  ? '—'
                  : '${(_diskRatio(sample) * 100).round()}%',
            ),
          ]
          .map((item) {
            final spots = [
              for (var i = 0; i < samples.length; i++)
                FlSpot(i.toDouble(), item.ratioOf(samples[i])),
            ];
            return item.copyWith(spots: spots);
          })
          .toList(growable: false);

  static double _diskRatio(MaidCafeMetric sample) => sample.diskTotalKb <= 0
      ? 0
      : ((sample.diskTotalKb - sample.diskAvailableKb) / sample.diskTotalKb)
            .clamp(0.0, 1.0);
}

class _MetricSeries {
  const _MetricSeries({
    required this.label,
    required this.color,
    required this.ratioOf,
    required this.valueLabelOf,
    this.spots = const [],
  });

  final String label;
  final Color color;
  final double Function(MaidCafeMetric) ratioOf;
  final String Function(MaidCafeMetric) valueLabelOf;
  final List<FlSpot> spots;

  _MetricSeries copyWith({required List<FlSpot> spots}) => _MetricSeries(
    label: label,
    color: color,
    ratioOf: ratioOf,
    valueLabelOf: valueLabelOf,
    spots: spots,
  );
}

class _MetricLegend extends StatelessWidget {
  const _MetricLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetricLatestValue extends StatelessWidget {
  const _MetricLatestValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
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

class _NotificationsLoading extends StatelessWidget {
  const _NotificationsLoading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SettingsSectionCard(
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2),
          for (var i = 0; i < 3; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: i == 0 ? 0.72 : 0.58,
                          child: Container(
                            height: 14,
                            color: colors.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 11,
                          color: colors.surfaceContainerHighest,
                        ),
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.84,
                          child: Container(
                            height: 11,
                            color: colors.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < 2) const Divider(height: 1, indent: 72, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState({required this.unreadOnly});

  final bool unreadOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SettingsSectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(
              unreadOnly ? Symbols.mark_email_read : Symbols.notifications_none,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'maidCafeNoNotifications'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaidCafeNotificationPreferencesPanel extends ConsumerWidget {
  const _MaidCafeNotificationPreferencesPanel({
    required this.workspaceId,
    required this.isBusy,
    required this.onChanged,
  });

  final String workspaceId;
  final bool Function(String? daemonId, String topic) isBusy;
  final Future<void> Function(
    String? daemonId,
    String topic,
    MaidCafeNotificationPreferenceLevel? preference,
  )
  onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(maidCafeNotificationTopicsProvider(workspaceId));
    final daemons = ref.watch(maidCafeDaemonsProvider(workspaceId));
    final preferences = ref.watch(
      maidCafeNotificationPreferencesProvider(workspaceId),
    );
    if (topics.hasError) {
      return _SettingsSectionCard(
        child: _preferenceError(
          context,
          topics.error!,
          () => ref.invalidate(maidCafeNotificationTopicsProvider(workspaceId)),
        ),
      );
    }
    if (daemons.hasError) {
      return _SettingsSectionCard(
        child: _preferenceError(
          context,
          daemons.error!,
          () => ref.invalidate(maidCafeDaemonsProvider(workspaceId)),
        ),
      );
    }
    if (preferences.hasError) {
      return _SettingsSectionCard(
        child: _preferenceError(
          context,
          preferences.error!,
          () => ref.invalidate(
            maidCafeNotificationPreferencesProvider(workspaceId),
          ),
        ),
      );
    }
    if (!topics.hasValue || !daemons.hasValue || !preferences.hasValue) {
      return const _SettingsSectionCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }
    final topicItems = topics.requireValue;
    final daemonItems = daemons.requireValue;
    final preferenceMap = <String, MaidCafeNotificationPreference>{
      for (final preference in preferences.requireValue)
        '${preference.daemonId ?? ''}|${preference.topic}': preference,
    };
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'maidCafeNotificationPreferences'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'maidCafeNotificationPreferencesDescription'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _preferenceScope(
            context,
            title: 'maidCafeAllDaemons'.tr(),
            daemonId: null,
            topics: topicItems,
            preferences: preferenceMap,
          ),
          for (final daemon in daemonItems)
            ExpansionTile(
              title: Text(daemon.name),
              subtitle: Text(
                'maidCafeNotificationDaemonOverride'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                _preferenceScope(
                  context,
                  title: daemon.name,
                  daemonId: daemon.id,
                  topics: topicItems,
                  preferences: preferenceMap,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _preferenceScope(
    BuildContext context, {
    required String title,
    required String? daemonId,
    required List<MaidCafeNotificationTopic> topics,
    required Map<String, MaidCafeNotificationPreference> preferences,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (daemonId == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        for (final topic in topics)
          _preferenceTile(
            context,
            daemonId: daemonId,
            topic: topic,
            current:
                preferences['${daemonId ?? ''}|${topic.topic}']?.preference,
          ),
      ],
    );
  }

  Widget _preferenceTile(
    BuildContext context, {
    required String? daemonId,
    required MaidCafeNotificationTopic topic,
    required MaidCafeNotificationPreferenceLevel? current,
  }) {
    final busy = isBusy(daemonId, topic.topic);
    return ListTile(
      dense: true,
      title: Text(topic.description),
      subtitle: Text(topic.topic),
      trailing: SizedBox(
        width: 170,
        child: DropdownButton<MaidCafeNotificationPreferenceLevel?>(
          value: current,
          isExpanded: true,
          isDense: true,
          onChanged: busy
              ? null
              : (preference) => onChanged(daemonId, topic.topic, preference),
          items: [
            DropdownMenuItem<MaidCafeNotificationPreferenceLevel?>(
              value: null,
              child: Text('maidCafeNotificationPreferenceDefault'.tr()),
            ),
            for (final preference in MaidCafeNotificationPreferenceLevel.values)
              DropdownMenuItem<MaidCafeNotificationPreferenceLevel?>(
                value: preference,
                child: Text(_preferenceLabel(preference)),
              ),
          ],
        ),
      ),
    );
  }

  String _preferenceLabel(MaidCafeNotificationPreferenceLevel preference) =>
      switch (preference) {
        MaidCafeNotificationPreferenceLevel.normal =>
          'maidCafeNotificationPreferenceNormal'.tr(),
        MaidCafeNotificationPreferenceLevel.silent =>
          'maidCafeNotificationPreferenceSilent'.tr(),
        MaidCafeNotificationPreferenceLevel.reject =>
          'maidCafeNotificationPreferenceReject'.tr(),
      };

  Widget _preferenceError(
    BuildContext context,
    Object error,
    VoidCallback retry,
  ) {
    final message = error is MaidCafeException ? error.message : '$error';
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
