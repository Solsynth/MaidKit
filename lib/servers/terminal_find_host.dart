import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'terminal_session_adapter.dart';

/// Wraps a [TerminalSessionAdapter] view with Cmd/Ctrl+F find UI and
/// terminal-level shortcut handling.
class TerminalFindHost extends StatefulWidget {
  const TerminalFindHost({
    super.key,
    required this.adapter,
    this.autofocus = false,
    this.readOnly = false,
    this.showCursor = true,
    this.transparentBackground,
    this.onKeyEvent,
    this.onOpenFileManagement,
  });

  final TerminalSessionAdapter adapter;
  final bool autofocus;
  final bool readOnly;
  final bool showCursor;
  final bool? transparentBackground;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onOpenFileManagement;

  @override
  State<TerminalFindHost> createState() => _TerminalFindHostState();
}

class _TerminalFindHostState extends State<TerminalFindHost> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  var _open = false;
  var _matchCount = 0;
  var _matchIndex = 0;
  var _caseSensitive = false;

  @override
  void dispose() {
    widget.adapter.findClear();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TerminalFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adapter, widget.adapter)) {
      oldWidget.adapter.findClear();
      _rematch();
    }
  }

  void _openFind() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _rematch();
  }

  void _closeFind() {
    widget.adapter.findClear();
    setState(() {
      _open = false;
      _matchCount = 0;
      _matchIndex = 0;
    });
  }

  void _rematch() {
    final query = _query.text;
    if (query.isEmpty) {
      widget.adapter.findClear();
      setState(() {
        _matchCount = 0;
        _matchIndex = 0;
      });
      return;
    }
    final count = widget.adapter.find(query, caseSensitive: _caseSensitive);
    setState(() {
      _matchCount = count;
      _matchIndex = count == 0 ? 0 : 0;
    });
    if (count > 0) {
      widget.adapter.findJump(0);
    }
  }

  void _next() {
    if (_matchCount == 0) return;
    final next = (_matchIndex + 1) % _matchCount;
    setState(() => _matchIndex = next);
    widget.adapter.findJump(next);
  }

  void _previous() {
    if (_matchCount == 0) return;
    final previous = (_matchIndex - 1 + _matchCount) % _matchCount;
    setState(() => _matchIndex = previous);
    widget.adapter.findJump(previous);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        // Only intercept navigation keys while find is open so Enter still
        // reaches the shell during normal session use.
        if (_open) ...{
          const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
          const SingleActivator(LogicalKeyboardKey.enter): _next,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true):
              _previous,
          const SingleActivator(LogicalKeyboardKey.f3): _next,
          const SingleActivator(LogicalKeyboardKey.f3, shift: true): _previous,
        },
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_open)
              Material(
                color: scheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Symbols.search, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          focusNode: _focus,
                          autofocus: true,
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'terminalFindInTerminal'.tr(),
                          ),
                          onChanged: (_) => _rematch(),
                          onSubmitted: (_) => _next(),
                        ),
                      ),
                      Text(
                        _matchCount == 0
                            ? 'terminalNoResults'.tr()
                            : '${_matchIndex + 1} / $_matchCount',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 4),
                      FilterChip(
                        label: Text('terminalCaseSensitive'.tr()),
                        selected: _caseSensitive,
                        visualDensity: VisualDensity.compact,
                        onSelected: (value) {
                          setState(() => _caseSensitive = value);
                          _rematch();
                        },
                      ),
                      IconButton(
                        tooltip: 'terminalPreviousMatch'.tr(),
                        onPressed: _matchCount == 0 ? null : _previous,
                        icon: const Icon(Symbols.keyboard_arrow_up, size: 20),
                      ),
                      IconButton(
                        tooltip: 'terminalNextMatch'.tr(),
                        onPressed: _matchCount == 0 ? null : _next,
                        icon: const Icon(Symbols.keyboard_arrow_down, size: 20),
                      ),
                      IconButton(
                        tooltip: 'commonClose'.tr(),
                        onPressed: _closeFind,
                        icon: const Icon(Symbols.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: widget.adapter.buildView(
                autofocus: widget.autofocus,
                readOnly: widget.readOnly,
                showCursor: widget.showCursor,
                onOpenFileManagement: widget.onOpenFileManagement,
                transparentBackground: widget.transparentBackground,
                onKeyEvent: widget.onKeyEvent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
