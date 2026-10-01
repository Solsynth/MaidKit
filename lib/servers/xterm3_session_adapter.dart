import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm3/xterm.dart' as xterm;

import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/theme.dart';
import 'terminal_color_scheme.dart';
import 'terminal_keyword_highlight.dart';
import 'terminal_session_adapter.dart';

/// The web platform's terminal renderer, backed by package `xterm3`.
///
/// The native renderer is MaidTerm, which draws through libghostty: a native
/// library reached over `dart:ffi` and built by a native-assets hook, neither
/// of which exists for `dart2js`. Web builds therefore link this adapter
/// instead — the choice is made at compile time by
/// `terminal_renderer_backend.dart`, so a web build never imports MaidTerm and
/// a native build never imports xterm3.
///
/// xterm3's emulator core is pure Dart, so this adapter still speaks the
/// renderer-neutral [TerminalSessionAdapter] contract: bytes in, bytes out,
/// resize notifications, find, scrollback capture, and sudo autofill. The one
/// capability it drops is desktop notifications requested through OSC 9/777,
/// which need a notification plugin a browser build does not have.
class TerminalRendererFactory implements TerminalSessionAdapterFactory {
  const TerminalRendererFactory({
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
  TerminalSessionAdapter create() => Xterm3SessionAdapter(
    cursorAnimationEnabled: cursorAnimationEnabled,
    colorScheme: colorScheme,
    transparentBackground: transparentBackground,
    fontFamily: fontFamily,
    selectToCopyEnabled: selectToCopyEnabled,
    shiftInsertPasteEnabled: shiftInsertPasteEnabled,
    keywordHighlightEnabled: keywordHighlightEnabled,
  );
}

class Xterm3SessionAdapter implements TerminalSessionAdapter {
  Xterm3SessionAdapter({
    bool cursorAnimationEnabled = true,
    this.colorScheme = TerminalColorSchemes.defaultScheme,
    this.transparentBackground = false,
    this.fontFamily = MaidKitFonts.mono,
    this.selectToCopyEnabled = false,
    this.shiftInsertPasteEnabled = true,
    this.keywordHighlightEnabled = true,
  }) : _controller = xterm.TerminalController(),
       _terminal = xterm.Terminal(
         maxLines: scrollbackLines,
         platform: _hostPlatform,
       ) {
    _terminal
      ..onOutput = _onTerminalOutput
      ..onResize = _onTerminalResize
      ..onCurrentDirectoryChange = _onCurrentDirectory;
    // Cursor behaviour is a terminal mode here, not a renderer setting, so the
    // preference is applied through the same DEC mode a remote program would
    // use. Blinking is off by default in xterm3; DEC 12 turns it on. This runs
    // before the change listener is attached: a renderer setting is not buffer
    // content and must not schedule a tint pass.
    _terminal.write(cursorAnimationEnabled ? '\x1b[?12h' : '\x1b[?12l');
    if (keywordHighlightEnabled || selectToCopyEnabled) {
      _terminal.addListener(_onTerminalChanged);
    }
  }

  /// Scrollback retained per session, matching the native renderer's budget.
  static const scrollbackLines = 10000;

  /// Upper bound on keyword highlights drawn at once. Output such as a build
  /// log can match thousands of times; the tint is decoration and must never
  /// cost more than the text it decorates.
  static const _maxKeywordHighlights = 400;

  final TerminalColorScheme colorScheme;
  final bool transparentBackground;
  final String fontFamily;
  final bool selectToCopyEnabled;
  final bool shiftInsertPasteEnabled;
  final bool keywordHighlightEnabled;

  final xterm.Terminal _terminal;
  final xterm.TerminalController _controller;
  final _viewKey = GlobalKey<xterm.TerminalViewState>();
  final _scrollController = ScrollController();

  final _outgoingBytes = StreamController<Uint8List>.broadcast();
  final _resizeEvents = StreamController<TerminalResize>.broadcast();
  final _activity = TerminalActivityTracker();
  final _decoder = _Utf8ByteDecoder();

  final _matches = <xterm.TerminalSearchMatch>[];
  final _keywordHighlights = <xterm.TerminalHighlight>[];
  Timer? _keywordTimer;
  xterm.TerminalViewState? _attachedViewState;
  String? _lastAutoCopiedSelection;
  String? _cursorVisibilityEscape;
  StreamSubscription<SudoPromptReason?>? _sudoSub;
  SudoPromptReason? _sudoAutofillReady;
  String? _directory;
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
  String? get currentDirectory => _directory;

  @override
  int get bufferRows => _disposed ? 0 : _terminal.buffer.lines.length;

  @override
  String? dumpHistory({int maxLines = 4000}) {
    if (_disposed) return null;
    try {
      // The plain formatter covers scrollback plus the visible grid, so a
      // restored session shows its prior output as scrollback history.
      final text = _terminal.buffer.getText(null, true);
      if (text.isEmpty) return text;
      // Unused rows at the bottom of the viewport are part of the grid, not
      // history: replaying them would push blank lines into a restored
      // scrollback.
      final lines = text.split('\n');
      var end = lines.length;
      while (end > 0 && lines[end - 1].trim().isEmpty) {
        end--;
      }
      if (maxLines > 0 && end > maxLines) {
        return lines.sublist(end - maxLines, end).join('\n');
      }
      return lines.sublist(0, end).join('\n');
    } catch (_) {
      // Renderer not available (tests, disposed engine): no capture.
      return null;
    }
  }

  @override
  void replayHistory(String text) {
    if (_disposed || text.isEmpty) return;
    // Feed the renderer directly, bypassing the activity tracker: restored
    // content is not live program output.
    _terminal.write(text);
  }

  @override
  SudoPromptReason? get sudoAutofillReady => _sudoAutofillReady;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {
    _sudoSub?.cancel();
    _sudoSub = reasons.listen((reason) => _sudoAutofillReady = reason);
  }

  @override
  void write(Uint8List bytes) {
    if (_disposed || bytes.isEmpty) return;
    _activity.receivedOutput(bytes);
    // OSC 52 clipboard requests are answered by `TerminalView` itself, which
    // installs host clipboard handlers while it is mounted.
    _terminal.write(_decoder.add(bytes));
  }

  @override
  void sendInput(String text) {
    if (_disposed || text.isEmpty) return;
    _activity.sentInput(text);
    _terminal.textInput(text);
  }

  @override
  void showKeyboard() {
    if (!_disposed) _viewKey.currentState?.requestKeyboard();
  }

  @override
  void hideKeyboard() {
    if (!_disposed) _viewKey.currentState?.closeKeyboard();
  }

  @override
  Rect? get cursorGlobalRect {
    try {
      return _viewKey.currentState?.globalCursorRect;
    } catch (_) {
      // The render object has no geometry until the view has been laid out.
      return null;
    }
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
    _applyCursorVisibility(showCursor);
    final view = xterm.TerminalView(
      _terminal,
      key: _viewKey,
      controller: _controller,
      scrollController: _scrollController,
      // Unlike the native renderer, the web view has a read-only mode of its
      // own, so a log surface keeps the same selection and clipboard handling
      // an interactive terminal gets.
      readOnly: readOnly,
      autofocus: autofocus && !readOnly,
      theme: _theme,
      textStyle: xterm.TerminalStyle(fontFamily: fontFamily),
      backgroundOpacity: (transparentBackground ?? this.transparentBackground)
          ? 0
          : 1,
      onKeyEvent: !readOnly && shiftInsertPasteEnabled
          ? _wrapKeyEventForShiftInsert(onKeyEvent)
          : onKeyEvent,
      onHyperlinkTap: _openLink,
    );

    // Keyword tints are anchored to buffer lines, so the first pass has to wait
    // for the view to exist: without a viewport there is nothing to tint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final state = _viewKey.currentState;
      if (state == null || identical(state, _attachedViewState)) return;
      _attachedViewState = state;
      _scheduleKeywordHighlightRefresh();
    });

    return AppContextMenuRegion(
      menuBuilder: () => terminalContextMenu(
        onOpenFileManagement: onOpenFileManagement,
        hasSelection: _controller.selection != null,
        canPaste: true,
        onCopy: _copySelectionToClipboard,
        onPaste: () => unawaited(_pasteFromClipboard()),
        onSelectAll: _selectAll,
      ),
      child: view,
    );
  }

