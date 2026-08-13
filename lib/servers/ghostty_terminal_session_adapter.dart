import 'dart:async';
import 'dart:convert';

import 'package:flterm/flterm.dart' as flterm;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:maid_kit/theme.dart';
import 'terminal_color_scheme.dart';
import 'terminal_session_adapter.dart';

/// Terminal adapter backed by flterm's libghostty-vt renderer.
///
/// flterm owns terminal rendering and interaction while this adapter bridges
/// its controller to MaidKit's SSH transport and terminal-find host.
class GhosttyTerminalSessionAdapterFactory
    implements TerminalSessionAdapterFactory {
  const GhosttyTerminalSessionAdapterFactory({
    required this.cursorAnimationEnabled,
    required this.colorScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
  });

  final bool cursorAnimationEnabled;
  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;

  @override
  TerminalSessionAdapter create() => GhosttyTerminalSessionAdapter(
    cursorAnimationEnabled: cursorAnimationEnabled,
    colorScheme: colorScheme,
    transparentBackground: transparentBackground,
    fontFamily: fontFamily,
  );
}

class GhosttyTerminalSessionAdapter implements TerminalSessionAdapter {
  GhosttyTerminalSessionAdapter({
    this.cursorAnimationEnabled = true,
    this.colorScheme = TerminalColorSchemes.defaultScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
  }) : _controller = flterm.TerminalController(
         config: flterm.TerminalConfig(
           scrollbackLimit: 10 * 1024 * 1024,
           cursorBlink: cursorAnimationEnabled,
         ),
       ) {
    _controller.onOutput = (bytes) {
      if (!_disposed) {
        _activity.sentInput(utf8.decode(bytes, allowMalformed: true));
        _outgoingBytes.add(Uint8List.fromList(bytes));
      }
    };
    _controller.onResize = _onResize;
  }

  final bool cursorAnimationEnabled;
  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final flterm.TerminalController _controller;
  final _terminalViewKey = GlobalKey<flterm.TerminalViewState>();
  final flterm.TerminalScrollController _scrollController =
      flterm.TerminalScrollController();
  final _outgoingBytes = StreamController<Uint8List>.broadcast();
  final _resizeEvents = StreamController<TerminalResize>.broadcast();
  final _matches = <_FltermMatch>[];
  final _activity = TerminalActivityTracker();

  var _disposed = false;
  var _lastColumns = 80;
  var _lastRows = 24;

  @override
  Stream<Uint8List> get outgoingBytes => _outgoingBytes.stream;

  @override
  Stream<TerminalResize> get resizeEvents => _resizeEvents.stream;

  @override
  Stream<bool> get taskRunning => _activity.runningChanges;

  @override
  Stream<TerminalTaskActivity> get taskActivity => _activity.changes;

  @override
  bool get isTaskRunning => _activity.isRunning;

  @override
  TerminalTaskActivity get currentTaskActivity => _activity.current;

  @override
  void write(Uint8List bytes) {
    if (!_disposed) {
      _activity.receivedOutput(bytes);
      _controller.write(bytes);
    }
  }

  @override
  void sendInput(String text) {
    if (!_disposed && text.isNotEmpty) {
      _activity.sentInput(text);
      _controller.sendText(text);
    }
  }

  @override
  void showKeyboard() {
    if (!_disposed) _controller.showKeyboard();
  }

  @override
  void hideKeyboard() {
    if (!_disposed) _controller.hideKeyboard();
  }

  @override
  Rect? get cursorGlobalRect => _terminalViewKey.currentState?.globalCursorRect;

  /// Exposes flterm's key encoder for the adapter integration tests and for
  /// callers that need to send a non-text terminal key programmatically.
  void sendKey(flterm.Key key) {
    if (!_disposed) _controller.sendKey(key);
  }

  void _onResize(int columns, int rows) {
    if (_disposed || (columns == _lastColumns && rows == _lastRows)) return;
    _lastColumns = columns;
    _lastRows = rows;
    _resizeEvents.add(
      TerminalResize(
        columns: columns,
        rows: rows,
        // flterm's public resize callback reports cell dimensions. SSH uses
        // columns/rows for its window change; retain a sensible pixel estimate
        // for the existing transport contract.
        pixelWidth: columns * 8,
        pixelHeight: rows * 18,
      ),
    );
  }

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    if (!showCursor) {
      _controller.modeSet(flterm.TerminalMode.cursorVisible(), value: false);
    }

