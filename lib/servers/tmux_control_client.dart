import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Raised when a tmux control-mode client cannot be established: tmux is not
/// installed, the host refused `tmux -CC`, or the transport closed before the
/// client produced a session.
class TmuxControlException implements Exception {
  const TmuxControlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One notification from a `tmux -CC` client.
///
/// Control mode answers commands in blocks (`%begin` … `%end`) and reports
/// everything else as `%`-prefixed notifications. Unknown notifications are
/// dropped rather than raising, so a newer tmux stays usable.
sealed class TmuxEvent {
  const TmuxEvent();
}

/// Output produced by the pane `%N`: already decoded to the bytes a terminal
/// emulator expects.
class TmuxOutputEvent extends TmuxEvent {
  const TmuxOutputEvent(this.paneId, this.bytes);

  final String paneId;
  final List<int> bytes;

  @override
  bool operator ==(Object other) =>
      other is TmuxOutputEvent &&
      other.paneId == paneId &&
      _listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(paneId, Object.hashAll(bytes));
}

/// The layout of a window changed. [layout] is the tmux v2 JSON layout, which
/// requires the client flag set by `refresh-client -f new-layouts`.
class TmuxLayoutEvent extends TmuxEvent {
  const TmuxLayoutEvent(this.windowId, this.layout);

  final String windowId;
  final String layout;

  @override
  bool operator ==(Object other) =>
      other is TmuxLayoutEvent &&
      other.windowId == windowId &&
      other.layout == layout;

  @override
  int get hashCode => Object.hash(windowId, layout);
}

class TmuxWindowAddEvent extends TmuxEvent {
  const TmuxWindowAddEvent(this.windowId);

  final String windowId;

  @override
  bool operator ==(Object other) =>
      other is TmuxWindowAddEvent && other.windowId == windowId;

  @override
  int get hashCode => windowId.hashCode;
}

class TmuxWindowCloseEvent extends TmuxEvent {
  const TmuxWindowCloseEvent(this.windowId);

  final String windowId;

  @override
  bool operator ==(Object other) =>
      other is TmuxWindowCloseEvent && other.windowId == windowId;

  @override
  int get hashCode => windowId.hashCode;
}

class TmuxWindowRenamedEvent extends TmuxEvent {
  const TmuxWindowRenamedEvent(this.windowId, this.name);

  final String windowId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TmuxWindowRenamedEvent &&
      other.windowId == windowId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(windowId, name);
}

class TmuxWindowPaneChangedEvent extends TmuxEvent {
  const TmuxWindowPaneChangedEvent(this.windowId, this.paneId);

  final String windowId;
  final String paneId;

  @override
  bool operator ==(Object other) =>
      other is TmuxWindowPaneChangedEvent &&
      other.windowId == windowId &&
      other.paneId == paneId;

