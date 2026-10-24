import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'privacy_preferences.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_session_adapter.dart';
import 'terminal_tabs_provider.dart';

/// The workspace's bottom band: live readings for the focused terminal.
///
/// The pane tab workspace (tabs_screen.dart) draws it under the pane layout,
/// keyed on the terminal id so a dashboard behind the strip keeps its own exit
/// animation instead of the bar swapping to a stale readout. A non-terminal
/// focus passes a null [terminal] and the bar animates out.
class AnimatedTerminalStatusBar extends StatelessWidget {
  const AnimatedTerminalStatusBar({
    required this.session,
    required this.terminal,
    required this.terminalId,
    required this.transport,
    super.key,
  });

  final SshSessionInfo? session;
  final TerminalSessionAdapter? terminal;
  final String? terminalId;
  final TerminalTransport? transport;

  @override
  Widget build(BuildContext context) {
    final activeTerminal = terminal;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
      transitionBuilder: (child, animation) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return ClipRect(
          child: SizeTransition(
            sizeFactor: curve,
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(curve),
              child: FadeTransition(opacity: curve, child: child),
            ),
          ),
        );
      },
      child: activeTerminal == null
          ? const SizedBox.shrink(key: ValueKey('no-session'))
          : _TerminalStatusBar(
              key: ValueKey(activeTerminal),
              session: session,
              terminal: activeTerminal,
              terminalId: terminalId!,
              transport: transport,
            ),
    );
  }
}

class _TerminalStatusBar extends ConsumerStatefulWidget {
  const _TerminalStatusBar({
    required this.session,
    required this.terminal,
    required this.terminalId,
    required this.transport,
    super.key,
  });

  final SshSessionInfo? session;
  final TerminalSessionAdapter terminal;
  final String terminalId;

  /// Which transport serves this terminal, or null when the tab predates the
  /// information.
  final TerminalTransport? transport;

  @override
  ConsumerState<_TerminalStatusBar> createState() => _TerminalStatusBarState();
}

class _TerminalStatusBarState extends ConsumerState<_TerminalStatusBar> {
  static const _pingInterval = Duration(seconds: 5);

  Timer? _pingTimer;
  Duration? _latency;
  var _measuringLatency = false;

