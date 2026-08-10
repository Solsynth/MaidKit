import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' as vt;
import 'package:libghostty/libghostty.dart' hide KeyEvent;
import 'package:meta/meta.dart';

import '../foundation.dart';
import '../rendering/kitty_png_decoder.dart';
import 'selection_gesture_driver.dart';
import 'terminal_controller.dart';
import 'terminal_input_client.dart';
import 'terminal_view_binding.dart';

@internal
class TerminalControllerImpl extends TerminalController
    implements TerminalViewBinding {
  static const _cr = 0x0d;
  static const _del = 0x7f;
  static const _formFeed = 0x0c;
  static const _space = 0x20;
  static const _macFunctionKeyStart = 0xF700;
  static const _macFunctionKeyEnd = 0xF8FF;

  static final _crBytes = Uint8List.fromList([_cr]);
  static final _formFeedBytes = Uint8List.fromList([_formFeed]);
  static final _clearScrollback = utf8.encode('\x1b[3J');
  static final _appCursorDown = Uint8List.fromList([0x1b, 0x4f, 0x42]);
  static final _appCursorUp = Uint8List.fromList([0x1b, 0x4f, 0x41]);
  static final _cursorDown = Uint8List.fromList([0x1b, 0x5b, 0x42]);
  static final _cursorUp = Uint8List.fromList([0x1b, 0x5b, 0x41]);

  @override
  final Terminal terminal;
  final _renderState = RenderState();
  final _keyEncoder = KeyEncoder();
  final _mouseEncoder = MouseEncoder();
  late final SelectionGestureDriver _selectionGesture;
  final vt.KeyEvent _keyEvent;
  final MouseEvent _mouseEvent;
  final TerminalInputClient _textInput;

  TerminalConfig _config;
  TerminalScreen _activeScreen = .primary;
  MouseTracking _mouseTracking = .none;
  KeyboardState _keyboardState = .hidden;
  Mods _virtualMods = const .none();
  var _preeditText = '';
  var _cursorKeyApplication = false;
  Brightness _brightness = .dark;
  var _cursorBlinking = true;
  var _wasFocused = false;
  var _selectionMutationDepth = 0;

  CellMetrics _lastMetrics = const .new(
    cellWidth: 0,
    cellHeight: 0,
    baseline: 0,
  );
  var _lastDevicePixelRatio = 1.0;

  FocusNode? _focusNode;
  ScrollController? _scrollController;
  var _lastCols = 0;
  var _lastRows = 0;

  TerminalControllerImpl({TerminalConfig config = const TerminalConfig()})
    : _config = config,
      _keyEvent = vt.KeyEvent(),
      _mouseEvent = MouseEvent(),
      _textInput = TerminalInputClient(),
      terminal = Terminal(
        cols: config.cols,
        rows: config.rows,
        maxScrollback: config.scrollbackLimit,
      ),
      super.base() {
    _selectionGesture = SelectionGestureDriver(terminal);
    installDefaultKittyPngDecoder();
    _textInput
      ..onTextCommitted = _handleTextCommitted
      ..onDelete = _handleDelete
      ..onPreeditChanged = _handlePreeditChanged
      ..onNewline = _handleNewline;
    _wireTerminalCallbacks();
    _applyModes();
    _applyTerminalOptions();
    terminal.addListener(_onTerminalChanged);
  }

  @override
  TerminalScreen get activeScreen => terminal.activeScreen;
  @override
  Position get cursorPosition {
    _renderState.update(terminal);
    return _renderState.cursor.position;
  }

  @override
  set brightness(Brightness value) {
    _textInput.keyboardAppearance = value;
    _brightness = value;
  }

  @override
  TerminalConfig get config => _config;

  @override
  set config(TerminalConfig value) {
    if (_config == value) return;
    _config = value;
    _applyModes();
    _applyTerminalOptions();
    _wireTerminalCallbacks();
    notifyListeners();
  }

  @override
  bool get cursorBlinks {
    if (!_cursorBlinking || !hasFocus) return false;
    if (_activeScreen == .alternate) return true;
    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) {
      return terminal.isViewportActive;
    }
    final position = scrollController.position;
    if (!position.hasContentDimensions) return terminal.isViewportActive;
    return position.pixels >= position.maxScrollExtent - 1.0;
  }

  @override
  bool get hasFocus => _focusNode?.hasFocus ?? false;

  @override
  bool get hasSelection => terminal.selection != null;

  @override
  KeyboardState get keyboardState => _keyboardState;

  @override
  MouseTracking get mouseTracking => _mouseTracking;

  @override
  String get preeditText => _preeditText;

  @override
  String get pwd => terminal.pwd;

  @override
  int get scrollbackRows => terminal.scrollbackRows;

  @override
  Scrollbar get scrollbar => terminal.scrollbar;

  @override
  String get title => terminal.title;

  @override
  int get totalRows => terminal.totalRows;

  @override
  Mods get virtualMods => _virtualMods;

  bool get _hasActiveComposition =>
      _textInput.hasActiveComposition || _preeditText.isNotEmpty;

  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      .linux || .macOS || .windows => true,
      .android || .fuchsia || .iOS => false,
    };
  }

  bool get _shouldForwardCompositionKeyToTextInput {
    return _hasActiveComposition && _textInput.isAttached && _isDesktopPlatform;
  }

  @override
  void attach(FocusNode focusNode, ScrollController scrollController) {
    _focusNode?.removeListener(_onFocusChanged);
    _focusNode = focusNode;
    _wasFocused = focusNode.hasFocus;
    _focusNode!.addListener(_onFocusChanged);
    _textInput.keyboardAppearance = _brightness;
    if (_wasFocused && _keyboardState != .disabled) {
      if (_keyboardState == .showing) {
        _textInput.show();
      } else {
        _textInput.ensureAttached(keyboardAppearance: _brightness);
      }
    }
    _scrollController = scrollController;
  }

  @override
  void cancelSelectionGesture() {
    _selectionGesture.reset();
    _setSelection(null, clearIfNull: true);
  }

  @override
  void clear() {
    if (_activeScreen == .alternate) return;
    clearSelection();
    terminal.write(_clearScrollback);
    _emitOutput(_formFeedBytes);
  }

  @override
  void clearSelection() {
    if (terminal.selection == null) return;
    _selectionGesture.reset();
    _setSelection(null, clearIfNull: true);
  }

  @override
  void clearVirtualMods() {
    if (_virtualMods.isEmpty) return;
    _virtualMods = const .none();
    notifyListeners();
  }

  @override
  Formatter createFormatter({
    required FormatterFormat format,
    bool unwrap = false,
    bool trim = false,
    FormatterExtra extra = const FormatterExtra(),
  }) {
    return Formatter(
      terminal: terminal,
      format: format,
      unwrap: unwrap,
      trim: trim,
      extra: extra,
    );
  }

  @override
  void detach() {
    _focusNode?.removeListener(_onFocusChanged);
    _focusNode = null;
    _wasFocused = false;
    _keyboardState = .hidden;
    _preeditText = '';
    _scrollController = null;
    _textInput.detach();
  }

  @override
  void disableKeyboard() => _updateKeyboardState(.disabled);

  @override
  void dispose() {
    terminal.removeListener(_onTerminalChanged);
    detach();
    _keyEvent.dispose();
    _mouseEvent.dispose();
    _selectionGesture.dispose();
    _keyEncoder.dispose();
    _mouseEncoder.dispose();
    _renderState.dispose();
    terminal.dispose();
    super.dispose();
  }

  @override
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!_hasActiveComposition &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        HardwareKeyboard.instance.isShiftPressed &&
        terminal.selection != null) {
      if (_extendSelection(event.logicalKey)) return .handled;
    }

    var key = keyFromPhysical(event.physicalKey);
    // Soft keyboards and IMEs synthesize key events without a physical key
    // (Android reports PhysicalKeyboardKey.none). Without a logical fallback
    // their backspace/enter/arrow presses would be dropped silently.
    if (key == .unidentified) {
      key = keyFromLogical(event.logicalKey) ?? key;
    }
    final KeyAction? action = switch (event) {
      KeyDownEvent() => .press,
      KeyUpEvent() => .release,
      KeyRepeatEvent() => .repeat,
      _ => null,
    };

    if (action == null) return .ignored;

    if (_shouldForwardCompositionKeyToTextInput) {
      return .skipRemainingHandlers;
    }

    final unshiftedCodepoint = unshiftedCodepointForKey(key);
    final mods = _currentMods();
    final character = _encoderCharacter(event.character);
    final consumedMods = _consumedModsFor(
      character,
      unshiftedCodepoint: unshiftedCodepoint,
      mods: mods,
    );

    _keyEvent
      ..key = key
      ..mods = mods
      ..action = action
      ..utf8 = character
      ..consumedMods = consumedMods
      ..unshiftedCodepoint = unshiftedCodepoint
      ..composing = _hasActiveComposition;

    _keyEncoder.sync(terminal);
    final result = _keyEncoder.encode(_keyEvent);
    if (result.isEmpty) return _hasActiveComposition ? .handled : .ignored;

    if (_shouldRouteKeyThroughTextInput(
      action: action,
      character: character,
      encoded: result,
      mods: mods,
    )) {
      _onTextInput();
      return .skipRemainingHandlers;
    }

    clearVirtualMods();
    final forwardToPlatformIme = _consumeCommittedCompositionEditKey(
      key,
      action,
      mods,
    );
    _emitOutput(utf8.encode(result));
    _onTextInput();

    return forwardToPlatformIme ? .skipRemainingHandlers : .handled;
  }

  @override
  void handleMouseEvent(TerminalMouseEvent event) {
    _mouseEvent
      ..action = event.action
      ..button = event.button
      ..mods = _currentMods()
      ..setPosition(
        x: event.pixelX * _lastDevicePixelRatio,
        y: event.pixelY * _lastDevicePixelRatio,
      );
    _mouseEncoder.sync(terminal);
    final result = _mouseEncoder.encode(_mouseEvent);
    if (result.isEmpty) return;
    _emitOutput(utf8.encode(result));
  }

  @override
  void handleResize({
    required int cols,
    required int rows,
    required CellMetrics metrics,
    required EdgeInsets padding,
    required double devicePixelRatio,
  }) {
    _lastCols = cols;
    _lastRows = rows;
    _lastMetrics = metrics;
    _lastDevicePixelRatio = devicePixelRatio;
    final cellWidthPx = (metrics.cellWidth * devicePixelRatio).round();
    final cellHeightPx = (metrics.cellHeight * devicePixelRatio).round();
    _mouseEncoder.setSize(
      MouseEncoderSize(
        screenWidth: cols * cellWidthPx,
        screenHeight: rows * cellHeightPx,
        cellWidth: cellWidthPx,
        cellHeight: cellHeightPx,
        paddingLeft: (padding.left * devicePixelRatio).round(),
        paddingRight: (padding.right * devicePixelRatio).round(),
        paddingTop: (padding.top * devicePixelRatio).round(),
        paddingBottom: (padding.bottom * devicePixelRatio).round(),
      ),
    );
    onResize?.call(cols, rows);

    if (terminal.modeGet(const TerminalMode.inBandResize())) {
      final report = SizeReportStyle.mode2048.encode(
        rows: rows,
        columns: cols,
        cellWidth: cellWidthPx,
        cellHeight: cellHeightPx,
      );
      _emitOutput(utf8.encode(report));
    }
  }

  @override
  void handleScroll(int lines) {
    if (_activeScreen != .alternate || lines == 0) return;

    if (_mouseTracking != .none) {
      final button = lines < 0 ? MouseButton.four : MouseButton.five;
      final count = lines.abs();

      if (count > 0) _mouseEncoder.sync(terminal);

      for (var i = 0; i < count; i++) {
        _mouseEvent
          ..action = .press
          ..button = button
          ..mods = _currentMods()
          ..setPosition(x: 0, y: 0);
        final result = _mouseEncoder.encode(_mouseEvent);
        if (result.isNotEmpty) _emitOutput(utf8.encode(result));
      }
      return;
    }

    final up = _cursorKeyApplication ? _appCursorUp : _cursorUp;
    final down = _cursorKeyApplication ? _appCursorDown : _cursorDown;
    final key = lines < 0 ? up : down;
    final count = lines.abs();
    final bytes = Uint8List(key.length * count);
    for (var i = 0; i < count; i++) {
      bytes.setRange(i * key.length, (i + 1) * key.length, key);
    }
    _emitOutput(bytes);
  }

  @override
  void handleSelectionPress({
    required Position cell,
    required Offset localPosition,
    required TerminalGestureSettings settings,
  }) {
    final ref = _viewportRef(cell);
    if (ref == null) {
      _setSelection(null, clearIfNull: true);
      return;
    }

    var selection = _selectionGesture.press(
      ref: ref,
      localPosition: localPosition,
      settings: settings,
    );
    if (selection != null &&
        settings.lineSelectMode == .full &&
        _selectionGesture.behavior == .line) {
      selection = _fullWidthLineSelection(selection);
    }
    _setSelection(selection, clearIfNull: true);
  }

  @override
  void handleSelectionRelease(Position cell) {
    _setSelection(_selectionGesture.release(_viewportRef(cell)));
  }

  @override
  void hideKeyboard() => _updateKeyboardState(.hidden);

  @override
  bool modeGet(TerminalMode mode) => terminal.modeGet(mode);

  @override
  void modeSet(TerminalMode mode, {required bool value}) {
    terminal.modeSet(mode, value: value);
  }

  @override
  void paste(String text) {
    if (text.isEmpty) return;
    final bracketed = terminal.modeGet(const .bracketedPaste());
    _emitOutput(pasteEncode(text, bracketed: bracketed));
    _scrollToBottomOnInput();
  }

  @override
  void requestFocus() => _focusNode?.requestFocus();

  @override
  void scrollToBottom() {
    if (_activeScreen == .alternate) return;
    terminal.scrollToBottom();
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      final max = controller.position.maxScrollExtent;
      if (max.isFinite) controller.jumpTo(max);
    }
  }

  @override
  void scrollToTop() {
    if (_activeScreen == .alternate) return;
    terminal.scrollToTop();
    final controller = _scrollController;
    if (controller != null && controller.hasClients) controller.jumpTo(0);
  }

  @override
  void selectAll() => _setSelection(terminal.selectAll());

  @override
  String selectedText({FormatterFormat format = .plain}) {
    final selection = terminal.selection;
    if (selection == null) return '';
    final formatted = terminal.formatSelection(
      format: format,
      unwrap: !selection.rectangle,
      selection: selection,
    );
    return formatted ?? '';
  }

  @override
  void selectRange({
    required Position start,
    required Position end,
    PointTag pointTag = .screen,
    bool rectangle = false,
  }) {
    _setSelection(
      .fromRefs(
        start: .at(terminal, start, pointTag: pointTag),
        end: .at(terminal, end, pointTag: pointTag),
        rectangle: rectangle,
      ),
    );
  }

  @override
  void sendKey(vt.Key key, {Mods mods = const .none()}) {
    final effectiveMods = mods | _virtualMods;
    final codepoint = unshiftedCodepointForKey(key);
    _keyEvent
      ..key = key
      ..mods = effectiveMods
      ..action = .press
      ..consumedMods = const .none()
      ..unshiftedCodepoint = codepoint
      ..utf8 = codepoint > 0 ? String.fromCharCode(codepoint) : null
      ..composing = false;

    _keyEncoder.sync(terminal);
    final result = _keyEncoder.encode(_keyEvent);
    if (result.isEmpty) return;
    _emitOutput(utf8.encode(result));
    clearVirtualMods();
  }

  @override
  void sendText(String text) {
    if (text.isEmpty) return;
    _emitOutput(utf8.encode(text));
    clearVirtualMods();
  }

  @override
  void showKeyboard() => _updateKeyboardState(.showing);

  @override
  void toggleMod(Mods mod) {
    _virtualMods = _virtualMods ^ mod;
    notifyListeners();
  }

  @override
  void unfocus() => _focusNode?.unfocus();

  @override
  void updateSelectionAutoscroll({
    required Position cell,
    required Offset localPosition,
    required bool rectangle,
  }) {
    if (_lastCols <= 0 || _lastRows <= 0) return;
    _setSelection(
      _selectionGesture.autoscroll(
        cell: _clampViewportPoint(cell),
        localPosition: localPosition,
        rectangle: rectangle,
        geometry: _selectionGestureGeometry(),
      ),
    );
    _syncScrollControllerToTerminal();
  }

  @override
  void updateSelectionDrag({
    required Position cell,
    required Offset localPosition,
    required bool rectangle,
  }) {
    final ref = _viewportRef(cell);
    if (ref == null) return;
    _setSelection(
      _selectionGesture.drag(
        ref: ref,
        localPosition: localPosition,
        rectangle: rectangle,
        geometry: _selectionGestureGeometry(),
      ),
    );
  }

  @override
  void updateTextInputGeometry({
    required Size editableSize,
    required Matrix4 transform,
    required Rect caretRect,
    required Rect composingRect,
  }) {
    _textInput.updateGeometry(
      editableSize: editableSize,
      transform: transform,
      caretRect: caretRect,
      composingRect: composingRect,
    );
  }

  @override
  void write(Uint8List data) => terminal.write(data);

  void _applyModes() {
    for (final entry in _config.modes.entries) {
      terminal.modeSet(entry.key, value: entry.value);
    }
  }

  void _applyTerminalOptions() {
    terminal.kittyImageStorageLimit = _config.kittyImageStorageLimit;
    terminal.setApcBufferLimit(_config.apcBufferLimit);
    terminal.setGlyphProtocol(enabled: _config.glyphProtocol);
    terminal.defaultCursorShape = _config.cursorStyle;
    terminal.defaultCursorBlink = _config.cursorBlink;
    _cursorBlinking = _effectiveCursorBlinking();
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Position _clampViewportPoint(Position position) {
    return Position(
      row: _clampInt(position.row, 0, _lastRows - 1),
      col: _clampInt(position.col, 0, _lastCols - 1),
    );
  }

  bool _consumeCommittedCompositionEditKey(
    vt.Key key,
    KeyAction action,
    Mods mods,
  ) {
    // A plain deletion immediately after a desktop candidate commit belongs
    // to the platform IME first. Modified deletions stay terminal-only so
    // protocol modes and shell shortcuts keep their encoded semantics.
    if (!_isDesktopPlatform) return false;
    if (action != .press && action != .repeat) return false;
    if (key != .backspace && key != .delete) return false;
    if (!mods.isEmpty) return false;
    return _textInput.consumeCommittedCompositionEdit();
  }

  Mods _consumedModsFor(
    String? character, {
    required int unshiftedCodepoint,
    required Mods mods,
  }) {
    // Flutter does not expose consumed modifiers, so this fallback only
    // accounts for Shift producing a different single-codepoint character.
    if (!mods.hasShift || character == null || unshiftedCodepoint == 0) {
      return const .none();
    }

    final codepoints = character.runes.iterator;
    if (!codepoints.moveNext()) return const .none();
    final codepoint = codepoints.current;
    if (codepoints.moveNext()) return const .none();
    if (codepoint == unshiftedCodepoint) return const .none();
    return const .shift();
  }

  Mods _currentMods() {
    var mods = _virtualMods;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) mods = mods | const .shift();
    if (keyboard.isControlPressed) mods = mods | const .ctrl();
    if (keyboard.isAltPressed) mods = mods | const .alt();
    if (keyboard.isMetaPressed) mods = mods | const .superKey();
    return mods;
  }

  bool _effectiveCursorBlinking() {
    return _config.cursorBlink ?? terminal.modeGet(const .cursorBlinking());
  }

  bool _emitKeyPress(
    vt.Key key, {
    Mods mods = const .none(),
    bool clearMods = true,
  }) {
    final codepoint = unshiftedCodepointForKey(key);
    _keyEvent
      ..key = key
      ..mods = mods
      ..action = .press
      ..consumedMods = const .none()
      ..unshiftedCodepoint = codepoint
      ..utf8 = codepoint > 0 ? String.fromCharCode(codepoint) : null
      ..composing = false;

    _keyEncoder.sync(terminal);
    final result = _keyEncoder.encode(_keyEvent);
    if (result.isEmpty) return false;

    _emitOutput(utf8.encode(result));
    if (clearMods) clearVirtualMods();
    return true;
  }

  void _emitOutput(Uint8List bytes) => onOutput?.call(bytes);

  void _ensureGridSize() {
    if (_lastRows > 0 && _lastCols > 0) return;
    _renderState.update(terminal);
    _lastRows = _renderState.rows;
    _lastCols = _renderState.cols;
  }

  bool _extendSelection(LogicalKeyboardKey arrowKey) {
    final SelectionAdjust? adjustment = switch (arrowKey) {
      .arrowRight => .right,
      .arrowLeft => .left,
      .arrowUp => .up,
      .arrowDown => .down,
      _ => null,
    };
    if (adjustment == null) return false;
    final selection = terminal.selection;
    if (selection == null) return false;
    _setSelection(selection.adjust(adjustment));
    return true;
  }

  Selection _fullWidthLineSelection(Selection selection) {
    final start = selection.start.positionIn(.viewport);
    final end = selection.end.positionIn(.viewport);
    if (start == null || end == null) return selection;
    _ensureGridSize();
    if (_lastCols <= 0) return selection;
    return Selection.fromRefs(
      start: .at(
        terminal,
        Position(row: start.row, col: 0),
        pointTag: .viewport,
      ),
      end: .at(
        terminal,
        Position(row: end.row, col: _lastCols - 1),
        pointTag: .viewport,
      ),
    );
  }

  void _handleDelete(int count) {
    if (count <= 0) return;

    var emitted = false;
    for (var i = 0; i < count; i++) {
      emitted =
          _emitKeyPress(.backspace, mods: _currentMods(), clearMods: false) ||
          emitted;
    }
    if (!emitted) return;

    clearVirtualMods();
    _onTextInput();
  }

  void _handleNewline() {
    _emitOutput(_crBytes);
    clearVirtualMods();
    _onTextInput();
  }

  void _handlePreeditChanged(String text) {
    if (_preeditText == text) return;
    _preeditText = text;
    if (text.isNotEmpty) _onTextInput();
    notifyListeners();
  }

  void _handlePwdChanged() {
    onPwdChanged?.call();
    notifyListeners();
  }

  TerminalSizeInfo _handleSizeQuery() {
    _renderState.update(terminal);
    return TerminalSizeInfo(
      rows: _renderState.rows,
      columns: _renderState.cols,
      cellWidth: (_lastMetrics.cellWidth * _lastDevicePixelRatio).round(),
      cellHeight: (_lastMetrics.cellHeight * _lastDevicePixelRatio).round(),
    );
  }

  void _handleTextCommitted(String text) {
    if (_virtualMods.isEmpty) {
      _emitOutput(utf8.encode(text));
      _onTextInput();
      return;
    }

    if (text.length == 1) {
      final key = keyFromCodepoint(text.codeUnitAt(0));
      if (key != null) {
        sendKey(key);
        return;
      }
    }

    _emitOutput(utf8.encode(text));
    clearVirtualMods();
    _onTextInput();
  }

  void _mutateSelection(void Function() mutate) {
    _selectionMutationDepth++;
    try {
      mutate();
    } finally {
      _selectionMutationDepth--;
    }
  }

  void _onFocusChanged() {
    final focused = _focusNode?.hasFocus ?? false;
    if (focused == _wasFocused) return;
    _wasFocused = focused;

    if (focused && _keyboardState == .showing) {
      _textInput.show();
    } else if (focused && _keyboardState != .disabled) {
      _textInput.ensureAttached(keyboardAppearance: _brightness);
    } else if (!focused) {
      if (_keyboardState == .showing) _keyboardState = .hidden;
      _textInput.hide();
    }

    if (!focused) clearVirtualMods();

    if (terminal.modeGet(const TerminalMode.focusEvent())) {
      final event = focused ? FocusEvent.gained : FocusEvent.lost;
      _emitOutput(utf8.encode(event.encode()));
    }

    notifyListeners();
  }

  void _onTerminalChanged() {
    var changed = false;

    final newMouseTracking = terminal.mouseTracking;
    if (newMouseTracking != _mouseTracking) {
      _mouseTracking = newMouseTracking;
      changed = true;
    }

    final newActiveScreen = terminal.activeScreen;
    if (newActiveScreen != _activeScreen) {
      _activeScreen = newActiveScreen;
      if (newActiveScreen == .primary) _applyModes();
      changed = true;
    }

    final newCursorKeyApp = terminal.modeGet(const .cursorKeys());
    if (newCursorKeyApp != _cursorKeyApplication) {
      _cursorKeyApplication = newCursorKeyApp;
      changed = true;
    }

    final newCursorBlinking = _effectiveCursorBlinking();
    if (newCursorBlinking != _cursorBlinking) {
      _cursorBlinking = newCursorBlinking;
      changed = true;
    }

    // terminal.selection uses the same synchronous listener path as output.
    // Controller-owned selection changes must preserve the scrollback viewport.
    if (_selectionMutationDepth == 0) _scrollToBottomOnOutput();
    if (changed) notifyListeners();
  }

  void _onTextInput() {
    if (_config.selectionClearOnTyping) clearSelection();
    _scrollToBottomOnInput();
  }

  void _scrollToBottomOnInput() {
    if (_activeScreen == .alternate) return;
    final policy = _config.scrollToBottom;
    if (policy == .onKeystroke || policy == .both) scrollToBottom();
  }

  void _scrollToBottomOnOutput() {
    if (_activeScreen == .alternate) return;
    final policy = _config.scrollToBottom;
    if (policy == .onOutput || policy == .both) scrollToBottom();
  }

  SelectionGestureGeometry _selectionGestureGeometry() {
    _ensureGridSize();
    return SelectionGestureGeometry(
      columns: _lastCols <= 0 ? 1 : _lastCols,
      cellWidth: _lastMetrics.cellWidth <= 0
          ? 1
          : _lastMetrics.cellWidth.round(),
      paddingLeft: 0,
      screenHeight: _lastMetrics.cellHeight <= 0
          ? 1
          : (_lastMetrics.cellHeight * (_lastRows <= 0 ? 1 : _lastRows))
                .round(),
    );
  }

  void _setSelection(Selection? value, {bool clearIfNull = false}) {
    if (value == null) {
      if (!clearIfNull || terminal.selection == null) return;
      _mutateSelection(() => terminal.selection = null);
      notifyListeners();
      return;
    }

    final current = terminal.selection;
    if (current != null && current.equal(value)) return;
    _mutateSelection(() => terminal.selection = value);
    notifyListeners();
  }

  bool _shouldRouteKeyThroughTextInput({
    required KeyAction action,
    required String? character,
    required String encoded,
    required Mods mods,
  }) {
    // Desktop printable keys are offered to Flutter text input only when the
    // terminal encoder produced the same literal character. Any protocol,
    // modifier, or composition-sensitive key stays on the terminal path.
    if (encoded != character) return false;
    if (_hasActiveComposition || !_textInput.isAttached) return false;
    if (!_isDesktopPlatform) return false;
    if (action != .press && action != .repeat) return false;
    if (!_virtualMods.isEmpty) return false;
    return !mods.hasCtrl && !mods.hasAlt && !mods.hasSuper;
  }

  void _syncScrollControllerToTerminal() {
    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) return;
    final target = terminal.scrollbar.offset * _lastMetrics.cellHeight;
    final position = scrollController.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (clamped == position.pixels) return;
    scrollController.jumpTo(clamped);
  }

  Future<void> _updateKeyboardState(KeyboardState newState) async {
    if (newState == _keyboardState) return;
    _keyboardState = newState;

    switch (newState) {
      case .showing when hasFocus:
        _focusNode?.requestFocus();
        _textInput.show();
      case .showing:
        _focusNode?.requestFocus();
      case .hidden when hasFocus:
        _textInput.hide();
        _textInput.ensureAttached(keyboardAppearance: _brightness);
      case .hidden:
        _textInput.hide();
      case .disabled:
        _textInput.hide();
    }

    notifyListeners();
  }

  GridRef? _viewportRef(Position position) {
    _ensureGridSize();
    if (_lastRows <= 0 || _lastCols <= 0) return null;
    return .at(terminal, _clampViewportPoint(position), pointTag: .viewport);
  }

  void _wireTerminalCallbacks() {
    terminal.onWritePty = _emitOutput;
    terminal.onBell = () => onBell?.call();
    terminal.onTitleChanged = () => onTitleChanged?.call();
    terminal.onPwdChanged = _handlePwdChanged;
    terminal.onColorScheme = () => _brightness == .light ? .light : .dark;
    terminal.onSize = _handleSizeQuery;
    terminal.onDeviceAttributes = () => _config.deviceAttributes;
    final enquiry = _config.enquiryResponse;
    terminal.onEnquiry = enquiry.isEmpty
        ? null
        : () => .fromList(utf8.encode(enquiry));
  }

  /// Filters out control characters and macOS function key private-use
  /// codepoints that should not be sent as UTF-8 text to the key encoder.
  static String? _encoderCharacter(String? character) {
    if (character == null || character.isEmpty) return null;
    final code = character.codeUnitAt(0);
    if (code < _space || code == _del) return null;
    if (code >= _macFunctionKeyStart && code <= _macFunctionKeyEnd) return null;
    return character;
  }
}