  @override
  int get hashCode => Object.hash(windowId, paneId);
}

class TmuxSessionChangedEvent extends TmuxEvent {
  const TmuxSessionChangedEvent(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      other is TmuxSessionChangedEvent && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// The client is gone: the transport closed, `detach-client` succeeded, or the
/// session ended. [reason] is tmux's own `%exit` text when it reported one.
class TmuxExitEvent extends TmuxEvent {
  const TmuxExitEvent([this.reason]);

  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is TmuxExitEvent && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

class TmuxSessionWindowChangedEvent extends TmuxEvent {
  const TmuxSessionWindowChangedEvent(this.sessionId, this.windowId);

  final String sessionId;
  final String windowId;

  @override
  bool operator ==(Object other) =>
      other is TmuxSessionWindowChangedEvent &&
      other.sessionId == sessionId &&
      other.windowId == windowId;

  @override
  int get hashCode => Object.hash(sessionId, windowId);
}

/// One completed command: the lines it answered with, and whether tmux
/// reported an error.
class TmuxBlockEvent extends TmuxEvent {
  const TmuxBlockEvent(this.number, this.lines, this.error);

  final int number;
  final List<String> lines;
  final bool error;

  @override
  bool operator ==(Object other) =>
      other is TmuxBlockEvent &&
      other.number == number &&
      other.error == error &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(number, error, Object.hashAll(lines));
}

/// A `tmux -CC` client speaking the control-mode protocol.
///
/// The client never attaches a session itself: the transport on the other side
/// of [output]/[write] runs `tmux -CC new-session -A -s <name>` on an allocated
/// pty, and this class only parses the conversation. Control mode needs that
/// pty, which is why it can never ride a plain command channel.
class TmuxControlClient {
  TmuxControlClient({
    required Stream<Uint8List> output,
    required void Function(List<int> bytes) write,
    required void Function(String reason) onClosed,
  }) : _writeSink = write,
       _closedHandler = onClosed {
    _subscription = output.listen(
      _consume,
      onError: (Object _) => _closeWith(null),
      onDone: () => _closeWith(_lastSessionReason),
      cancelOnError: false,
    );
  }

  /// How many input bytes one `send-keys -H` line may carry.
  ///
  /// A control command line is newline-terminated, so keystrokes that contain
  /// newlines or control bytes have to be hex-encoded; the chunk keeps a single
  /// command line comfortably small for any host's line discipline.
  static const sendKeysChunkBytes = 256;

  static const _dcsIntro = '\x1bP1000p';
  static const _lineFeed = 0x0a;
  static const _escape = 0x1b;
  static const _stringTerminator = 0x5c;

  final void Function(List<int> bytes) _writeSink;
  final void Function(String reason) _closedHandler;
  late final StreamSubscription<Uint8List> _subscription;

  final _controller = StreamController<TmuxEvent>.broadcast();
  final _pending = <int>[];
  final _completions = <int, Completer<TmuxBlockEvent>>{};
  final _queue = <int>[];
  final _blockLines = <String>[];
  var _nextBlock = 1;
  var _openBlock = 0;
  var _framingStripped = false;
  var _closed = false;
  String? _lastSessionReason;

  /// Every parsed event. Broadcast, so subscribers may attach and detach while
  /// a session runs.
  Stream<TmuxEvent> get events => _controller.stream;

  bool get isClosed => _closed;

  /// Runs one control command, completing with its block.
  ///
  /// Control mode answers commands in order, so a completion is matched to the
  /// command that is oldest in flight.
  Future<TmuxBlockEvent> command(String line) {
    if (line.contains('\n')) {
      throw ArgumentError.value(
        line,
        'line',
        'a command must be a single line',
      );
    }
    if (_closed) {
      return Future<TmuxBlockEvent>.error(
        StateError('tmux control client closed'),
      );
    }
    final number = _nextBlock++;
    final completer = Completer<TmuxBlockEvent>();
    _completions[number] = completer;
    _queue.add(number);
    _send(line);
    return completer.future;
  }

  /// Sends [bytes] to the pane [paneId] as keystrokes.
  void sendKeys(String paneId, List<int> bytes) {
    for (var start = 0; start < bytes.length; start += sendKeysChunkBytes) {
      final end = (start + sendKeysChunkBytes).clamp(0, bytes.length);
      final hex = [
        for (final byte in bytes.sublist(start, end))
          byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ].join(' ');
      _send('send-keys -H -t $paneId $hex');
    }
  }

  /// Reports the client's own terminal size, which tmux uses to size the
  /// session's windows.
  void resizeClient(int columns, int rows) {
    _send('refresh-client -C ${columns}x$rows');
  }

  /// Detaches this client, leaving the session running on the host.
  Future<void> detach() async {
    if (_closed) return;
    await command('detach-client');
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _closeWith(null);
    await _controller.close();
  }

  void _send(String line) {
    if (_closed) return;
    _writeSink(utf8.encode('$line\n'));
  }

  void _closeWith(String? reason) {
    if (_closed) return;
    _closed = true;
    final pending = [..._queue];
    _queue.clear();
    _blockLines.clear();
    _openBlock = 0;
    for (final number in pending) {
      final completer = _completions.remove(number);
      if (completer == null || completer.isCompleted) continue;
      completer.completeError(StateError('tmux control client closed'));
    }
    if (!_controller.isClosed) {
      _controller.add(TmuxExitEvent(reason));
    }
    _closedHandler(reason ?? '');
  }

  void _consume(Uint8List bytes) {
    if (_closed) return;
    _pending.addAll(bytes);
    while (_pending.isNotEmpty) {
      // A DCS string terminator closes the command block framing; it arrives
      // between lines, so it is dropped before any line is decoded.
      if (_pending.length >= 2 &&
          _pending[0] == _escape &&
          _pending[1] == _stringTerminator) {
        _pending.removeRange(0, 2);
        continue;
      }
      if (_pending.length == 1 && _pending[0] == _escape) return;
      final index = _pending.indexOf(_lineFeed);
      if (index < 0) return;
      final line = utf8.decode(
        _pending.sublist(0, index),
        allowMalformed: true,
      );
      _pending.removeRange(0, index + 1);
      _handleLine(
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      );
    }
  }

  void _handleLine(String line) {
    var text = line;
    if (!_framingStripped) {
      if (text.isEmpty) return;
      if (text.startsWith(_dcsIntro)) {
        text = text.substring(_dcsIntro.length);
      }
      _framingStripped = true;
      if (text.isEmpty) return;
    }
    if (!text.startsWith('%')) {
      if (_openBlock == 0) return;
      _blockLines.add(text);
      return;
    }
    final event = _parseNotification(text);
    if (event == null) return;
    if (event is TmuxExitEvent) _lastSessionReason = event.reason;
    if (!_controller.isClosed) _controller.add(event);
  }

  TmuxEvent? _parseNotification(String line) {
    final space = line.indexOf(' ');
    final name = space < 0 ? line : line.substring(0, space);
    final rest = space < 0 ? '' : line.substring(space + 1);
    switch (name) {
      case '%begin':
        return _openBlockStart(rest);
      case '%end':
        return _closeBlock(rest, error: false);
      case '%error':
        return _closeBlock(rest, error: true);
      case '%output':
        return _parseOutput(rest, extended: false);
      case '%extended-output':
        return _parseOutput(rest, extended: true);
      case '%layout-change':
        return _parseLayoutChange(rest);
      case '%window-add':
        return TmuxWindowAddEvent(rest.trim());
      case '%window-close':
        return TmuxWindowCloseEvent(rest.trim());
      case '%window-renamed':
        final split = rest.indexOf(' ');
        if (split < 0) return TmuxWindowRenamedEvent(rest.trim(), '');
        return TmuxWindowRenamedEvent(
          rest.substring(0, split),
          rest.substring(split + 1),
        );
      case '%window-pane-changed':
        final fields = rest.split(' ').where((f) => f.isNotEmpty).toList();
        if (fields.length < 2) return null;
        return TmuxWindowPaneChangedEvent(fields[0], fields[1]);
      case '%session-changed':
        final split = rest.indexOf(' ');
        if (split < 0) return TmuxSessionChangedEvent(rest.trim());
        return TmuxSessionChangedEvent(rest.substring(split + 1));
      case '%session-window-changed':
        final fields = rest.split(' ').where((f) => f.isNotEmpty).toList();
        if (fields.length < 2) return null;
        return TmuxSessionWindowChangedEvent(fields[0], fields[1]);
      case '%exit':
        final reason = rest.trim();
        return TmuxExitEvent(reason.isEmpty ? null : reason);
      default:
        return null;
    }
  }

  /// `%begin <time> <number> <flags>` opens a command's answer.
  TmuxEvent? _openBlockStart(String rest) {
    final fields = rest.split(' ');
    if (fields.length < 2) return null;
    final number = int.tryParse(fields[1]);
    if (number == null) return null;
    _openBlock = number;
    _blockLines.clear();
    return null;
  }

  /// `%end`/`%error <time> <number> <flags>` closes it.
  ///
  /// tmux numbers blocks per client and answers commands in the order they were
  /// sent, so a block number this client does not know about belongs to the
  /// oldest command still in flight. Correlating that way keeps a mismatched
  /// counter from leaving a future pending forever.
  TmuxEvent? _closeBlock(String rest, {required bool error}) {
    final fields = rest.split(' ');
    if (fields.length < 2) return null;
    final reported = int.tryParse(fields[1]);
    if (reported == null) return null;
    final number = _completions.containsKey(reported) || _queue.isEmpty
        ? reported
        : _queue.first;
    final lines = List<String>.unmodifiable(_blockLines);
    _blockLines.clear();
    _openBlock = 0;
    final completer = _completions.remove(number);
    _queue.remove(number);
    if (completer != null && !completer.isCompleted) {
      completer.complete(TmuxBlockEvent(number, lines, error));
    }
    return TmuxBlockEvent(number, lines, error);
  }

  TmuxEvent? _parseOutput(String rest, {required bool extended}) {
    final space = rest.indexOf(' ');
    if (space < 0) return null;
    final paneId = rest.substring(0, space);
    var payload = rest.substring(space + 1);
    if (extended) {
      // `%extended-output %<id> <age> … : <data>` — the colon that separates the
      // metadata from the payload is the last field boundary before it.
      final colon = payload.indexOf(': ');
      payload = colon < 0 ? '' : payload.substring(colon + 2);
    }
    return TmuxOutputEvent(paneId, _decodeEscapes(payload));
  }

  TmuxEvent? _parseLayoutChange(String rest) {
    final space = rest.indexOf(' ');
    final windowId = space < 0 ? rest.trim() : rest.substring(0, space);
    if (space < 0) return null;
    final remainder = rest.substring(space + 1).trimLeft();
    if (!remainder.startsWith('{')) {
      final end = remainder.indexOf(' ');
      final layout = end < 0 ? remainder : remainder.substring(0, end);
      return TmuxLayoutEvent(windowId, layout);
    }
    // The JSON layout contains no spaces of its own, but a balanced brace scan
    // keeps the parse correct if a build emits them.
    var depth = 0;
    var inString = false;
    var end = -1;
    for (var i = 0; i < remainder.length; i++) {
      final char = remainder[i];
      if (inString) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == '"') inString = false;
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;
    return TmuxLayoutEvent(windowId, remainder.substring(0, end + 1));
  }

  /// Decodes tmux's octal (`\NNN`) and backslash escapes into raw bytes.
  static List<int> _decodeEscapes(String value) {
    final bytes = <int>[];
    for (var i = 0; i < value.length; i++) {
      final char = value.codeUnitAt(i);
      if (char != 0x5c) {
        bytes.add(char);
        continue;
      }
      if (i + 1 >= value.length) {
        bytes.add(char);
        continue;
      }
      final next = value.codeUnitAt(i + 1);
      if (next == 0x5c) {
        bytes.add(0x5c);
        i++;
        continue;
      }
      if (next >= 0x30 && next <= 0x37 && i + 3 < value.length) {
        final octal = value.substring(i + 1, i + 4);
        final decoded = int.tryParse(octal, radix: 8);
        if (decoded != null) {
          bytes.add(decoded & 0xff);
          i += 3;
          continue;
        }
      }
      bytes.add(char);
    }
    return bytes;
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