  @override
  void initState() {
    super.initState();
    _measureLatency();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _measureLatency());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _measureLatency() async {
    if (_measuringLatency) return;
    _measuringLatency = true;
    try {
      final latency = await ref
          .read(connectionManagerProvider)
          .measureTerminalLatency(widget.terminalId);
      if (mounted) setState(() => _latency = latency);
    } finally {
      _measuringLatency = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final valueStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Load, memory and uptime are gone from this bar: they were only ever
    // fresh while the dashboard's background refresh ran, and the dashboard
    // is exactly what is not focused when a terminal is. What stays is what
    // this bar measures or knows for itself — transport, connection state, a
    // ping it takes on its own timer, and the host's static label.
    final systemLabel = [
      widget.session?.systemInfo?.distribution,
      widget.session?.systemInfo?.kernel,
    ].whereType<String>().join(' · ');

    final segments = <Widget>[
      if (widget.transport case final transport?)
        _StatusBarTransport(transport: transport),
      if (widget.session case final activeSession?)
        _StatusBarIdentity(session: activeSession),
      if (_latency case final latency?)
        _StatusBarMetric(
          icon: Symbols.network_ping,
          tooltip: 'terminalSshPing'.tr(),
          value: '${latency.inMilliseconds} ms',
          valueColor: _statusBarPingColor(latency, scheme),
          mutedStyle: mutedStyle,
          valueStyle: valueStyle,
        ),
      if (systemLabel.isNotEmpty)
        Tooltip(
          message: systemLabel,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(systemLabel, style: mutedStyle),
        ),
    ];

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android)
                _TerminalQuickKeys(terminal: widget.terminal),
              if (segments.isNotEmpty)
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: segments.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 12,
                          color: scheme.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    itemBuilder: (context, index) =>
                        Center(child: segments[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalQuickKeys extends StatefulWidget {
  const _TerminalQuickKeys({required this.terminal});

  final TerminalSessionAdapter terminal;

  @override
  State<_TerminalQuickKeys> createState() => _TerminalQuickKeysState();
}

class _TerminalQuickKeysState extends State<_TerminalQuickKeys> {
  static const _commonKeys = [
    ('Ctrl+C', '\u0003'),
    ('Ctrl+D', '\u0004'),
    ('Ctrl+L', '\u000c'),
    ('Tab', '\t'),
    ('Esc', '\u001b'),
    ('↑', '\u001b[A'),
    ('↓', '\u001b[B'),
    ('←', '\u001b[D'),
    ('→', '\u001b[C'),
    ('Enter', '\r'),
  ];

  static const _extraKeys = [
    ('Ctrl+Z', '\u001a'),
    ('Ctrl+A', '\u0001'),
    ('Ctrl+E', '\u0005'),
    ('Ctrl+U', '\u0015'),
    ('PgUp', '\u001b[5~'),
    ('PgDn', '\u001b[6~'),
  ];

  static const _allKeys = [..._commonKeys, ..._extraKeys];

  final _scrollController = ScrollController();
  var _expanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle() {
    final expanded = !_expanded;
    setState(() => _expanded = expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        expanded ? _scrollController.position.maxScrollExtent : 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final terminal = widget.terminal;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final keys = _expanded ? _allKeys : _commonKeys;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: ListView.separated(
                key: ValueKey(_expanded),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                scrollDirection: Axis.horizontal,
                itemCount: keys.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final (label, input) = keys[index];
                  return TextButton(
                    onPressed: () => terminal.sendInput(input),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(label),
                  );
                },
              ),
            ),
          ),
          IconButton(
            tooltip: keyboardVisible
                ? 'terminalKeyboardHide'.tr()
                : 'terminalKeyboardShow'.tr(),
            onPressed: keyboardVisible
                ? terminal.hideKeyboard
                : terminal.showKeyboard,
            icon: Icon(
              keyboardVisible
                  ? Symbols.keyboard_arrow_down
                  : Symbols.keyboard_arrow_up,
            ),
          ),
          IconButton(
            tooltip: _expanded
                ? 'terminalKeysFewer'.tr()
                : 'terminalKeysMore'.tr(),
            onPressed: _toggle,
            icon: Icon(_expanded ? Symbols.expand_less : Symbols.expand_more),
          ),
        ],
      ),
    );
  }
}

class _StatusBarIdentity extends StatelessWidget {
  const _StatusBarIdentity({required this.session});

  final SshSessionInfo session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, color) = switch (session.status) {
      SessionStatus.connected => ('commonConnected'.tr(), scheme.primary),
      SessionStatus.connecting => ('commonConnecting'.tr(), scheme.tertiary),
      SessionStatus.failed => ('commonFailed'.tr(), scheme.error),
      SessionStatus.closed => (
        'commonNotConnected'.tr(),
        scheme.onSurfaceVariant,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        const SizedBox(width: 8),
        Text(
          session.serverName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The transport a terminal runs over: an icon, with the name in a tooltip.
///
/// The bar is a row of numbers and names, and the transport is a constant of the
/// session rather than a reading, so it stays an icon — the tooltip answers
/// "which one is this?" without taking width from the metrics.
class _StatusBarTransport extends StatelessWidget {
  const _StatusBarTransport({required this.transport});

  final TerminalTransport transport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (transport) {
      TerminalTransport.ssh => Symbols.terminal,
      // A serial terminal is a cable, not a network session.
      TerminalTransport.serial => Symbols.cable,
      // A daemon dialed directly, versus one reached through the cloud.
      TerminalTransport.maidCafeDirect => Symbols.dns,
      TerminalTransport.maidCafeRelay => Symbols.cloud,
    };
    return Tooltip(
      message: transport.labelKey.tr(),
      waitDuration: const Duration(milliseconds: 400),
      child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
    );
  }
}

class _StatusBarMetric extends StatelessWidget {
  const _StatusBarMetric({
    required this.icon,
    required this.tooltip,
    required this.value,
    required this.mutedStyle,
    required this.valueStyle,
    this.valueColor,
  });

  final IconData icon;
  final String tooltip;
  final String value;
  final TextStyle? mutedStyle;
  final TextStyle? valueStyle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            value,
            style: (valueStyle ?? mutedStyle)?.copyWith(
              color: valueColor ?? valueStyle?.color ?? mutedStyle?.color,
            ),
          ),
        ],
      ),
    );
  }
}

