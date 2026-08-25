import 'dart:async';
import 'dart:convert';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/theme.dart';
import 'maidcafe_push.dart';
import 'terminal_color_scheme.dart';
import 'terminal_session_adapter.dart';
import 'terminal_keyword_highlight.dart';

/// Terminal adapter backed by MaidTerm's libghostty-vt renderer.
///
/// MaidTerm owns terminal rendering and interaction while this adapter bridges
/// its controller to MaidKit's SSH transport and terminal-find host.
class MaidTermSessionAdapterFactory implements TerminalSessionAdapterFactory {
  const MaidTermSessionAdapterFactory({
    required this.cursorAnimationEnabled,
    required this.colorScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
    this.selectToCopyEnabled = false,
    this.shiftInsertPasteEnabled = true,
    this.keywordHighlightEnabled = true,
  });

  final bool cursorAnimationEnabled;
  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final bool selectToCopyEnabled;
  final bool shiftInsertPasteEnabled;
  final bool keywordHighlightEnabled;

  @override
  TerminalSessionAdapter create() => MaidTermSessionAdapter(
    cursorAnimationEnabled: cursorAnimationEnabled,
    colorScheme: colorScheme,
    transparentBackground: transparentBackground,
    fontFamily: fontFamily,
    selectToCopyEnabled: selectToCopyEnabled,
    shiftInsertPasteEnabled: shiftInsertPasteEnabled,
    keywordHighlightEnabled: keywordHighlightEnabled,
  );
}

class MaidTermSessionAdapter implements TerminalSessionAdapter {
  MaidTermSessionAdapter({
    this.cursorAnimationEnabled = true,
    this.colorScheme = TerminalColorSchemes.defaultScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
    bool selectToCopyEnabled = false,
    bool shiftInsertPasteEnabled = true,
    bool keywordHighlightEnabled = true,
  }) : _selectToCopyEnabled = selectToCopyEnabled,
       _shiftInsertPasteEnabled = shiftInsertPasteEnabled,
       _keywordHighlightEnabled = keywordHighlightEnabled,
       _controller = maidterm.TerminalController(
         config: maidterm.TerminalConfig(
           scrollbackLimit: 10 * 1024 * 1024,
           cursorBlink: cursorAnimationEnabled,
         ),
       ) {
    _clipboard = createHostClipboardBridge(sendResponse: sendInput);
    _controller.onOutput = (bytes) {
      if (!_disposed) {
        _activity.sentInput(utf8.decode(bytes, allowMalformed: true));
        _outgoingBytes.add(Uint8List.fromList(bytes));
      }
    };
    _controller.onResize = _onResize;
    _controller.onNotification = _handleNotification;
    if (selectToCopyEnabled) {
      _controller.addListener(_onSelectionMaybeChanged);
    }
  }

  final bool cursorAnimationEnabled;
  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final bool _selectToCopyEnabled;
  final bool _shiftInsertPasteEnabled;
  final bool _keywordHighlightEnabled;
  final maidterm.TerminalController _controller;
  late final TerminalClipboardBridge _clipboard;
  final _terminalViewKey = GlobalKey<maidterm.TerminalViewState>();

  final maidterm.TerminalScrollController _scrollController =
      maidterm.TerminalScrollController();
  final _outgoingBytes = StreamController<Uint8List>.broadcast();
  final _resizeEvents = StreamController<TerminalResize>.broadcast();
  final _matches = <_MaidTermMatch>[];
  final _activity = TerminalActivityTracker();

  /// Tracks the last auto-copied selection text so we only write to the
  /// clipboard when the selection actually changes.
  String? _lastAutoCopiedSelection;

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
  String? get currentDirectory =>
      TerminalWorkingDirectoryTracker.decode(_controller.pwd);

