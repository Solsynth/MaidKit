import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:xterm/xterm.dart';

import 'package:maid_kit/shared/presentation/app_context_menu.dart';

import 'package:maid_kit/theme.dart';

import 'terminal_color_scheme.dart';
import 'terminal_keyword_highlight.dart';

Menu terminalContextMenu({
  required bool hasSelection,
  required bool canPaste,
  required VoidCallback onCopy,
  required VoidCallback onPaste,
  required VoidCallback onSelectAll,
  VoidCallback? onOpenFileManagement,
}) => Menu(
  children: [
    MenuAction(
      title: 'commonCopy'.tr(),
      image: MenuImage.icon(Symbols.content_copy),
      attributes: MenuActionAttributes(disabled: !hasSelection),
      callback: onCopy,
    ),
    MenuAction(
      title: 'fileManagerPaste'.tr(),
      image: MenuImage.icon(Symbols.content_paste),
      attributes: MenuActionAttributes(disabled: !canPaste),
      callback: onPaste,
    ),
    MenuSeparator(),
    MenuAction(
      title: 'commonSelectAll'.tr(),
      image: MenuImage.icon(Symbols.select_all),
      callback: onSelectAll,
    ),
    if (onOpenFileManagement != null) ...[
      MenuSeparator(),
      MenuAction(
        title: 'sessionsOpenFileManagement'.tr(),
        image: MenuImage.icon(Symbols.folder_open),
        callback: onOpenFileManagement,
      ),
    ],
  ],
);

/// Tracks OSC 7 shell integration updates such as `file:///work/project`.
class TerminalWorkingDirectoryTracker {
  static const _marker = '\x1b]7;';

  var _pending = '';
  String? _directory;

  String? get directory => _directory;

  void add(Uint8List bytes) {
    _pending += utf8.decode(bytes, allowMalformed: true);
    while (true) {
      final start = _pending.indexOf(_marker);
      if (start < 0) {
        _pending = _pending.length > _marker.length - 1
            ? _pending.substring(_pending.length - _marker.length + 1)
            : _pending;
        return;
      }
      final bel = _pending.indexOf('\x07', start + _marker.length);
      final st = _pending.indexOf('\x1b\\', start + _marker.length);
      final end = bel < 0
          ? st
          : st < 0
          ? bel
          : bel < st
          ? bel
          : st;
      if (end < 0) {
        _pending = _pending.substring(start);
        return;
      }
      final value = _pending.substring(start + _marker.length, end);
      _directory = TerminalWorkingDirectoryTracker.decode(value);
      _pending = _pending.substring(end + (end == bel ? 1 : 2));
    }
  }

  static String? decode(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme == 'file') return Uri.decodeComponent(uri.path);
    } on FormatException {
      return null;
    }
    return value.startsWith('/') ? Uri.decodeComponent(value) : null;
  }
}

/// A terminal emulator instance attached to one remote shell.
///
/// The adapter owns emulator-specific state and rendering. SSH transport code
/// only needs to forward byte streams and react to input and resize events.
abstract interface class TerminalSessionAdapter {
  /// Bytes produced by keyboard, paste, or mouse input in the terminal.
  Stream<Uint8List> get outgoingBytes;

  /// Terminal size changes requested by the renderer.
  Stream<TerminalResize> get resizeEvents;

  /// Whether the remote shell has reported that a command is active.
  ///
  /// This is informed by shell-integration/progress control sequences when
  /// available, with a conservative Enter-to-prompt fallback for ordinary
  /// interactive shells.
  Stream<bool> get taskRunning;

  /// Detailed task activity, including a percentage when the terminal or its
  /// command reports one.
  Stream<TerminalTaskActivity> get taskActivity;

  /// Latest task activity value, used before [taskRunning] emits its first
  /// event.
  bool get isTaskRunning;

  /// Latest detailed task activity value.
  TerminalTaskActivity get currentTaskActivity;

  /// Current shell directory reported through OSC 7, when available.
  String? get currentDirectory;

