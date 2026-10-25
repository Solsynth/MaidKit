import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_session_adapter.dart';
import 'terminal_tabs_provider.dart';

/// A pane's bottom band: live readings for the terminal that pane shows.
///
/// The pane view (tabs_screen.dart) draws it under the pane's own body, so in a
/// split every terminal pane reads out its own terminal instead of only the
/// focused one. It is keyed on the terminal id, so a pane that switches to a
/// non-terminal collapses the bar with its own exit animation; a null
/// [terminal] passes a placeholder that animates out.
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

    // No rule above the band and no rules between readings: each reading is a
    // pill resting on the pane's sheet, so the bar groups itself by tone and
    // spacing instead of drawing a table.
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android)
              _TerminalQuickKeys(terminal: widget.terminal),
            if (segments.isNotEmpty)
              SizedBox(
                height: 30,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    MaidKitSpace.md,
                    MaidKitSpace.xs,
                    MaidKitSpace.md,
                    MaidKitSpace.xxs,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: segments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MaidKitSpace.sm),
                  itemBuilder: (context, index) =>
                      Center(child: _StatusPill(child: segments[index])),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One reading in the band, drawn as a pill off the pane's sheet.
///
/// The pill is the whole grouping affordance: two readings never touch, so the
/// band needs no dividers, and a reading that appears or disappears only
/// changes the row's extent.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: MaidKitRadius.pillRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MaidKitSpace.sm,
          vertical: MaidKitSpace.xxs,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
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
          _TerminalKeyboardToggle(terminal: terminal),
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

/// Raise-or-release button for the mobile soft keyboard.
///
/// The pane body sits inside a [Scaffold], which strips the bottom view insets
/// from the media query it hands down, so `MediaQuery.viewInsetsOf` reads zero
/// while the keyboard is up — the button would only ever show it. The platform
/// view still reports the real inset, and its metrics callback is what redraws
/// this button when the keyboard comes or goes.
class _TerminalKeyboardToggle extends StatefulWidget {
  const _TerminalKeyboardToggle({required this.terminal});

  final TerminalSessionAdapter terminal;

  @override
  State<_TerminalKeyboardToggle> createState() =>
      _TerminalKeyboardToggleState();
}

class _TerminalKeyboardToggleState extends State<_TerminalKeyboardToggle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = View.of(context).viewInsets.bottom > 0;
    return IconButton(
      tooltip: visible
          ? 'terminalKeyboardHide'.tr()
          : 'terminalKeyboardShow'.tr(),
      // Putting the keyboard away means releasing the terminal, not only
      // closing the IME: the renderer raises it again on focus gain, so a hide
      // that kept focus would leave the user unable to get it back by tapping
      // the terminal.
      onPressed: visible
          ? widget.terminal.unfocus
          : widget.terminal.showKeyboard,
      icon: Icon(
        visible ? Symbols.keyboard_arrow_down : Symbols.keyboard_arrow_up,
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
