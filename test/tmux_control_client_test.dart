import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/tmux_control_client.dart';

/// A control client wired to a hand-driven transport.
class _Harness {
  _Harness() {
    client = TmuxControlClient(
      output: _output.stream,
      write: writes.add,
      onClosed: closed.add,
    );
    eventsSubscription = client.events.listen(events.add);
  }

  final _output = StreamController<Uint8List>();
  final writes = <List<int>>[];
  final closed = <String>[];
  final events = <TmuxEvent>[];
  late final TmuxControlClient client;
  late final StreamSubscription<TmuxEvent> eventsSubscription;

  void feed(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  void feedBytes(List<int> bytes) => _output.add(Uint8List.fromList(bytes));

  String get written => writes.map((w) => utf8.decode(w)).join();

  /// The greeting a real attach produces: tmux opens a block of its own before
  /// the client asks anything, with the DCS intro glued to its front.
  ///
  /// The number is deliberately not 1: tmux uses its own counter for this
  /// block, which is exactly what used to be misread as the first command's
  /// answer.
  void greeting() => feed('\x1bP1000p%begin 1 312 0\n%end 1 312 0\n');

  Future<void> end() => _output.close();

  Future<void> dispose() async {
    await eventsSubscription.cancel();
    if (!_output.isClosed) await _output.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a block answers the pending command', () async {
    final harness = _Harness();
    // Before the greeting, tmux is not accepting commands, so the line waits.
    final pending = harness.client.command('list-sessions');
    expect(harness.written, isEmpty);
    harness.greeting();
    await pumpEventQueue();
    expect(harness.written, 'list-sessions\n');
    harness.feed('%begin 1 314 0\nhello\n%end 1 314 0\n');
    final block = await pending;
    // The answer is matched to the pending command even though tmux numbered
    // the attach block first: that block is the attach's, not an answer.
    expect(block.lines, ['hello']);
    expect(block.lines, ['hello']);
    expect(block.error, isFalse);
    await harness.dispose();
  });

  test('the attach block does not steal the first command\'s answer', () async {
    // What a real attach looks like: tmux opens and closes a block of its own
    // before any command exists, then answers the client's commands in order.
    // Counting that first block shifted every completion by one, so the window
    // list's answer landed on the layout pull and both were lost - an empty
    // tab on every tmux version.
    final harness = _Harness();
    final windows = harness.client.command('list-windows');
    final layout = harness.client.command('display-message');
    harness.greeting();
    harness.feed('%begin 1 314 0\n@0\t0\tzsh\t1\n%end 1 314 0\n');
    harness.feed('%begin 1 315 0\nLAYOUT\n%end 1 315 0\n');
    expect((await windows).lines, ['@0\t0\tzsh\t1']);
    expect((await layout).lines, ['LAYOUT']);
    await harness.dispose();
  });

  test('a login banner and OSC before the DCS intro are skipped', () async {
    // What a real SSH shell produces: the host's motd, the echoed command, and
    // a shell-integration OSC all precede the intro, and the intro does not
    // start a line of its own. Treating that line as control data left the
    // client waiting for a greeting it had already received, so nothing was
    // ever sent and the tab stayed empty.
    final harness = _Harness();
    final windows = harness.client.command('list-windows');
    expect(harness.written, isEmpty);
    harness.feed('Welcome to Ubuntu 26.04.1 LTS\r\n');
    harness.feed('\x1b]3008;start=abc;cwd=/home/user\x1b\\');
    harness.feed('\x1bP1000p%begin 1 312 0\n%end 1 312 0\n');
    await pumpEventQueue();
    expect(harness.written, 'list-windows\n');
    harness.feed('%begin 1 313 0\n@0\t0\tzsh\t1\n%end 1 313 0\n');
    expect((await windows).lines, ['@0\t0\tzsh\t1']);
    await harness.dispose();
  });

  test(
    'a command waits for the intro instead of being written early',
    () async {
      // Everything sent before tmux reaches control mode can be flushed by the
      // tty initialisation, so the client holds it rather than trusting the
      // write. This is checked by asserting the sink saw nothing yet.
      final harness = _Harness();
      final pending = harness.client.command('list-windows');
      await pumpEventQueue();
      expect(harness.written, isEmpty);
      harness.greeting();
      await pumpEventQueue();
      expect(harness.written, 'list-windows\n');
      harness.feed('%begin 1 313 0\nok\n%end 1 313 0\n');
      expect((await pending).lines, ['ok']);
      await harness.dispose();
    },
  );

  test('the DCS framing is stripped once and at the end', () async {
    final harness = _Harness();
    final pending = harness.client.command('list-sessions');
    harness.greeting();
    harness.feed('%begin 1 315 0\n');
    harness.feed('line\n%end 1 315 0\n\x1b');
    harness.feedBytes([0x5c]);
    final block = await pending;
    expect(block.lines, ['line']);
    expect(harness.events.whereType<TmuxExitEvent>(), isEmpty);
    await harness.dispose();
  });