  /// Displays bytes received from the remote shell.
  void write(Uint8List bytes);

  /// Sends text or terminal control sequences to the remote shell.
  void sendInput(String text);

  /// Shows the platform software keyboard and focuses this terminal.
  void showKeyboard();

  /// Hides the platform software keyboard without dropping terminal focus.
  void hideKeyboard();

  /// Current cursor cell in global coordinates, when the renderer is mounted.
  Rect? get cursorGlobalRect;

  /// Builds this adapter's terminal renderer.
  ///
  /// [readOnly] disables keyboard input when the surface is used for log
  /// playback rather than an interactive shell.
  /// [showCursor] hides the caret (useful for static log playback).
  /// [transparentBackground] overrides the adapter's initial background
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  });

  /// Finds all matches for [query] in the terminal buffer. Returns the count.
  int find(String query, {bool caseSensitive = false});

  /// Jumps to the match at [index] (0-based) and highlights it.
  void findJump(int index);

  /// Clears find highlights / selection produced by [find].
  void findClear();

  /// Releases emulator-specific resources.
  Future<void> dispose();
}

/// Bridges OSC 52 clipboard requests from terminal applications to the host.
///
/// TUI applications cannot access the host clipboard directly. They use OSC
/// 52 to publish selected text or request the current host clipboard value.
/// The terminal renderer still receives the original bytes; this bridge only
/// observes the control sequence and emits a response for query requests.
class TerminalClipboardBridge {
  TerminalClipboardBridge({
    required this._setClipboard,
    required this._getClipboard,
    required this._sendResponse,
  });

  static const _escape = 0x1b;
  static const _closeString = 0x5c;
  static const _bel = 0x07;
  static const _maxPayloadBytes = 4 * 1024 * 1024;

  final Future<void> Function(String text) _setClipboard;
  final Future<String?> Function() _getClipboard;
  final void Function(String text) _sendResponse;
  final _payload = BytesBuilder(copy: false);
  var _stage = 0;
  var _tmuxStage = 0;
  var _disposed = false;

  /// Feeds raw terminal output into the OSC 52 recognizer.
  ///
  /// OSC sequences may be split across transport packets, so recognition is
  /// intentionally byte-oriented and retains only a possible OSC 52 payload.
  /// tmux can wrap forwarded OSC sequences in a DCS passthrough envelope; that
  /// envelope is unwrapped here before the same OSC parser handles its bytes.
  void add(Uint8List bytes) {
    if (_disposed) return;
    for (final byte in bytes) {
      _consume(byte);
    }
  }

  void _consume(int byte) {
    if (_tmuxStage != 0) {
      _consumeTmux(byte);
      return;
    }

    // ESC Ptmux; ... ESC \ is tmux's passthrough form for terminal control
    // sequences. The first ESC is already held by the OSC parser.
    if (_stage == 1 && byte == 0x50) {
      _stage = 0;
      _tmuxStage = 1;
      return;
    }

    if (_stage != 0) {
      _consumeOsc(byte);
      return;
    }
    if (byte == _escape) _stage = 1;
  }

  void _consumeTmux(int byte) {
    const prefix = 'tmux;';
    if (_tmuxStage <= prefix.length) {
      if (byte == prefix.codeUnitAt(_tmuxStage - 1)) {
        _tmuxStage++;
        return;
      }
      _tmuxStage = 0;
      _stage = 0;
      _payload.clear();
      _consume(byte);
      return;
    }

    // tmux doubles ESC bytes inside the passthrough payload. An un-doubled
    // ESC followed by '\' terminates the DCS envelope.
    if (_tmuxStage == prefix.length + 1) {
      if (byte == _escape) {
        _tmuxStage++;
      } else {
        _consumeOsc(byte);
      }
      return;
    }

    if (byte == _escape) {
      if (_stage == 0) {
        _stage = 1;
      } else {
        _consumeOsc(_escape);
      }
      _tmuxStage = prefix.length + 1;
    } else if (byte == _closeString) {
      _tmuxStage = 0;
      _stage = 0;
      _payload.clear();
    } else {
      _tmuxStage = 0;
      _stage = 0;
      _payload.clear();
      _consume(byte);
    }
  }