  @override
  void write(Uint8List bytes) {
    if (!_disposed) {
      _clipboard.add(bytes);
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

  /// Exposes MaidTerm's key encoder for the adapter integration tests and for
  /// callers that need to send a non-text terminal key programmatically.
  void sendKey(maidterm.Key key) {
    if (!_disposed) _controller.sendKey(key);
  }

  void _onResize(int columns, int rows, int pixelWidth, int pixelHeight) {
    if (_disposed || (columns == _lastColumns && rows == _lastRows)) return;
    _lastColumns = columns;
    _lastRows = rows;
    _resizeEvents.add(
      TerminalResize(
        columns: columns,
        rows: rows,
        // Physical-pixel viewport size reported by the renderer, matching
        // what a native terminal exposes through TIOCGWINSZ so remote
        // kitty-graphics clients size images correctly.
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      ),
    );
  }

  /// Surfaces OSC 9 / OSC 777;notify / OSC 99 desktop notification requests
  /// from the remote shell as system notifications, mirroring MaidTerm's own
  /// local-session behavior. Suppressed while the user is attending the app.
  Future<void> _handleNotification(String title, String body) async {
    if (_disposed || await _userAttending()) return;
    try {
      await showSystemNotification(
        // OSC 9 carries no title; fall back to the app name like MaidTerm.
        title: title.trim().isEmpty ? 'MaidKit' : title.trim(),
        body: body,
        channelId: 'maidterm_session',
        channelName: 'Terminal sessions',
        channelDescription: 'Notifications from remote terminal sessions',
      );
    } catch (_) {
      // No notification plugin (tests, web): drop the request quietly.
    }
  }

  /// Whether the user is currently looking at the app: window focus on
  /// desktop, lifecycle state elsewhere. A missing window manager (tests,
  /// the WebView2 title-bar engine) counts as attended so notifications are
  /// never shown from a surface that cannot see the terminal.
  Future<bool> _userAttending() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      try {
        return await windowManager.isFocused();
      } catch (_) {
        return true;
      }
    }
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    if (!showCursor) {
      _controller.modeSet(maidterm.TerminalMode.cursorVisible(), value: false);
    }

    final effectiveKeyEvent = !readOnly && _shiftInsertPasteEnabled
        ? _wrapKeyEventForShiftInsert(onKeyEvent)
        : onKeyEvent;

    final theme = maidterm.TerminalTheme(
      palette: maidterm.ColorPalette(
        ansiColors: colorScheme.ansiColors,
        // Keep an opaque palette color for libghostty's color resolution.
        // Transparency belongs to TerminalTheme.backgroundOpacity; passing
        // an alpha-zero palette color is flattened to black by the renderer.
        background: colorScheme.background,
        foreground: colorScheme.foreground,
      ),
      cursor: maidterm.CursorTheme(
        color: maidterm.DynamicColor.fixed(colorScheme.cursor),
      ),
      cursorMotionDuration: cursorAnimationEnabled
          ? const Duration(milliseconds: 90)
          : Duration.zero,
      selection: maidterm.SelectionTheme(
        background: maidterm.DynamicColor.fixed(colorScheme.selection),
      ),
      backgroundOpacity: (transparentBackground ?? this.transparentBackground)
          ? 0
          : 1,
      fontFamily: fontFamily,
      // Underline keyword matches without touching their ANSI colors.
      hyperlink: _keywordHighlightEnabled
          ? _keywordHyperlinkTheme
          : const maidterm.HyperlinkTheme(),
    );

    Widget terminal = maidterm.TerminalView(
      key: _terminalViewKey,
      controller: _controller,
      scrollController: _scrollController,
      autofocus: autofocus && !readOnly,
      showKeyboard: !readOnly,
      onKeyEvent: effectiveKeyEvent,
      linkSettings: _keywordHighlightEnabled
          ? _buildKeywordLinkSettings()
          : const maidterm.LinkSettings(),
      theme: theme,
    );
    if (readOnly) {
      terminal = _ReadOnlyLogSurface(
        onCopy: _copySelectionToClipboard,
        onSelectAll: _controller.selectAll,
        child: terminal,
      );
    }
    if (readOnly) return terminal;
    return AppContextMenuRegion(
      menuBuilder: () => terminalContextMenu(
        onOpenFileManagement: onOpenFileManagement,
        hasSelection: _controller.hasSelection,
        canPaste: true,
        onCopy: _copySelectionToClipboard,
        onPaste: () => unawaited(_pasteFromClipboard()),
        onSelectAll: _controller.selectAll,
      ),
      child: terminal,
    );
  }

