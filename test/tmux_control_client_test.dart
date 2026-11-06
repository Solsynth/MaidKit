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
    final pending = harness.client.command('list-sessions');
    harness.feed('\x1bP1000p%begin 1 1 0\nhello\n%end 1 1 0\n');
    final block = await pending;
    expect(block.number, 1);
    expect(block.lines, ['hello']);
    expect(block.error, isFalse);
    expect(harness.written, 'list-sessions\n');
    await harness.dispose();
  });

  test('the DCS framing is stripped once and at the end', () async {
    final harness = _Harness();
    final pending = harness.client.command('list-sessions');
    harness.feed('\x1bP1000p%begin 1 2 0\n');
    harness.feed('line\n%end 1 2 0\n\x1b');
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
    harness.client.resizeClient(120, 36);
    expect(harness.written, 'refresh-client -C 120x36\n');
    await harness.dispose();
  });

  test('a command rejects a newline', () async {
    final harness = _Harness();
    expect(() => harness.client.command('list\nsessions'), throwsArgumentError);
    await harness.dispose();
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