  void _consumeOsc(int byte) {
    switch (_stage) {
      case 1:
        if (byte == 0x5d) {
          _stage = 2;
        } else {
          _reset(byte);
        }
        return;
      case 2:
        if (byte == 0x35) {
          _stage = 3;
        } else {
          _reset(byte);
        }
        return;
      case 3:
        if (byte == 0x32) {
          _stage = 4;
        } else {
          _reset(byte);
        }
        return;
      case 4:
        if (byte == 0x3b) {
          _payload.clear();
          _stage = 5;
        } else {
          _reset(byte);
        }
        return;
      case 5:
        if (byte == _bel) {
          _finish();
        } else if (byte == _escape) {
          _stage = 6;
        } else if (_payload.length < _maxPayloadBytes) {
          _payload.addByte(byte);
        } else {
          _stage = 0;
          _payload.clear();
        }
        return;
      case 6:
        if (byte == _closeString) {
          _finish();
        } else {
          _reset(byte);
        }
        return;
    }
  }

  void _reset(int byte) {
    _stage = byte == _escape ? 1 : 0;
    _payload.clear();
  }

  void _finish() {
    final fields = utf8
        .decode(_payload.takeBytes(), allowMalformed: true)
        .split(';');
    _stage = 0;
    if (fields.length < 2 || !_isClipboardSelection(fields.first)) return;

    final selection = fields.first;
    final encoded = fields.sublist(1).join(';');
    if (encoded == '?') {
      unawaited(_sendClipboardResponse(selection));
      return;
    }

    try {
      final compact = encoded.replaceAll(RegExp(r'\s'), '');
      final padded = compact.padRight(
        compact.length + (4 - compact.length % 4) % 4,
        '=',
      );
      final text = utf8.decode(base64.decode(padded), allowMalformed: true);
      unawaited(_setClipboard(text).catchError((_) {}));
    } on FormatException {
      // Ignore malformed OSC 52 payloads; they are not terminal output.
    }
  }

  Future<void> _sendClipboardResponse(String selection) async {
    try {
      final text = await _getClipboard() ?? '';
      if (_disposed) return;
      final encoded = base64.encode(utf8.encode(text));
      _sendResponse('\x1b]52;$selection;$encoded\x1b\\');
    } catch (_) {
      // Clipboard access is optional on headless and restricted platforms.
    }
  }

  bool _isClipboardSelection(String selection) =>
      selection.isEmpty ||
      selection == 'c' ||
      selection == 'p' ||
      selection == 'q' ||
      selection == 's' ||
      selection == '0' ||
      selection == '1' ||
      selection == '2' ||
      selection == '3' ||
      selection == '4' ||
      selection == '5' ||
      selection == '6' ||
      selection == '7';
  void dispose() {
    _disposed = true;
    _stage = 0;
    _tmuxStage = 0;
    _payload.clear();
  }
}

Future<void> _setHostClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

Future<String?> _getHostClipboard() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

TerminalClipboardBridge createHostClipboardBridge({
  required void Function(String text) sendResponse,
}) => TerminalClipboardBridge(
  setClipboard: _setHostClipboard,
  getClipboard: _getHostClipboard,
  sendResponse: sendResponse,
);

/// A terminal resize notification from the renderer.