  @override
  int find(String query, {bool caseSensitive = false}) {
    findClear();
    if (_disposed || query.isEmpty) return 0;

    _matches.addAll(_terminal.search(query, caseSensitive: caseSensitive));
    if (_matches.isNotEmpty) {
      _controller.setSearchHighlights(_terminal.buffer, [
        for (final match in _matches) match.range,
      ], currentIndex: 0);
      findJump(0);
    }
    return _matches.length;
  }

  @override
  void findJump(int index) {
    if (_disposed || _matches.isEmpty) return;
    final clamped = index.clamp(0, _matches.length - 1);
    _controller.setCurrentSearchHighlight(clamped);
    _scrollToBufferLine(_matches[clamped].range.normalized.begin.y);
  }

  @override
  void findClear() {
    _matches.clear();
    if (!_disposed) _controller.clearSearchHighlights();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _keywordTimer?.cancel();
    _keywordTimer = null;
    _clearKeywordHighlights();
    await _sudoSub?.cancel();
    _terminal.removeListener(_onTerminalChanged);
    _matches.clear();
    _controller.dispose();
    _scrollController.dispose();
    _terminal.dispose();
    await _outgoingBytes.close();
    await _resizeEvents.close();
    await _activity.dispose();
  }

  /// The host platform, used to encode keyboard input: xterm3 needs to know
  /// which platform's key conventions apply (`Cmd` chords on Apple platforms,
  /// `Ctrl` elsewhere). On web this reports the browser's operating system.
  static xterm.TerminalTargetPlatform get _hostPlatform =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android => xterm.TerminalTargetPlatform.android,
        TargetPlatform.iOS => xterm.TerminalTargetPlatform.ios,
        TargetPlatform.macOS => xterm.TerminalTargetPlatform.macos,
        TargetPlatform.windows => xterm.TerminalTargetPlatform.windows,
        TargetPlatform.linux => xterm.TerminalTargetPlatform.linux,
        TargetPlatform.fuchsia => xterm.TerminalTargetPlatform.fuchsia,
      };

  /// Physical pixels per logical pixel, used to keep the PTY's pixel geometry
  /// in the same units the native renderer reports.
  static double get _devicePixelRatio {
    try {
      return WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
    } catch (_) {
      // No window attached (headless tests): logical pixels stand in.
      return 1;
    }
  }

  /// The emulator instance, for tests that assert terminal modes (cursor
  /// visibility, blink) instead of rendered pixels.
  @visibleForTesting
  xterm.Terminal get debugTerminal => _terminal;

  /// Number of keyword tints currently drawn, for tests that assert the
  /// keyword-highlight pass ran without inspecting painted pixels.
  @visibleForTesting
  int get debugKeywordHighlightCount => _keywordHighlights.length;

  xterm.TerminalTheme get _theme {
    final ansi = colorScheme.ansiColors;
    return xterm.TerminalTheme(
      cursor: colorScheme.cursor,
      selection: colorScheme.selection,
      foreground: colorScheme.foreground,
      background: colorScheme.background,
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
      // Find hits reuse the palette: every hit is a selection, the active one
      // is painted in the cursor colour so it stands out from the rest.
      searchHitBackground: colorScheme.selection,
      searchHitBackgroundCurrent: colorScheme.cursor,
      searchHitForeground: colorScheme.background,
    );
  }

  void _onTerminalOutput(String data) {
    if (_disposed || data.isEmpty) return;
    _activity.sentInput(data);
    _outgoingBytes.add(utf8.encode(data));
  }

  void _onTerminalResize(
    int columns,
    int rows,
    int cellPixelWidth,
    int cellPixelHeight,
  ) {
    if (_disposed || (columns == _lastColumns && rows == _lastRows)) return;
    _lastColumns = columns;
    _lastRows = rows;
    final ratio = _devicePixelRatio;
    _resizeEvents.add(
      TerminalResize(
        columns: columns,
        rows: rows,
        // xterm3 reports the size of one cell; [TerminalResize] carries the
        // viewport size a PTY reports through TIOCGWINSZ (ws_xpixel/ws_ypixel),
        // so the grid is multiplied out and converted to physical pixels.
        pixelWidth: (columns * cellPixelWidth * ratio).round(),
        pixelHeight: (rows * cellPixelHeight * ratio).round(),
      ),
    );
  }

  void _onCurrentDirectory(String uri) {
    _directory = TerminalWorkingDirectoryTracker.decode(uri);
  }

  void _onTerminalChanged() {
    _scheduleKeywordHighlightRefresh();
    _maybeAutoCopySelection();
  }

  void _applyCursorVisibility(bool showCursor) {
    final escape = showCursor ? '\x1b[?25h' : '\x1b[?25l';
    if (_cursorVisibilityEscape == escape) return;
    _cursorVisibilityEscape = escape;
    // Writing a mode notifies the mounted view, which must not happen inside
    // build, so the escape is applied on the next frame. It never reaches the
    // remote shell: it is the renderer's own state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _terminal.write(escape);
    });
  }

  Future<void> _openLink(String uri) async {
    if (_disposed) return;
    try {
      final parsed = Uri.tryParse(uri);
      if (parsed != null) {
        await launchUrl(parsed, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // No handler for this scheme on the host platform.
    }
  }

  FocusOnKeyEventCallback _wrapKeyEventForShiftInsert(
    FocusOnKeyEventCallback? delegate,
  ) => (node, event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_pasteFromClipboard());
      return KeyEventResult.handled;
    }
    return delegate?.call(node, event) ?? KeyEventResult.ignored;
  };

  String? _selectedText() {
    final range = _controller.selectionFor(_terminal.buffer);
    if (range == null) return null;
    return _terminal.buffer.getText(range, true);
  }

  void _copySelectionToClipboard() {
    if (_disposed) return;
    final text = _selectedText();
    if (text != null && text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_disposed) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && !_disposed) {
      _terminal.paste(text);
    }
  }

  void _selectAll() {
    if (_disposed) return;
    final buffer = _terminal.buffer;
    final lines = buffer.lines.length;
    if (lines == 0) return;
    // Anchors over the whole buffer; the controller owns them from here and
    // disposes them when the selection is replaced or cleared.
    _controller.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(buffer.viewWidth - 1, lines - 1),
    );
  }

  /// Auto-copies the active selection to the clipboard (select-to-copy).
  ///
  /// The terminal notifies on every buffer change, so the selection text is
  /// diffed against the last copied value to avoid redundant clipboard writes.
  void _maybeAutoCopySelection() {
    if (_disposed || !selectToCopyEnabled) return;
    final text = _selectedText();
    if (text == null || text.isEmpty) {
      _lastAutoCopiedSelection = null;
      return;
    }
    if (text == _lastAutoCopiedSelection) return;
    _lastAutoCopiedSelection = text;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void _scrollToBufferLine(int line) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // A row height is only known once the view has painted; fall back to the
    // native adapter's 18px estimate so the jump still lands near the match.
    final lineHeight = _viewKey.currentState?.renderTerminal.lineHeight ?? 18.0;
    if (lineHeight <= 0) return;
    final target =
        line * lineHeight - (position.viewportDimension - lineHeight) / 2;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  /// Schedules one keyword-tint pass.
  ///
  /// Output arrives in bursts, and the terminal notifies once per chunk, so the
  /// scan is deferred and coalesced rather than run per write.
  void _scheduleKeywordHighlightRefresh() {
    if (_disposed || !keywordHighlightEnabled || _keywordTimer != null) return;
    _keywordTimer = Timer(const Duration(milliseconds: 250), () {
      _keywordTimer = null;
      _refreshKeywordHighlights();
    });
  }

  /// Tints keyword matches in the rows that are actually on screen.
  ///
  /// Matches are highlighted as buffer anchors, so a tint follows its text
  /// through scrolling and reflow until the next pass replaces it.
  void _refreshKeywordHighlights() {
    if (_disposed || !keywordHighlightEnabled) return;
    final range = _visibleBufferLines();
    if (range == null) return;

    _clearKeywordHighlights();
    final buffer = _terminal.buffer;
    for (var line = range.$1; line <= range.$2; line++) {
      if (_keywordHighlights.length >= _maxKeywordHighlights) break;
      final bufferLine = buffer.lines[line];
      final text = bufferLine.getText();
      if (text.isEmpty) continue;
      for (final rule in terminalKeywordRules) {
        for (final match in rule.pattern.allMatches(text)) {
          if (_keywordHighlights.length >= _maxKeywordHighlights) break;
          final start = _cellForTextOffset(bufferLine, match.start);
          final end = _cellForTextOffset(bufferLine, match.end);
          if (end <= start) continue;
          _keywordHighlights.add(
            _controller.highlight(
              p1: buffer.createAnchor(start, line),
              p2: buffer.createAnchor(end, line),
              color: rule.color,
            ),
          );
        }
      }
    }
  }

  void _clearKeywordHighlights() {
    for (final highlight in _keywordHighlights) {
      highlight.dispose();
    }
    _keywordHighlights.clear();
  }

  /// The rows the viewport currently shows, as `(first, last)` buffer indices.
  (int, int)? _visibleBufferLines() {
    final state = _viewKey.currentState;
    if (state == null || !_scrollController.hasClients) return null;
    final lineHeight = state.renderTerminal.lineHeight;
    if (lineHeight <= 0) return null;
    final lines = _terminal.buffer.lines.length;
    if (lines == 0) return null;
    final position = _scrollController.position;
    final first = (position.pixels / lineHeight).floor().clamp(0, lines - 1);
    final rows = (position.viewportDimension / lineHeight).ceil() + 1;
    return (first, (first + rows).clamp(first, lines - 1));
  }

  /// Maps a character offset in [line]'s text to the cell it starts at.
  ///
  /// [xterm.BufferLine.getText] takes cell indices, and one cell can render as
  /// several characters (a wide glyph plus its combining marks) or none at all,
  /// so the cell index is found by binary search over the text prefix length
  /// rather than by assuming one character per cell.
  int _cellForTextOffset(xterm.BufferLine line, int offset) {
    var low = 0;
    var high = line.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (line.getText(0, middle).length < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// Decodes a byte stream that arrives in arbitrary chunks.
///
/// [xterm.Terminal.write] takes Dart strings, but a socket delivers bytes, and
/// a UTF-8 sequence can straddle two chunks. Decoding each chunk on its own
/// would replace every split character with a replacement character that no
/// later chunk can repair, so the trailing bytes of an incomplete sequence are
/// held back until the rest of it arrives.
class _Utf8ByteDecoder {
  /// At most three bytes, the longest truncated UTF-8 sequence.
  var _pending = Uint8List(0);

  String add(Uint8List bytes) {
    final chunk = switch (_pending.isEmpty) {
      true => bytes,
      false =>
        Uint8List(_pending.length + bytes.length)
          ..setRange(0, _pending.length, _pending)
          ..setRange(_pending.length, _pending.length + bytes.length, bytes),
    };

    final held = _incompleteTailLength(chunk);
    if (held == 0) {
      _pending = Uint8List(0);
      return utf8.decode(chunk, allowMalformed: true);
    }
    _pending = chunk.sublist(chunk.length - held);
    return utf8.decode(
      Uint8List.sublistView(chunk, 0, chunk.length - held),
      allowMalformed: true,
    );
  }

  /// Length of the trailing bytes that begin a truncated UTF-8 sequence, or 0
  /// when [chunk] ends on a sequence boundary.
  static int _incompleteTailLength(Uint8List chunk) {
    var index = chunk.length - 1;
    for (var scanned = 0; index >= 0 && scanned < 3; scanned++, index--) {
      final byte = chunk[index];
      if (byte & 0xc0 == 0x80) continue; // Continuation byte.
      final expected = byte >= 0xf0
          ? 4
          : byte >= 0xe0
          ? 3
          : byte >= 0xc0
          ? 2
          : 1;
      final available = chunk.length - index;
      return available < expected ? available : 0;
    }
    return 0;
  }
}