  test('%output decodes octal and backslash escapes to bytes', () async {
    final harness = _Harness();
    harness.feed('%output %0 foo\\015\\012\\033[31mred\\033[0m\n');
    await pumpEventQueue();
    final output = harness.events.whereType<TmuxOutputEvent>().single;
    expect(output.paneId, '%0');
    expect(output.bytes, [
      0x66, 0x6f, 0x6f, 0x0d, 0x0a, //
      0x1b, 0x5b, 0x33, 0x31, 0x6d,
      0x72, 0x65, 0x64,
      0x1b, 0x5b, 0x30, 0x6d,
    ]);
    await harness.dispose();
  });

  test('non-ASCII output keeps its UTF-8 bytes intact', () async {
    // A braille spinner reaches control mode as plain UTF-8 text, so the
    // decoder has to encode it back to the same bytes. Copying code units
    // instead truncates every non-ASCII glyph to its low byte, which turned
    // docker compose's spinner and progress bars into control characters.
    final harness = _Harness();
    harness.feed('%output %0 \u280b Building\u2809\n');
    await pumpEventQueue();
    final output = harness.events.whereType<TmuxOutputEvent>().single;
    expect(
      utf8.decode(output.bytes),
      '\u280b Building\u2809',
      reason: 'the spinner has to arrive as text, not as stray control bytes',
    );
    expect(output.bytes, utf8.encode('\u280b Building\u2809'));
    await harness.dispose();
  });

  test('octal escapes and literal text coexist', () async {
    // The escape still means a raw byte; the text around it keeps its own
    // encoding.
    final harness = _Harness();
    harness.feed('%output %0 \u2500\\033[31mred\u2500\n');
    await pumpEventQueue();
    final output = harness.events.whereType<TmuxOutputEvent>().single;
    expect(output.bytes, [
      ...utf8.encode('\u2500'),
      0x1b,
      ...utf8.encode('[31mred\u2500'),
    ]);
    await harness.dispose();
  });

  test('%extended-output keeps the payload after the colon', () async {
    final harness = _Harness();
    harness.feed('%extended-output %3 0 0 : hi\\012\n');
    await pumpEventQueue();
    final output = harness.events.whereType<TmuxOutputEvent>().single;
    expect(output.paneId, '%3');
    expect(output.bytes, [0x68, 0x69, 0x0a]);
    await harness.dispose();
  });

  test('%layout-change parses the v2 JSON layout', () async {
    final harness = _Harness();
    const layout = '{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%2"}}';
    harness.feed('%layout-change @1 $layout *\n');
    await pumpEventQueue();
    final event = harness.events.whereType<TmuxLayoutEvent>().single;
    expect(event.windowId, '@1');
    expect(event.layout, layout);
    await harness.dispose();
  });

  test('an unknown notification is dropped without throwing', () async {
    final harness = _Harness();
    harness.feed('%wat something\n%output %0 ok\n');
    await pumpEventQueue();
    expect(harness.events, hasLength(1));
    expect(harness.events.single, isA<TmuxOutputEvent>());
    await harness.dispose();
  });

  test('sendKeys hex-encodes and chunks the input', () async {
    final harness = _Harness();
    harness.greeting();
    await pumpEventQueue();
    harness.client.sendKeys('%0', [0x03]);
    expect(harness.written, 'send-keys -H -t %0 03\n');
    harness.writes.clear();
    harness.client.sendKeys('%0', List<int>.filled(300, 0x0a));
    await pumpEventQueue();
    final lines = harness.written.trimRight().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('send-keys -H -t %0 0A 0A'));
    await harness.dispose();
  });

  test('resizeClient reports the client size', () async {
    final harness = _Harness();
    harness.greeting();
    await pumpEventQueue();
    harness.client.resizeClient(120, 36);
    expect(harness.written, 'refresh-client -C 120x36\n');
    await harness.dispose();
  });

  test('a command rejects a newline', () async {
    final harness = _Harness();
    expect(() => harness.client.command('list\nsessions'), throwsArgumentError);
    await harness.dispose();
  });

  test('a stream that closes without %exit reports a lost transport', () async {
    // A dropped SSH connection looks exactly like this: the channel closes and
    // tmux never says the session ended. The session is still on the host, so
    // the event must not claim it ended - that is what made a running task look
    // finished and closed its tab.
    final harness = _Harness();
    harness.greeting();
    await pumpEventQueue();
    await harness.end();
    await pumpEventQueue();
    final exit = harness.events.whereType<TmuxExitEvent>().single;
    expect(exit.transportLost, isTrue);
    expect(exit.sessionEnded, isFalse);
    await harness.eventsSubscription.cancel();
  });

  test('%exit before the stream closes reports an ended session', () async {
    final harness = _Harness();
    harness.greeting();
    harness.feed('%exit session destroyed\n');
    await pumpEventQueue();
    await harness.end();
    await pumpEventQueue();
    final exits = harness.events.whereType<TmuxExitEvent>();
    expect(exits.any((event) => event.sessionEnded), isTrue);
    await harness.eventsSubscription.cancel();
  });

  test('closing the stream fails a pending command', () async {
    final harness = _Harness();
    final pending = harness.client.command('list-sessions');
    await harness.end();
    await expectLater(pending, throwsStateError);
    await pumpEventQueue();
    expect(harness.events.whereType<TmuxExitEvent>(), hasLength(1));
    expect(harness.closed, hasLength(1));
    await harness.eventsSubscription.cancel();
  });
}