    Widget terminal = flterm.TerminalView(
      key: _terminalViewKey,
      controller: _controller,
      scrollController: _scrollController,
      autofocus: autofocus && !readOnly,
      showKeyboard: !readOnly,
      onKeyEvent: onKeyEvent,
      theme: flterm.TerminalTheme(
        palette: flterm.ColorPalette(
          ansiColors: colorScheme.ansiColors,
          // Keep an opaque palette color for libghostty's color resolution.
          // Transparency belongs to TerminalTheme.backgroundOpacity; passing
          // an alpha-zero palette color is flattened to black by the renderer.
          background: colorScheme.background,
          foreground: colorScheme.foreground,
        ),
        cursor: flterm.CursorTheme(
          color: flterm.DynamicColor.fixed(colorScheme.cursor),
        ),
        cursorMotionDuration: cursorAnimationEnabled
            ? const Duration(milliseconds: 90)
            : Duration.zero,
        selection: flterm.SelectionTheme(
          background: flterm.DynamicColor.fixed(colorScheme.selection),
        ),
        backgroundOpacity: (transparentBackground ?? this.transparentBackground)
            ? 0
            : 1,
        fontFamily: fontFamily,
      ),
    );
    if (readOnly) {
      terminal = _ReadOnlyLogSurface(
        onCopy: _copySelectionToClipboard,
        onSelectAll: _controller.selectAll,
        child: terminal,
      );
    }
    return terminal;
  }

  void _copySelectionToClipboard() {
    if (_disposed) return;
    final text = _controller.selectedText();
    if (text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
  }

  @override
  int find(String query, {bool caseSensitive = false}) {
    findClear();
    if (_disposed || query.isEmpty) return 0;

    final formatter = _controller.createFormatter(
      format: flterm.FormatterFormat.plain,
      unwrap: false,
      trim: false,
    );
    try {
      final needle = caseSensitive ? query : query.toLowerCase();
      final lines = formatter.format().split('\n');
      for (var row = 0; row < lines.length; row++) {
        final line = lines[row];
        final haystack = caseSensitive ? line : line.toLowerCase();
        var from = 0;
        while (true) {
          final start = haystack.indexOf(needle, from);
          if (start < 0) break;
          _matches.add(_FltermMatch(row, start, start + needle.length));
          from = start + 1;
        }
      }
    } finally {
      formatter.dispose();
    }
    if (_matches.isNotEmpty) findJump(0);
    return _matches.length;
  }

  @override
  void findJump(int index) {
    if (_disposed || _matches.isEmpty) return;
    final match = _matches[index.clamp(0, _matches.length - 1)];
    _controller.selectRange(
      start: flterm.Position(row: match.row, col: match.start),
      end: flterm.Position(row: match.row, col: match.end - 1),
    );
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        (match.row * 18.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void findClear() {
    _matches.clear();
    if (!_disposed) _controller.clearSelection();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _matches.clear();
    _controller.dispose();
    _scrollController.dispose();
    await _outgoingBytes.close();
    await _resizeEvents.close();
    await _activity.dispose();
  }
}

class _FltermMatch {
  const _FltermMatch(this.row, this.start, this.end);

  final int row;
  final int start;
  final int end;
}

/// Focus host for read-only log surfaces on the ghostty renderer.
///
/// flterm's [flterm.TerminalView] has no read-only keyboard mode: any focused
/// view encodes keystrokes into the terminal buffer. Like the xterm adapter's
/// read-only path, the view stays excluded from focus so typing never mutates
/// the log, while this host owns the focus and routes copy/select-all.
///
/// Other keys are intentionally left to bubble: the excluded view can never
/// receive them, and ancestors (find shortcuts, app shortcuts) still work.
class _ReadOnlyLogSurface extends StatefulWidget {
  const _ReadOnlyLogSurface({
    required this.onCopy,
    required this.onSelectAll,
    required this.child,
  });

  final VoidCallback onCopy;
  final VoidCallback onSelectAll;
  final Widget child;

  @override
  State<_ReadOnlyLogSurface> createState() => _ReadOnlyLogSurfaceState();
}

class _ReadOnlyLogSurfaceState extends State<_ReadOnlyLogSurface> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command = apple
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;

    if (command && event.logicalKey == LogicalKeyboardKey.keyC) {
      widget.onCopy();
      return KeyEventResult.handled;
    }
    if (command && event.logicalKey == LogicalKeyboardKey.keyA) {
      widget.onSelectAll();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // flterm's own tap handler cannot focus an ExcludeFocus'd subtree, so
        // focus this host on any pointer press inside the log surface.
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: ExcludeFocus(child: widget.child),
      ),
    );
  }
}
