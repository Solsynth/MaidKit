import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'privacy_preferences.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

/// What an empty pane shows: the workspace's command palette, inline.
///
/// An empty pane is not a dead end — it is one question, "what goes here?" —
/// so it is answered with the same searchable list the session-actions palette
/// uses, over everything a pane can mount: a terminal on any host, the file
/// manager, a server page, each assets page, projects, an agent chat, the cloud
/// console, settings and the dashboard. Picking an entry mounts it in this pane
/// when [paneId] names one, and opens a new workspace tab otherwise (the
/// no-tabs intro).
class PaneLauncher extends ConsumerStatefulWidget {
  const PaneLauncher({
    super.key,
    required this.paneId,
    this.compact = false,
    this.focused = false,
  });

  /// The empty pane to fill. Null for the whole-workspace intro, where a
  /// choice opens a tab of its own.
  final String? paneId;

  /// Sizes the block down for a split pane rather than the whole workspace.
  final bool compact;

  /// Whether this launcher's pane is the live one.
  ///
  /// A split leaves its new, empty pane live, and the one thing to do there is
  /// choose what goes into it, so a live launcher owns the keyboard. The claim
  /// waits for the frame that made the pane live: whatever closed just before
  /// — the command palette that ran the split — restores the keyboard to its
  /// previous owner on that frame, and the newer claim has to land after it.
  final bool focused;

  @override
  ConsumerState<PaneLauncher> createState() => _PaneLauncherState();
}

/// One row of the launcher: an icon, a name, and what mounting it runs.
class _LauncherEntry {
  const _LauncherEntry({
    required this.label,
    required this.icon,
    this.hint,
    this.run,
  });

  final String label;
  final IconData icon;
  final String? hint;

  /// Null when this build cannot run the entry; the row is then left out
  /// rather than offered and refused.
  final Future<void> Function()? run;
}

class _PaneLauncherState extends ConsumerState<PaneLauncher> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  var _query = '';

  @override
  void initState() {
    super.initState();
    _claimKeyboard();
  }

  @override
  void didUpdateWidget(covariant PaneLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) _claimKeyboard();
  }

  void _claimKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focused || _focusNode.hasFocus) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openFiles(Server server) async {
    // The file manager talks to the host over SFTP (or the daemon's file API
    // in a browser), so a native build needs the session first.
    if (!kIsWeb) {
      final manager = ref.read(connectionManagerProvider);
      if (manager.clientFor(server.id) == null &&
          !await connectForStatistics(context, ref, server)) {
        return;
      }
      if (!mounted) return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .openFileManagement(server, paneId: widget.paneId);
  }

  List<_LauncherEntry> _entries(List<Server> servers) {
    final notifier = ref.read(terminalTabsProvider.notifier);
    final paneId = widget.paneId;
    final hideAddresses = ref.watch(hideServerAddressesProvider);

    // A browser has no SSH socket: only a host it can reach through a daemon
    // offers a terminal there, the same rule the command palette applies.
    bool reachable(Server server) =>
        !kIsWeb ||
        server.connectionType == ServerConnectionType.maidcafe.name ||
        server.hasMaidCafeTerminalRoute;

    return [
      for (final server in servers) ...[
        _LauncherEntry(
          label: 'sessionsNewTerminalOn'.tr(args: [server.name]),
          icon: Symbols.terminal,
          hint: serverAddressLabel(server, hideAddresses: hideAddresses),
          run: reachable(server)
              ? () => openTerminalFor(context, ref, server, paneId: paneId)
              : null,
        ),
        _LauncherEntry(
          label: 'sessionsOpenFileTransfer'.tr(args: [server.name]),
          icon: Symbols.folder,
          run: reachable(server) ? () => _openFiles(server) : null,
        ),
        _LauncherEntry(
          label: '${'serversDetailedView'.tr()} · ${server.name}',
          icon: Symbols.dns,
          run: () async => notifier.openServerDetails(server, paneId: paneId),
        ),
      ],
      _LauncherEntry(
        label: 'tabDashboard'.tr(),
        icon: Symbols.dashboard,
        run: () async => notifier.openDashboard(paneId: paneId),
      ),
      _LauncherEntry(
        label: 'assetsConnections'.tr(),
        icon: Symbols.inventory_2,
        run: () async => notifier.openAssets(paneId: paneId),
      ),
      _LauncherEntry(
        label: 'tabGithub'.tr(),
        icon: Symbols.rocket_launch,
        run: () async =>
            notifier.openAssets(section: AssetsSection.github, paneId: paneId),
      ),
      _LauncherEntry(
        label: 'assetsCredentialsTitle'.tr(),
        icon: Symbols.key,
        run: () async => notifier.openAssets(
          section: AssetsSection.credentials,
          paneId: paneId,
        ),
      ),
      _LauncherEntry(
        label: 'tabSnippets'.tr(),
        icon: Symbols.code,
        run: () async => notifier.openAssets(
          section: AssetsSection.snippets,
          paneId: paneId,
        ),
      ),
      _LauncherEntry(
        label: 'tabProjects'.tr(),
        icon: Symbols.deployed_code,
        run: () async => notifier.openProjects(paneId: paneId),
      ),
      _LauncherEntry(
        label: 'agentNewConversation'.tr(),
        icon: Symbols.smart_toy,
        run: () async => notifier.openAgentChat(paneId: paneId),
      ),
      _LauncherEntry(
        label: 'maidCafeCloudTitle'.tr(),
        icon: Symbols.cloud,
        run: () async => notifier.openMaidCafeCloud(paneId: paneId),
      ),
      _LauncherEntry(
        label: 'tabSettings'.tr(),
        icon: Symbols.settings,
        run: () async => notifier.openSettings(paneId: paneId),
      ),
    ].where((entry) => entry.run != null).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final servers =
        ref.watch(serversProvider).asData?.value ?? const <Server>[];
    final query = _query.trim().toLowerCase();
    final entries = _entries(servers)
        .where(
          (entry) =>
              query.isEmpty ||
              entry.label.toLowerCase().contains(query) ||
              (entry.hint?.toLowerCase().contains(query) ?? false),
        )
        .toList();
    final padding = widget.compact ? 16.0 : 32.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - padding * 2).clamp(
          0.0,
          widget.compact ? 520.0 : 560.0,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - padding * 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.compact) ...[
                      Text(
                        'sessionsSearchActions'.tr(),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'sessionsSearchActions'.tr(),
                        prefixIcon: const Icon(Symbols.search, size: 20),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'commonClearSearch'.tr(),
                                icon: const Icon(Symbols.close, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'serversNoMatches'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (final entry in entries)
                        ListTile(
                          dense: widget.compact,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Icon(entry.icon, size: 20),
                          title: Text(entry.label),
                          subtitle: entry.hint == null
                              ? null
                              : Text(
                                  entry.hint!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => entry.run?.call(),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