Color? _statusBarPingColor(Duration latency, ColorScheme scheme) {
  if (latency >= const Duration(milliseconds: 250)) return scheme.error;
  if (latency >= const Duration(milliseconds: 100)) return scheme.tertiary;
  return null;
}

/// Empty-state server picker used for the full workspace and for empty panes.
class SessionIntro extends ConsumerWidget {
  const SessionIntro({
    super.key,
    required this.servers,
    required this.tabs,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    this.compact = false,
  });

  final AsyncValue<List<Server>> servers;
  final TerminalTabsState tabs;
  final Future<void> Function(Server server) onOpenTerminal;
  final Future<void> Function(Server server) onOpenFiles;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => servers.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) =>
        Center(child: Text('serversLoadError'.tr(args: [error.toString()]))),
    data: (servers) => servers.isEmpty
        ? Center(
            child: FilledButton.icon(
              // The dashboard owns the add-server action; bring it back so the
              // user can create the first server from an empty workspace.
              onPressed: () =>
                  ref.read(terminalTabsProvider.notifier).openDashboard(),
              icon: const Icon(Symbols.add),
              label: Text('serversAddServer'.tr()),
            ),
          )
        : _TerminalServerGrid(
            servers: servers,
            tabs: tabs,
            compact: compact,
            onOpenTerminal: onOpenTerminal,
            onOpenFiles: onOpenFiles,
          ),
  );
}

class _TerminalServerGrid extends ConsumerWidget {
  const _TerminalServerGrid({
    required this.servers,
    required this.tabs,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    this.compact = false,
  });

  final List<Server> servers;
  final TerminalTabsState tabs;
  final Future<void> Function(Server server) onOpenTerminal;
  final Future<void> Function(Server server) onOpenFiles;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    return GridView.builder(
      padding: EdgeInsets.all(compact ? 12 : 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 320 : 380,
        mainAxisExtent: compact ? 168 : 180,
        mainAxisSpacing: compact ? 12 : 16,
        crossAxisSpacing: compact ? 12 : 16,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final openCount = tabs.tabs
            .where((tab) => tab.serverId == server.id)
            .length;
        // A browser can only reach a terminal over the MaidCafe daemon
        // WebSocket, and it has no local disk or SFTP for the file manager.
        final canOpenTerminal =
            !kIsWeb ||
            server.connectionType == ServerConnectionType.maidcafe.name ||
            server.hasMaidCafeTerminalRoute;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Symbols.terminal, size: 22),
                const SizedBox(height: 12),
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  serverAddressLabel(server, hideAddresses: hideAddresses),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                _ServerCardActions(
                  openCount: openCount,
                  onOpenTerminal: canOpenTerminal
                      ? () => onOpenTerminal(server)
                      : null,
                  onOpenFiles: kIsWeb ? null : () => onOpenFiles(server),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Action row that collapses to icon buttons when the card is narrow (split panes).
class _ServerCardActions extends StatelessWidget {
  const _ServerCardActions({
    required this.openCount,
    required this.onOpenTerminal,
    required this.onOpenFiles,
  });

  final int openCount;

  /// Null when the action cannot work on this platform (a browser has neither
  /// SSH on this server nor a filesystem); the button is then omitted.
  final VoidCallback? onOpenTerminal;
  final VoidCallback? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Split panes often leave cards under ~260px — use icon-only actions.
        final narrow = constraints.maxWidth < 260;
        if (narrow) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'sessionsOpenCount'.tr(args: ['$openCount']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (onOpenTerminal != null)
                IconButton.filledTonal(
                  tooltip: 'sessionsNewTerminal'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenTerminal,
                  icon: const Icon(Symbols.add, size: 20),
                ),
              if (onOpenFiles != null)
                IconButton(
                  tooltip: 'sessionsOpenFileManagement'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenFiles,
                  icon: const Icon(Symbols.folder, size: 20),
                ),
            ],
          );
        }
        return Row(
          children: [
            Text(
              'sessionsOpenCount'.tr(args: ['$openCount']),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            if (onOpenTerminal != null)
              FilledButton.tonalIcon(
                onPressed: onOpenTerminal,
                icon: const Icon(Symbols.add),
                label: Text('sessionsNewTerminal'.tr()),
              ),
            if (onOpenFiles != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'sessionsOpenFileManagement'.tr(),
                onPressed: onOpenFiles,
                icon: const Icon(Symbols.folder),
              ),
            ],
          ],
        );
      },
    );
  }
}
