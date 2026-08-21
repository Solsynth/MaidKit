import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Flutter text input connection for terminal editing.
///
/// The terminal has no editable text buffer, so this client keeps a sentinel
/// editing value only to give platform IMEs an anchor for composing ranges.
/// It turns platform edits into terminal events: committed text, newlines,
/// deletions, and visible preedit text.
@internal
final class TerminalInputClient with DeltaTextInputClient {
  static final _newlinePattern = RegExp(r'\r\n|[\n\r]');
  static final _singleNewlinePattern = RegExp(r'^(?:\r\n|[\n\r])$');
  static const _newlineActionDedupeWindow = Duration(milliseconds: 100);
  static const _sentinel = TextEditingValue(
    selection: .collapsed(offset: 1),
    text: ' ',
  );

  TextInputConnection? _connection;
  TextEditingValue _value = _sentinel;
  Brightness _keyboardAppearance = .dark;
  Timer? _newlineActionDedupeTimer;
  var _suppressNextNewlineDelta = false;
  var _suppressNextNewlineAction = false;
  _CommittedCompositionEdit _committedCompositionEdit = .none;
  var _hadVisiblePreeditText = false;

  VoidCallback? _onNewline;
  ValueChanged<int>? _onDelete;
  ValueChanged<String>? _onTextCommitted;
  ValueChanged<String>? _onPreeditChanged;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  /// Whether the platform owns a composing range, even when no visible
  /// preedit text should be rendered.
  bool get hasActiveComposition => _value.hasTerminalComposingRange;

  bool get isAttached => _connection != null;

  set keyboardAppearance(Brightness value) {
    if (_keyboardAppearance == value) return;
    _keyboardAppearance = value;
    _connection?.updateConfig(_configuration);
  }

  set onDelete(ValueChanged<int>? callback) => _onDelete = callback;

  set onNewline(VoidCallback? callback) => _onNewline = callback;

  set onPreeditChanged(ValueChanged<String>? callback) {
    _onPreeditChanged = callback;
  }

  set onTextCommitted(ValueChanged<String>? callback) {
    _onTextCommitted = callback;
  }

  TextInputConfiguration get _configuration {
    return TextInputConfiguration(
      // The engine rejects TextInput.setClient without a view ID (Windows
      // raises "Could not set client, view ID is null."), which silently
      // kills all terminal input. Match EditableText by pinning the implicit
      // view; this app runs a single window, so it is the terminal's view.
      viewId: PlatformDispatcher.instance.implicitView?.viewId,
      autocorrect: false,
      inputType: .multiline,
      inputAction: .newline,
      smartDashesType: .disabled,
      smartQuotesType: .disabled,
      enableDeltaModel: true,
      enableSuggestions: false,
      enableInlinePrediction: false,
      enableInteractiveSelection: false,
      enableIMEPersonalizedLearning: false,
      keyboardAppearance: _keyboardAppearance,
    );
  }

  void attach({Brightness keyboardAppearance = .dark}) {
    _closeConnection();
    _keyboardAppearance = keyboardAppearance;
    _openConnection();
  }

  @override
  void connectionClosed() {
    _connection = null;
    _resetInputState();
  }

  /// Lets one plain desktop Backspace/Delete reach the platform IME after a
  /// candidate commit, while arming suppression for the matching edit delta.
  bool consumeCommittedCompositionEdit() {
    if (_committedCompositionEdit != .pending) return false;
    _committedCompositionEdit = .suppressNextDeletionDelta;
    return true;
  }

  void detach() => _closeConnection();

  @override
  void didChangeInputControl(TextInputControl? _, TextInputControl? _) {}

  void ensureAttached({Brightness keyboardAppearance = Brightness.dark}) {
    _keyboardAppearance = keyboardAppearance;
    final connection = _connection;
    if (connection == null) return _openConnection();
    connection.updateConfig(_configuration);
  }

  void hide() => _closeConnection();

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  bool onFocusReceived() => false;

