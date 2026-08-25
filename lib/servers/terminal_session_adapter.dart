import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

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

/// Answers remote `sudo` password prompts with the connection's stored
/// password.
///
/// The watcher inspects outgoing remote output for the localized sudo
/// password prompt. While such a prompt is the last thing on screen, a bare
/// Enter key press is replaced with the stored secret followed by Enter.
/// Any other keystroke disarms interception so manual entry still works, and
/// the flag re-evaluates on every output chunk, so failed attempts ("Sorry,
/// try again") naturally re-arm once the prompt is redrawn.
class SudoPromptAutofill {
  SudoPromptAutofill(this.secret);

  /// Matches `[sudo] password for alice:` and zh_CN locales' `[sudo] alice
  /// 的密码：`. The `[sudo]` marker keeps unrelated questions (`su`, nested
  /// `ssh`, MySQL) out of scope so the SSH password never leaks to them.
  static final RegExp _prompt = RegExp(
    r'\[\s*sudo\s*\]\s*'
    r'(?:password(?:\s+for\s+[^:：\r\n]*)?|[^:：\r\n]*的密码)\s*[:：]\s*$',
  );

  /// Control sequences must not contribute characters to the matcher.
  static final RegExp _escapeSequences = RegExp(
    r'\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
  );

  final String? secret;

  /// Printable tail of the current output line used for prompt matching.
  var _lineTail = '';

  /// Whether the remote currently shows a sudo password prompt.
  var prompting = false;

  bool get _enabled => secret != null && secret!.isNotEmpty;

  /// Updates the prompt state from a chunk of remote output.
  void inspect(Uint8List bytes) {
    if (!_enabled) return;
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll(_escapeSequences, '');
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\r' || char == '\n') {
        _lineTail = '';
      } else {
        _lineTail += char;
        const maxTail = 160;
        if (_lineTail.length > maxTail) {
          _lineTail = _lineTail.substring(_lineTail.length - maxTail);
        }
      }
    }
    prompting = _prompt.hasMatch(_lineTail);
  }

  /// Returns the bytes to forward for one keyboard input event.
  ///
  /// A bare Enter at an active prompt becomes `<secret>\r`; anything else is
  /// forwarded untouched and disarms further interception.
  Uint8List intercept(Uint8List bytes) {
    if (!prompting || !_enabled) return bytes;
    prompting = false;
    final isBareEnter =
        bytes.length == 1 && (bytes[0] == 0x0d || bytes[0] == 0x0a);
    if (!isBareEnter) return bytes;
    return Uint8List.fromList(utf8.encode('${secret!}\r'));
  }
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
    String? autoFillSecret,
    this.outputFlushDelay = const Duration(milliseconds: 8),
  }) : // Public parameter names preserve the adapter binding API.
       // ignore: prefer_initializing_formals
       _send = send,
       // ignore: prefer_initializing_formals
       _resize = resize,
       _autofill = autoFillSecret == null || autoFillSecret.isEmpty
           ? null
           : SudoPromptAutofill(autoFillSecret),
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
  final SudoPromptAutofill? _autofill;
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
      _send(_autofill?.intercept(bytes) ?? bytes);
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
    _autofill?.inspect(bytes);
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