class TerminalResize {
  const TerminalResize({
    required this.columns,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int columns;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
}

/// Tracks shell activity without interpreting terminal text as command output.
///
/// OSC 133 (FinalTerm/iTerm shell integration), OSC 633 (VS Code shell
/// integration), and OSC 9;4 (Windows Terminal progress) are established
/// terminal conventions. Regular shells rarely enable these by default, so
/// pressing Enter starts the indicator and a conventional prompt ends it.
class TerminalTaskActivity {
  const TerminalTaskActivity({required this.running, this.progress});

  final bool running;

  /// Completion fraction in the inclusive 0–1 range, if known.
  final double? progress;
}

class TerminalActivityTracker {
  final _changes = StreamController<TerminalTaskActivity>.broadcast();
  var _running = false;
  double? _progress;
  var _recentOutput = '';

  Stream<bool> get runningChanges =>
      _changes.stream.map((activity) => activity.running);
  Stream<TerminalTaskActivity> get changes => _changes.stream;
  bool get isRunning => _running;
  TerminalTaskActivity get current =>
      TerminalTaskActivity(running: _running, progress: _progress);

  void sentInput(String text) {
    if (text.contains('\n') || text.contains('\r')) _setRunning(true);
  }

  void receivedOutput(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _recentOutput += utf8.decode(bytes, allowMalformed: true);
    if (_recentOutput.length > 1024) {
      _recentOutput = _recentOutput.substring(_recentOutput.length - 1024);
    }

    // OSC 133 / 633: C = command execution started, D = command finished.
    final osc = RegExp(
      r'\x1b](?:133|633);([A-D])(?:;[^\x07\x1b]*)?(?:\x07|\x1b\\)',
    );
    for (final match in osc.allMatches(_recentOutput)) {
      switch (match.group(1)) {
        case 'C':
          _setRunning(true);
        case 'A':
        case 'D':
          _setRunning(false);
      }
    }

    // Windows Terminal progress: 0 clears, 1/2/3 represent progress states.
    final progress = RegExp(r'\x1b]9;4;([0-3])(?:;(\d+))?(?:\x07|\x1b\\)');
    for (final match in progress.allMatches(_recentOutput)) {
      final state = match.group(1)!;
      final percent = int.tryParse(match.group(2) ?? '');
      _setActivity(
        running: state != '0',
        progress: state == '1' && percent != null
            ? percent.clamp(0, 100) / 100
            : null,
      );
    }

    // Fallback for shells without integration. This deliberately accepts only
    // a prompt-looking final line, avoiding false completion during ordinary
    // command output.
    final visible = _recentOutput.replaceAll(
      RegExp(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'),
      '',
    );
    if (RegExp(r'(?:^|[\r\n])[^\r\n]{0,160}[\$#%>❯➜]\s*$').hasMatch(visible)) {
      _setActivity(running: false);
    } else {
      // Many CLI tools render a standalone percentage without emitting a
      // terminal progress sequence. Limit this to a line ending in `%` so
      // incidental values such as CPU usage do not hijack the tab indicator.
      final percentage = RegExp(r'(?:^|[\r\n])[^\r\n]{0,120}\b(\d{1,3})%\s*$');
      RegExpMatch? latest;
      for (final match in percentage.allMatches(visible)) {
        latest = match;
      }
      final value = latest == null ? null : int.tryParse(latest.group(1)!);
      if (value != null && value <= 100) {
        _setActivity(running: true, progress: value / 100);
      }
    }
  }

  void _setRunning(bool value) => _setActivity(running: value);

  void _setActivity({required bool running, double? progress}) {
    final normalizedProgress = running ? progress : null;
    if (_running == running && _progress == normalizedProgress) return;
    _running = running;
    _progress = normalizedProgress;
    if (!_changes.isClosed) _changes.add(current);
  }

  Future<void> dispose() => _changes.close();
}

abstract interface class TerminalSessionAdapterFactory {
  TerminalSessionAdapter create();
}

class TerminalSessionAdapterOption {
  const TerminalSessionAdapterOption({
    required this.id,
    required this.label,
    required this.description,
    required this.factory,
  });

  final String id;
  final String label;
  final String description;
  final TerminalSessionAdapterFactory factory;
}

class XtermTerminalSessionAdapterFactory
    implements TerminalSessionAdapterFactory {
  const XtermTerminalSessionAdapterFactory({
    required this.colorScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
    this.selectToCopyEnabled = false,
    this.shiftInsertPasteEnabled = true,
    this.keywordHighlightEnabled = true,
  });

  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final bool selectToCopyEnabled;
  final bool shiftInsertPasteEnabled;
  final bool keywordHighlightEnabled;

  @override
  TerminalSessionAdapter create() => XtermTerminalSessionAdapter(
    colorScheme: colorScheme,
    transparentBackground: transparentBackground,
    fontFamily: fontFamily,
    selectToCopyEnabled: selectToCopyEnabled,
    shiftInsertPasteEnabled: shiftInsertPasteEnabled,
    keywordHighlightEnabled: keywordHighlightEnabled,
  );
}

class _BufferMatch {
  const _BufferMatch(this.line, this.start, this.end);

  final int line;
  final int start;
  final int end;
}

/// The production adapter backed by the xterm Flutter package.
class XtermTerminalSessionAdapter implements TerminalSessionAdapter {
  XtermTerminalSessionAdapter({
    required this.colorScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
    bool selectToCopyEnabled = false,
    bool shiftInsertPasteEnabled = true,
    bool keywordHighlightEnabled = true,
  })  : _selectToCopyEnabled = selectToCopyEnabled,
        _shiftInsertPasteEnabled = shiftInsertPasteEnabled,
        _keywordHighlightEnabled = keywordHighlightEnabled,
        _terminal = Terminal(maxLines: 10000) {
    _clipboard = createHostClipboardBridge(sendResponse: sendInput);
    _terminal.onOutput = (data) {
      if (!_disposed) {
        _activity.sentInput(data);
        _outgoingBytes.add(Uint8List.fromList(utf8.encode(data)));
      }
    };
    _terminal.onResize = (columns, rows, pixelWidth, pixelHeight) {
      if (!_disposed) {
        _resizeEvents.add(
          TerminalResize(
            columns: columns,
            rows: rows,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
          ),
        );
      }
    };
    if (selectToCopyEnabled) {
      _controller.addListener(_onSelectionMaybeChanged);
    }
  }

  final Terminal _terminal;
  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final bool _selectToCopyEnabled;
  final bool _shiftInsertPasteEnabled;
  final bool _keywordHighlightEnabled;
  final TerminalController _controller = TerminalController();
  late final TerminalClipboardBridge _clipboard;
  final ScrollController _scrollController = ScrollController();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _outgoingBytes = StreamController<Uint8List>.broadcast();
  final _resizeEvents = StreamController<TerminalResize>.broadcast();
  final _highlights = <TerminalHighlight>[];
  final _keywordHighlights = <TerminalHighlight>[];
  final _matches = <_BufferMatch>[];
  final _activity = TerminalActivityTracker();
  final _workingDirectory = TerminalWorkingDirectoryTracker();
  var _disposed = false;

  static const _hitColor = Color(0x66E5E510);
  static const _currentHitColor = Color(0xAA31FF26);
  static const _approxLineHeight = 18.0;
  static const _maxKeywordHighlights = 1500;
  static const _keywordScanDelay = Duration(milliseconds: 250);

  /// Tracks the last auto-copied selection text so the select-to-copy
  /// listener only writes to the clipboard when the selection changes.
  String? _lastAutoCopiedSelection;

  Timer? _keywordScanTimer;

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
  String? get currentDirectory => _workingDirectory.directory;

  @override
  void write(Uint8List bytes) {
    if (!_disposed) {
      _workingDirectory.add(bytes);
      _clipboard.add(bytes);
      _activity.receivedOutput(bytes);
      _terminal.write(utf8.decode(bytes, allowMalformed: true));
      if (_keywordHighlightEnabled) _scheduleKeywordScan();
    }
  }

  @override
  void sendInput(String text) {
    if (!_disposed && text.isNotEmpty) {
      _activity.sentInput(text);
      _outgoingBytes.add(Uint8List.fromList(utf8.encode(text)));
    }
  }

  @override
  void showKeyboard() {
    if (!_disposed) _terminalViewKey.currentState?.requestKeyboard();
  }

  @override
  void hideKeyboard() {
    if (!_disposed) _terminalViewKey.currentState?.closeKeyboard();
  }

  @override
  Rect? get cursorGlobalRect => _terminalViewKey.currentState?.globalCursorRect;

  @override
  int find(String query, {bool caseSensitive = false}) {
    findClear();
    if (_disposed || query.isEmpty) return 0;
    final buffer = _terminal.buffer;
    final needle = caseSensitive ? query : query.toLowerCase();
    for (var y = 0; y < buffer.height; y++) {
      final lineText = buffer.lines[y].getText();
      final haystack = caseSensitive ? lineText : lineText.toLowerCase();
      var from = 0;
      while (true) {
        final index = haystack.indexOf(needle, from);
        if (index < 0) break;
        _matches.add(_BufferMatch(y, index, index + query.length));
        from = index + 1;
      }
    }
    _repaintAllHits(currentIndex: _matches.isEmpty ? null : 0);
    return _matches.length;
  }

  @override
  void findJump(int index) {
    if (_disposed || _matches.isEmpty) return;
    final safe = index.clamp(0, _matches.length - 1);
    // Keep every match painted; only restyle the current hit.
    _repaintAllHits(currentIndex: safe);
    final match = _matches[safe];
    final buffer = _terminal.buffer;
    final lineLen = buffer.lines[match.line].length;
    final start = match.start.clamp(0, lineLen);
    final endCol = (match.end - 1).clamp(start, lineLen > 0 ? lineLen - 1 : 0);
    _controller.setSelection(
      buffer.createAnchor(start, match.line),
      buffer.createAnchor(endCol, match.line),
    );
    if (_scrollController.hasClients) {
      final target = (match.line * _approxLineHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    }
  }

  @override
  void findClear({bool keepMatches = false}) {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
    _controller.clearSelection();
    if (!keepMatches) _matches.clear();
  }

  void _repaintAllHits({required int? currentIndex}) {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
    for (var i = 0; i < _matches.length; i++) {
      _paintMatch(i, current: currentIndex != null && i == currentIndex);
    }
  }

  void _paintMatch(int index, {required bool current}) {
    final match = _matches[index];
    final buffer = _terminal.buffer;
    final lineLen = buffer.lines[match.line].length;
    final start = match.start.clamp(0, lineLen);
    final endCol = (match.end - 1).clamp(start, lineLen > 0 ? lineLen - 1 : 0);
    _highlights.add(
      _controller.highlight(
        p1: buffer.createAnchor(start, match.line),
        p2: buffer.createAnchor(endCol, match.line),
        color: current ? _currentHitColor : _hitColor,
      ),
    );
  }

  void _copySelectionToClipboard() {
    if (_disposed) return;
    final selection = _controller.selection;
    if (selection == null) return;
    final text = _terminal.buffer.getText(selection);
    if (text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
  }

  void _selectAll() {
    if (_disposed) return;
    _controller.setSelection(
      _terminal.buffer.createAnchor(
        0,
        _terminal.buffer.height - _terminal.viewHeight,
      ),
      _terminal.buffer.createAnchor(
        _terminal.viewWidth,
        _terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
  }

  Future<void> _pasteFromClipboard() async {
    if (_disposed) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && !_disposed) {
      _terminal.paste(text);
      _controller.clearSelection();
    }
  }

  KeyEventResult _handleReadOnlyKeyEvent(FocusNode _, KeyEvent event) {
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
      _copySelectionToClipboard();
      return KeyEventResult.handled;
    }

    if (command && event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }

    // Block typing / paste / navigation from reaching the log terminal.
    return KeyEventResult.handled;
  }

  void _scheduleKeywordScan() {
    if (!_keywordHighlightEnabled || _disposed) return;
    _keywordScanTimer?.cancel();
    _keywordScanTimer = Timer(_keywordScanDelay, _refreshKeywordHighlights);
  }

  void _refreshKeywordHighlights() {
    if (!_keywordHighlightEnabled || _disposed) return;
    for (final highlight in _keywordHighlights) {
      highlight.dispose();
    }
    _keywordHighlights.clear();
    final buffer = _terminal.buffer;
    for (var y = 0; y < buffer.height; y++) {
      final lineText = buffer.lines[y].getText();
      for (final rule in terminalKeywordRules) {
        for (final match in rule.pattern.allMatches(lineText)) {
          if (_keywordHighlights.length >= _maxKeywordHighlights) return;
          final start = match.start;
          final end = match.end - 1;
          if (end < start) continue;
          _keywordHighlights.add(
            _controller.highlight(
              p1: buffer.createAnchor(start, y),
              p2: buffer.createAnchor(end, y),
              color: rule.color,
            ),
          );
        }
      }
    }
  }

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
    if (_selectToCopyEnabled) {
      final selection = _controller.selection;
      if (selection != null) {
        final selected = _terminal.buffer.getText(selection);
        if (selected.isNotEmpty) text = selected;
      }
    }
    if (text == null) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    }
    if (text != null && text.isNotEmpty && !_disposed) {
      _terminal.paste(text);
      _controller.clearSelection();
    }
  }

  /// Auto-copies the active selection to the clipboard (select-to-copy).
  ///
  /// The controller fires this on every state change, so we diff against the
  /// last copied text and only write when it actually changes.
  void _onSelectionMaybeChanged() {
    if (_disposed || !_selectToCopyEnabled) return;
    final selection = _controller.selection;
    final text = selection == null ? '' : _terminal.buffer.getText(selection);
    if (text.isEmpty) {
      _lastAutoCopiedSelection = null;
      return;
    }
    if (text == _lastAutoCopiedSelection) return;
    _lastAutoCopiedSelection = text;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
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
    final theme = _xtermThemeFor(colorScheme, showCursor: showCursor);
    final effectiveKeyEvent = !readOnly && _shiftInsertPasteEnabled
        ? _wrapKeyEventForShiftInsert(onKeyEvent)
        : onKeyEvent;
    final terminal = KeyedSubtree(
      key: ObjectKey(this),
      child: TerminalView(
        _terminal,
        key: _terminalViewKey,
        controller: _controller,
        scrollController: _scrollController,
        autofocus: autofocus,
        readOnly: readOnly,
        // Mobile soft keyboards send backspace through the IME, not as
        // hardware key events. deleteDetection keeps a non-empty IME buffer
        // so the deletion is observable; without it Android's backspace is
        // silently dropped.
        deleteDetection:
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS),
        // Never use hardwareKeyboardOnly together with readOnly: that combo
        // skips both CustomTextEdit and CustomKeyboardListener, leaving no
        // Focus node for Cmd/Ctrl+C after selecting log text.
        hardwareKeyboardOnly: false,
        onKeyEvent:
            effectiveKeyEvent ?? (readOnly ? _handleReadOnlyKeyEvent : null),
        alwaysShowCursor: false,
        backgroundOpacity: (transparentBackground ?? this.transparentBackground)
            ? 0
            : 1,
        theme: theme,
        padding: const EdgeInsets.all(12),
        textStyle: TerminalStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: const [],
          fontSize: 14,
        ),
      ),
    );
    if (readOnly) return terminal;
    return AppContextMenuRegion(
      menuBuilder: () => terminalContextMenu(
        hasSelection: _controller.selection != null,
        canPaste: true,
        onCopy: _copySelectionToClipboard,
        onPaste: () => unawaited(_pasteFromClipboard()),
        onSelectAll: _selectAll,
        onOpenFileManagement: onOpenFileManagement,
      ),
      child: terminal,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _keywordScanTimer?.cancel();
    if (_selectToCopyEnabled) {
      _controller.removeListener(_onSelectionMaybeChanged);
    }
    for (final highlight in _keywordHighlights) {
      highlight.dispose();
    }
    _keywordHighlights.clear();
    _clipboard.dispose();
    findClear();
    _terminal.onOutput = null;
    _terminal.onResize = null;
    _scrollController.dispose();
    await _outgoingBytes.close();
    await _resizeEvents.close();
    await _activity.dispose();
  }
}

TerminalTheme _xtermThemeFor(
  TerminalColorScheme scheme, {
  required bool showCursor,
}) {
  final ansi = scheme.ansiColors;
  return TerminalTheme(
    cursor: showCursor ? scheme.cursor : const Color(0x00000000),
    selection: scheme.selection,
    foreground: scheme.foreground,
    background: scheme.background,
    black: ansi[0],
    red: ansi[1],
    green: ansi[2],
    yellow: ansi[3],
    blue: ansi[4],
    magenta: ansi[5],
    cyan: ansi[6],
    white: ansi[7],
    brightBlack: ansi[8],
    brightRed: ansi[9],
    brightGreen: ansi[10],
    brightYellow: ansi[11],
    brightBlue: ansi[12],
    brightMagenta: ansi[13],
    brightCyan: ansi[14],
    brightWhite: ansi[15],
    searchHitBackground: scheme.selection,
    searchHitBackgroundCurrent: scheme.cursor,
    searchHitForeground: scheme.background,
  );
}

/// Wires a terminal adapter to one shell's byte streams without coupling the
/// adapter contract to a specific SSH implementation.
class TerminalSessionBinding {
  TerminalSessionBinding({
    required this.adapter,
    required Stream<Uint8List> stdout,
    required Stream<Uint8List> stderr,
    required void Function(Uint8List bytes) send,
    required void Function(TerminalResize resize) resize,
    this.outputFlushDelay = const Duration(milliseconds: 8),
  }) : // Public parameter names preserve the adapter binding API.
       // ignore: prefer_initializing_formals
       _send = send,
       // ignore: prefer_initializing_formals
       _resize = resize,
       _subscriptions = [] {
    _subscriptions.addAll([
      stdout.listen(_queueTerminalOutput, onError: _ignoreTransportError),
      stderr.listen(_queueTerminalOutput, onError: _ignoreTransportError),
      adapter.outgoingBytes.listen(_sendTerminalInput),
      adapter.resizeEvents.listen(_resizeTerminal),
    ]);
  }

  final TerminalSessionAdapter adapter;
  final void Function(Uint8List bytes) _send;
  final void Function(TerminalResize resize) _resize;
  final List<StreamSubscription<Object?>> _subscriptions;
  final Duration outputFlushDelay;
  final _outputBuffer = BytesBuilder(copy: false);
  Timer? _outputFlushTimer;
  var _closed = false;

  // SSH channel streams can report an error while their terminal is being
  // closed. The owner observes shell completion and tears this binding down,
  // so forwarding that late error into Flutter's root zone would only crash
  // the app after a normal `exit`.
  void _ignoreTransportError(Object error, StackTrace stackTrace) {}

  void _sendTerminalInput(Uint8List bytes) {
    if (_closed) return;
    try {
      _send(bytes);
    } catch (_) {
      // The SSH channel can close between delivering input and teardown.
    }
  }

  void _resizeTerminal(TerminalResize resize) {
    if (_closed) return;
    try {
      _resize(resize);
    } catch (_) {
      // See [_sendTerminalInput].
    }
  }

  /// Batch high-frequency remote output without delaying local key presses.
  ///
  /// An 8ms cap keeps interactive echo effectively immediate while preventing
  /// a burst (for example, `cat` or a build log) from forcing one terminal
  /// update per SSH packet. Large bursts bypass the timer to bound memory.
  void _queueTerminalOutput(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    _outputBuffer.add(bytes);
    if (_outputBuffer.length >= 16 * 1024) {
      _flushTerminalOutput();
      return;
    }
    _outputFlushTimer ??= Timer(outputFlushDelay, _flushTerminalOutput);
  }

  void _flushTerminalOutput() {
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    if (_closed || _outputBuffer.length == 0) return;
    adapter.write(_outputBuffer.takeBytes());
  }

  Future<void> close() async {
    if (_closed) return;
    _flushTerminalOutput();
    _closed = true;
    _outputFlushTimer?.cancel();
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await adapter.dispose();
  }
}