  @override
  void performAction(TextInputAction action) {
    if (action != .newline) return;
    if (_suppressNextNewlineAction) {
      _clearNewlineActionSuppression();
      return;
    }
    _onNewline?.call();
    _suppressNextNewlineDeltaSoon();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void removeTextPlaceholder() {}

  void show() {
    ensureAttached(keyboardAppearance: _keyboardAppearance);
    _connection?.show();
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void showToolbar() {}

  @override
  void updateEditingValue(TextEditingValue value) {
    final expireSuppressionAfterUpdate =
        _committedCompositionEdit == .suppressNextDeletionDelta;
    _value = value;
    _processEditingValue(value);
    if (expireSuppressionAfterUpdate &&
        _committedCompositionEdit == .suppressNextDeletionDelta) {
      _clearCommittedCompositionEdit();
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    final expireSuppressionAfterBatch =
        _committedCompositionEdit == .suppressNextDeletionDelta;
    var fromCompositionInBatch = _hadVisiblePreeditText || hasActiveComposition;
    for (final delta in deltas) {
      _value = delta.apply(_value);
      _processDelta(delta, fromCompositionInBatch: fromCompositionInBatch);
      fromCompositionInBatch = fromCompositionInBatch || _hadVisiblePreeditText;
    }
    if (expireSuppressionAfterBatch &&
        _committedCompositionEdit == .suppressNextDeletionDelta) {
      _clearCommittedCompositionEdit();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  /// Anchors native composing and candidate UI to the terminal cursor cell.
  void updateGeometry({
    required Size editableSize,
    required Matrix4 transform,
    required Rect caretRect,
    required Rect composingRect,
  }) {
    final connection = _connection;
    if (connection == null) return;
    connection
      ..setEditableSizeAndTransform(editableSize, transform)
      ..setCaretRect(caretRect)
      ..setComposingRect(composingRect);
  }

  void _armNewlineActionDedupeTimer() {
    _newlineActionDedupeTimer?.cancel();
    _newlineActionDedupeTimer = Timer(
      _newlineActionDedupeWindow,
      _clearNewlineActionSuppression,
    );
  }

  void _clearCommittedCompositionEdit() {
    _committedCompositionEdit = .none;
  }

  void _clearNewlineActionSuppression() {
    _newlineActionDedupeTimer?.cancel();
    _newlineActionDedupeTimer = null;
    _suppressNextNewlineDelta = false;
    _suppressNextNewlineAction = false;
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
    _resetInputState();
  }

  void _commitEndedCompositionFromValue() {
    final committed = _value.terminalCommittedText;
    if (committed.isEmpty) {
      _clearCommittedCompositionEdit();
      return;
    }
    _commitInputText(committed, fromComposition: true);
  }

  void _commitInputText(String text, {required bool fromComposition}) {
    _commitText(text);
    _committedCompositionEdit =
        text.isNotEmpty && (fromComposition || text.isImeLikeCommit)
        ? .pending
        : .none;
    _resetBuffer();
  }

  void _commitText(String text) {
    final singleNewline = _singleNewlinePattern.hasMatch(text);
    if (singleNewline && _suppressNextNewlineDelta) {
      _clearNewlineActionSuppression();
      return;
    }

    var offset = 0;
    for (final match in _newlinePattern.allMatches(text)) {
      final chunk = text.substring(offset, match.start);
      if (chunk.isNotEmpty) _onTextCommitted?.call(chunk);
      _onNewline?.call();
      offset = match.end;
    }

    final tail = text.substring(offset);
    if (tail.isNotEmpty) _onTextCommitted?.call(tail);
    if (singleNewline) _suppressNextNewlineActionSoon();
  }

  void _openConnection() {
    final connection = TextInput.attach(this, _configuration);
    _connection = connection;
    _value = _sentinel;
    connection.setEditingState(_value);
  }

  void _processDelta(
    TextEditingDelta delta, {
    required bool fromCompositionInBatch,
  }) {
    final preeditText = _value.terminalComposingText;
    final hasActiveComposition = _value.hasTerminalComposingRange;
    final hasVisiblePreeditText = preeditText.isNotEmpty;
    var committedFromDelta = false;
    final String? committedText = switch (delta) {
      TextEditingDeltaInsertion(:final textInserted)
          when !hasActiveComposition =>
        textInserted,
      TextEditingDeltaReplacement(:final replacementText)
          when !hasActiveComposition =>
        replacementText,
      _ => null,
    };

    if (committedText != null) {
      _commitInputText(committedText, fromComposition: fromCompositionInBatch);
      committedFromDelta = true;
    } else if (delta is TextEditingDeltaDeletion &&
        !hasActiveComposition &&
        !_hadVisiblePreeditText) {
      // After an IME candidate commit, desktop IMEs may report the first
      // plain delete through both the raw key path and the text-input delta
      // path. The controller forwards that key to the platform once, and this
      // client drops only the matching deletion delta.
      if (_committedCompositionEdit == .suppressNextDeletionDelta) {
        _clearCommittedCompositionEdit();
        _resetBuffer();
        return;
      }
      final count = delta.deletedRange.end - delta.deletedRange.start;
      _onDelete?.call(count);
      _clearCommittedCompositionEdit();
      _resetBuffer();
    }

    if (hasVisiblePreeditText) {
      _clearCommittedCompositionEdit();
      _onPreeditChanged?.call(preeditText);
    } else if (_hadVisiblePreeditText) {
      if (!committedFromDelta) _commitEndedCompositionFromValue();
      _onPreeditChanged?.call('');
    }

    _hadVisiblePreeditText = hasVisiblePreeditText;
  }

  void _processEditingValue(TextEditingValue value) {
    final preeditText = value.terminalComposingText;
    if (preeditText.isNotEmpty) {
      _clearCommittedCompositionEdit();
      _onPreeditChanged?.call(preeditText);
      _hadVisiblePreeditText = true;
      return;
    }

    final hadVisiblePreeditText = _hadVisiblePreeditText;
    if (hadVisiblePreeditText) _commitEndedCompositionFromValue();
    if (hadVisiblePreeditText) _onPreeditChanged?.call('');
    _hadVisiblePreeditText = false;
    if (hadVisiblePreeditText) return;

    final committed = value.terminalCommittedText;
    if (committed.isNotEmpty) {
      _commitInputText(committed, fromComposition: false);
    } else if (value.text.length < _sentinel.text.length) {
      // Platforms that report edits as full editing values (rather than
      // deltas) shrink the sentinel buffer when the user presses backspace.
      // Without this branch the deletion would be silently dropped.
      if (_committedCompositionEdit == .suppressNextDeletionDelta) {
        // The platform already applied this deletion on our behalf.
        _clearCommittedCompositionEdit();
        _resetBuffer();
        return;
      }
      _onDelete?.call(_sentinel.text.length - value.text.length);
      _clearCommittedCompositionEdit();
      _resetBuffer();
    }
  }

  void _resetBuffer() {
    _value = _sentinel;
    _connection?.setEditingState(_value);
  }

  void _resetInputState() {
    final hadVisiblePreeditText =
        _hadVisiblePreeditText || _value.terminalComposingText.isNotEmpty;
    _value = _sentinel;
    _clearNewlineActionSuppression();
    _clearCommittedCompositionEdit();
    _hadVisiblePreeditText = false;
    if (hadVisiblePreeditText) _onPreeditChanged?.call('');
  }

  void _suppressNextNewlineActionSoon() {
    _suppressNextNewlineAction = true;
    _armNewlineActionDedupeTimer();
  }

  void _suppressNextNewlineDeltaSoon() {
    _suppressNextNewlineDelta = true;
    _armNewlineActionDedupeTimer();
  }
}

enum _CommittedCompositionEdit { none, pending, suppressNextDeletionDelta }

/// Extracts terminal-owned text from Flutter's sentinel editing value.
extension _TerminalEditingValue on TextEditingValue {
  bool get hasTerminalComposingRange {
    final composing = this.composing;
    return composing.isValid &&
        !composing.isCollapsed &&
        composing.start >= 0 &&
        composing.end <= text.length;
  }

  String get terminalCommittedText =>
      _withoutTerminalInputSentinel(0, text.length);

  String get terminalComposingText {
    if (!hasTerminalComposingRange) return '';
    final composing = this.composing;
    return _withoutTerminalInputSentinel(composing.start, composing.end);
  }

  String _withoutTerminalInputSentinel(int start, int end) {
    var contentStart = start;
    if (start == 0 &&
        end > 0 &&
        text.startsWith(TerminalInputClient._sentinel.text)) {
      contentStart = TerminalInputClient._sentinel.text.length;
    }
    if (contentStart >= end) return '';
    return text.substring(contentStart, end);
  }
}

extension _TerminalInputString on String {
  bool get isImeLikeCommit => codeUnits.any((codeUnit) => codeUnit > 0x7f);
}