  /// Underline style applied to idle keyword matches. Uses a single accent
  /// color because the renderer shares one link style across all matches.
  static const _keywordHyperlinkTheme = maidterm.HyperlinkTheme(
    idle: maidterm.HyperlinkStyle(
      underline: maidterm.UnderlineStyle.single,
      underlineColor: Color(0xFF80D8FF),
    ),
    highlighted: maidterm.HyperlinkStyle(
      underline: maidterm.UnderlineStyle.single,
      underlineColor: Color(0xFF80D8FF),
    ),
  );

  maidterm.LinkSettings _buildKeywordLinkSettings() => maidterm.LinkSettings(
    types: {maidterm.LinkType.custom},
    modifier: maidterm.ActivationModifier.primary,
    rules: [
      for (final rule in terminalKeywordRules)
        maidterm.LinkRule.regex(
          id: rule.category.name,
          pattern: rule.pattern,
          highlightMode: maidterm.LinkHighlightMode.always,
        ),
    ],
  );

  FocusOnKeyEventCallback _wrapKeyEventForShiftInsert(
    FocusOnKeyEventCallback? delegate,
  ) => (node, event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_pasteForShiftInsert());
      return KeyEventResult.handled;
    }
    return delegate?.call(node, event) ?? KeyEventResult.ignored;
  };

  /// Pastes the current selection when select-to-copy is enabled, otherwise
  /// the system clipboard. Triggered by Shift+Insert.
  Future<void> _pasteForShiftInsert() async {
    if (_disposed) return;
    String? text;
    if (_selectToCopyEnabled && _controller.hasSelection) {
      final selected = _controller.selectedText();
      if (selected.isNotEmpty) text = selected;
    }
    if (text == null) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    }
    if (text != null && text.isNotEmpty && !_disposed) {
      _controller.paste(text);
    }
  }

  /// Auto-copies the active selection to the clipboard (select-to-copy).
  ///
  /// The controller fires this on every state change, so we diff against the
  /// last copied text and only write when it actually changes.
  void _onSelectionMaybeChanged() {
    if (_disposed || !_selectToCopyEnabled) return;
    if (!_controller.hasSelection) {
      _lastAutoCopiedSelection = null;
      return;
    }
    final text = _controller.selectedText();
    if (text.isEmpty) {
      _lastAutoCopiedSelection = null;
      return;
    }
    if (text == _lastAutoCopiedSelection) return;
    _lastAutoCopiedSelection = text;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void _copySelectionToClipboard() {
    if (_disposed) return;
    final text = _controller.selectedText();
    if (text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_disposed) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && !_disposed) {
      _controller.paste(text);
    }
  }

  @override
  int find(String query, {bool caseSensitive = false}) {
    findClear();
    if (_disposed || query.isEmpty) return 0;

    final formatter = _controller.createFormatter(
      format: maidterm.FormatterFormat.plain,
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
          _matches.add(_MaidTermMatch(row, start, start + needle.length));
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
      start: maidterm.Position(row: match.row, col: match.start),
      end: maidterm.Position(row: match.row, col: match.end - 1),
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
    if (_selectToCopyEnabled) {
      _controller.removeListener(_onSelectionMaybeChanged);
    }
    _clipboard.dispose();
    _matches.clear();
    _controller.dispose();
    _scrollController.dispose();
    await _outgoingBytes.close();
    await _resizeEvents.close();
    await _activity.dispose();
  }
}

class _MaidTermMatch {
  const _MaidTermMatch(this.row, this.start, this.end);

  final int row;
  final int start;
  final int end;
}

/// Focus host for read-only log surfaces on the ghostty renderer.
///
/// MaidTerm's [maidterm.TerminalView] has no read-only keyboard mode: any focused
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
        // MaidTerm's own tap handler cannot focus an ExcludeFocus'd subtree, so
        // focus this host on any pointer press inside the log surface.
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: ExcludeFocus(child: widget.child),
      ),
    );
  }
}
