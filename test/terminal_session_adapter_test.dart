import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:maid_kit/servers/maidterm_session_adapter.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_adapter_preferences.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

void main() {
  test('persists separate light and dark terminal themes', () async {
    final settings = InMemoryTerminalAdapterSettings(
      lightTheme: TerminalColorSchemes.catppuccinLatte,
      darkTheme: TerminalColorSchemes.nord,
    );
    final container = ProviderContainer(
      overrides: [
        terminalAdapterPreferencesProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(terminalLightThemeProvider),
      TerminalColorSchemes.catppuccinLatte,
    );
    expect(
      container.read(terminalDarkThemeProvider),
      TerminalColorSchemes.nord,
    );

    await container
        .read(terminalDarkThemeProvider.notifier)
        .save(TerminalColorSchemes.dracula);

    expect(
      container.read(terminalDarkThemeProvider),
      TerminalColorSchemes.dracula,
    );
    expect(settings.darkTheme, TerminalColorSchemes.dracula);
  });

  test('resolves the terminal palette from the app brightness', () async {
    final settings = InMemoryTerminalAdapterSettings(
      lightTheme: TerminalColorSchemes.catppuccinLatte,
      darkTheme: TerminalColorSchemes.nord,
    );
    final container = ProviderContainer(
      overrides: [
        terminalAdapterPreferencesProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);
    expect(
      container.read(terminalColorSchemeProvider),
      TerminalColorSchemes.catppuccinLatte,
    );

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    expect(
      container.read(terminalColorSchemeProvider),
      TerminalColorSchemes.nord,
    );
  });

  test('persists the terminal branding environment preference', () async {
    final settings = InMemoryTerminalAdapterSettings();
    final container = ProviderContainer(
      overrides: [
        terminalAdapterPreferencesProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(terminalBrandingEnvironmentEnabledProvider), isTrue);

    await container
        .read(terminalBrandingEnvironmentEnabledProvider.notifier)
        .setEnabled(false);

    expect(container.read(terminalBrandingEnvironmentEnabledProvider), isFalse);
    expect(settings.brandingEnvironmentEnabled, isFalse);
  });

  test('persists the terminal font family', () async {
    final settings = InMemoryTerminalAdapterSettings();
    final container = ProviderContainer(
      overrides: [
        terminalAdapterPreferencesProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(terminalFontFamilyProvider),
      TerminalFonts.defaultFamily,
    );

    await container
        .read(terminalFontFamilyProvider.notifier)
        .setFontFamily('Fira Code');

    expect(container.read(terminalFontFamilyProvider), 'Fira Code');
    expect(settings.terminalFontFamily, 'Fira Code');
  });

  test('dedupes font variants into a single regular entry per family', () {
    final options = TerminalFonts.dedupe(const [
      'SFMono-Regular',
      'SFMono-Bold',
      'SFMono-Light',
      'Menlo',
      'JetBrainsMono-Regular',
      'JetBrainsMono-BoldItalic',
      'JetBrainsMono-Medium',
      'AndaleMono',
    ]);

    final byLabel = {for (final option in options) option.label: option};
    expect(byLabel['SFMono']?.family, 'SFMono-Regular');
    expect(byLabel['JetBrainsMono']?.family, 'JetBrainsMono-Regular');
    expect(byLabel['Menlo']?.family, 'Menlo');
    expect(byLabel['AndaleMono']?.family, 'AndaleMono');
    expect(options, hasLength(4));
  });

  test('strips only the trailing variant from multi-dash family names', () {
    final options = TerminalFonts.dedupe(const [
      'MapleMono-NF-CN-Regular',
      'MapleMono-NF-CN-ExtraLight',
      'MapleMono-NF-CN-ExtraLightItalic',
      'MapleMono-NF-CN-Bold',
      'MapleMono-NF-Regular',
      'MapleMono-NF-Bold',
    ]);

    final byLabel = {for (final option in options) option.label: option};
    expect(byLabel['MapleMono-NF-CN']?.family, 'MapleMono-NF-CN-Regular');
    expect(byLabel['MapleMono-NF']?.family, 'MapleMono-NF-Regular');
    expect(options, hasLength(2));
  });

  test('collapses compound and width/style variants', () {
    final options = TerminalFonts.dedupe(const [
      'FiraCodeNerdFont-Regular',
      'FiraCodeNerdFont-Retina',
      'CaskaydiaMonoNerdFont-Regular',
      'CaskaydiaMonoNerdFont-SemiLight',
      'CaskaydiaMonoNerdFont-SemiLightItalic',
      'MartianMonoNerdFont-Regular',
      'MartianMonoNerdFont-CondensedBold',
      'MartianMonoNerdFont-CondensedRegular',
      'BlexMonoNerdFont-Regular',
      'BlexMonoNerdFont-Text',
      'BlexMonoNerdFont-TextItalic',
      'BlexMonoNerdFont-ExtraLightItalic',
    ]);

    final byLabel = {for (final option in options) option.label: option};
    expect(byLabel['FiraCodeNerdFont']?.family, 'FiraCodeNerdFont-Regular');
    expect(
      byLabel['CaskaydiaMonoNerdFont']?.family,
      'CaskaydiaMonoNerdFont-Regular',
    );
    expect(
      byLabel['MartianMonoNerdFont']?.family,
      'MartianMonoNerdFont-Regular',
    );
    expect(byLabel['BlexMonoNerdFont']?.family, 'BlexMonoNerdFont-Regular');
    expect(options, hasLength(4));
  });

  test('prefers a plain family file when no regular variant exists', () {
    final options = TerminalFonts.dedupe(const [
      'CascadiaCode-Bold',
      'CascadiaCode-Black',
    ]);
    expect(options, hasLength(1));
    expect(options.single.label, 'CascadiaCode');
    expect(options.single.family, 'CascadiaCode-Black');
  });

  test('applies the selected palette to the terminal renderer', () async {
    final scheme = TerminalColorSchemes.catppuccinMocha;
    final adapter = MaidTermSessionAdapter(colorScheme: scheme);
    addTearDown(adapter.dispose);

    final menuView = adapter.buildView() as AppContextMenuRegion;
    final view = menuView.child as maidterm.TerminalView;
    expect(view.theme!.background, scheme.background);
    expect(view.theme!.foreground, scheme.foreground);
    expect(view.theme!.cursorMotionDuration, const Duration(milliseconds: 90));
  });
  test('tracks the shell directory reported through OSC 7', () async {
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);

    adapter.write(
      Uint8List.fromList(
        utf8.encode('\x1b]7;file:///tmp/project%20folder\x07'),
      ),
    );

    expect(adapter.currentDirectory, '/tmp/project folder');
  });

  test('terminal context menu exposes file management', () {
    var opened = false;
    final menu = terminalContextMenu(
      hasSelection: false,
      canPaste: true,
      onCopy: () {},
      onPaste: () {},
      onSelectAll: () {},
      onOpenFileManagement: () => opened = true,
    );

    final action = menu.children.whereType<MenuAction>().last;
    action.callback();
    expect(opened, isTrue);
  });

  test('Ghostty adapter encodes cursor keys for the remote shell', () async {
    final adapter = MaidTermSessionAdapter();
    final output = adapter.outgoingBytes.first;

    adapter.sendKey(maidterm.Key.arrowUp);

    expect(utf8.decode(await output), '\u001b[A');
    await adapter.dispose();
  });

  test('Ghostty adapter encodes backspace for the remote shell', () async {
    final adapter = MaidTermSessionAdapter();
    final output = adapter.outgoingBytes.first;

    adapter.sendKey(maidterm.Key.backspace);

    expect(utf8.decode(await output), '\u007f');
    await adapter.dispose();
  });

  testWidgets(
    'Ghostty adapter renders with MaidTerm and reports its grid size',
    (tester) async {
      final adapter = MaidTermSessionAdapter();
      final resizes = <TerminalResize>[];
      final subscription = adapter.resizeEvents.listen(resizes.add);
      addTearDown(subscription.cancel);
      addTearDown(adapter.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 800, height: 600, child: adapter.buildView()),
        ),
      );
      await tester.pump();

      expect(find.byType(maidterm.TerminalView), findsOneWidget);
      expect(resizes, isNotEmpty);
      expect(resizes.last.columns, greaterThan(0));
      expect(resizes.last.rows, greaterThan(0));
      expect(adapter.cursorGlobalRect, isNotNull);
    },
  );

  testWidgets('resize events carry real physical pixel metrics', (
    tester,
  ) async {
    final adapter = MaidTermSessionAdapter();
    final resizes = <TerminalResize>[];
    final subscription = adapter.resizeEvents.listen(resizes.add);
    addTearDown(subscription.cancel);
    addTearDown(adapter.dispose);

    Future<void> pumpAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: size.width,
            height: size.height,
            child: adapter.buildView(),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAt(const Size(800, 600));
    expect(resizes, isNotEmpty);
    final large = resizes.last;
    // Real cell metrics times the device pixel ratio must exceed the
    // legacy columns*8 / rows*18 logical-pixel estimates.
    expect(large.pixelWidth, greaterThan(large.columns * 8));
    expect(large.pixelHeight, greaterThan(large.rows * 18));
    expect(large.pixelWidth, greaterThan(0));
    expect(large.pixelHeight, greaterThan(0));

    await pumpAt(const Size(400, 300));
    expect(resizes.length, greaterThanOrEqualTo(2));
    final small = resizes.last;
    expect(small.columns, lessThanOrEqualTo(large.columns));
    expect(small.rows, lessThanOrEqualTo(large.rows));
    expect(small.pixelWidth, lessThan(large.pixelWidth));
    expect(small.pixelHeight, lessThan(large.pixelHeight));

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('terminal key callback preempts shell input shortcuts', (
    tester,
  ) async {
    final adapter = MaidTermSessionAdapter();
    var shortcutCalls = 0;
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: adapter.buildView(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent ||
                  event.logicalKey != LogicalKeyboardKey.equal) {
                return KeyEventResult.ignored;
              }
              shortcutCalls++;
              return KeyEventResult.handled;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(maidterm.TerminalView));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(shortcutCalls, 1);
  });

  testWidgets('read-only ghostty view copies the selection with Cmd+C', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );

      final adapter = MaidTermSessionAdapter();
      addTearDown(adapter.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: adapter.buildView(readOnly: true, showCursor: false),
          ),
        ),
      );
      await tester.pump();

      adapter.write(Uint8List.fromList(utf8.encode('hello world\r\n')));

      // Clicking the read-only surface must focus it.
      await tester.tap(find.byType(maidterm.TerminalView));
      await tester.pump();

      // Select the log text through the public find API.
      expect(adapter.find('hello world'), 1);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(copied, ['hello world']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('read-only ghostty view blocks typing from mutating the log', (
    tester,
  ) async {
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: adapter.buildView(readOnly: true, showCursor: false),
        ),
      ),
    );
    await tester.pump();

    adapter.write(Uint8List.fromList(utf8.encode('original line\r\n')));

    await tester.tap(find.byType(maidterm.TerminalView));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();

    // Typing must not reach the log buffer.
    expect(adapter.find('original line'), 1);
    expect(adapter.find('z'), 0);
  });

  test('Ghostty adapter sends terminal control sequences', () async {
    final adapter = MaidTermSessionAdapter();
    final output = adapter.outgoingBytes.first;

    adapter.sendInput('\u0003\t\u001b');

    expect(utf8.decode(await output), '\u0003\t\u001b');
    await adapter.dispose();
  });

  test('OSC 52 synchronizes split TUI clipboard sequences', () async {
    String? clipboard;
    final responses = <String>[];
    final bridge = TerminalClipboardBridge(
      setClipboard: (text) async => clipboard = text,
      getClipboard: () async => clipboard,
      sendResponse: responses.add,
    );
    addTearDown(bridge.dispose);

    final encoded = base64.encode(utf8.encode('copied from a TUI app'));
    final sequence = Uint8List.fromList(
      utf8.encode('\x1b]52;c;$encoded\x1b\\'),
    );
    bridge.add(sequence.sublist(0, 7));
    bridge.add(sequence.sublist(7));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, 'copied from a TUI app');
    expect(responses, isEmpty);
  });

  test('OSC 52 unwraps tmux passthrough sequences', () async {
    String? clipboard;
    final bridge = TerminalClipboardBridge(
      setClipboard: (text) async => clipboard = text,
      getClipboard: () async => null,
      sendResponse: (_) {},
    );
    addTearDown(bridge.dispose);

    final encoded = base64.encode(utf8.encode('copied through tmux'));
    final inner = '\x1b]52;c;$encoded\x07';
    final wrapped = '\x1bPtmux;${inner.replaceAll('\x1b', '\x1b\x1b')}\x1b\\';
    bridge.add(Uint8List.fromList(utf8.encode(wrapped)));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, 'copied through tmux');
  });

  test('OSC 52 accepts an omitted selection', () async {
    String? clipboard;
    final bridge = TerminalClipboardBridge(
      setClipboard: (text) async => clipboard = text,
      getClipboard: () async => null,
      sendResponse: (_) {},
    );
    addTearDown(bridge.dispose);

    final encoded = base64.encode(utf8.encode('clipboard'));
    bridge.add(Uint8List.fromList(utf8.encode('\x1b]52;;$encoded\x07')));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, 'clipboard');
  });

  test('OSC 52 accepts unpadded base64 payloads', () async {
    String? clipboard;
    final bridge = TerminalClipboardBridge(
      setClipboard: (text) async => clipboard = text,
      getClipboard: () async => null,
      sendResponse: (_) {},
    );
    addTearDown(bridge.dispose);

    bridge.add(Uint8List.fromList(utf8.encode('\x1b]52;c;aGVsbG8\x07')));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, 'hello');
  });
  test('OSC 52 responds to TUI clipboard queries', () async {
    final responses = <String>[];
    final bridge = TerminalClipboardBridge(
      setClipboard: (_) async {},
      getClipboard: () async => 'host clipboard',
      sendResponse: responses.add,
    );
    addTearDown(bridge.dispose);

    bridge.add(Uint8List.fromList(utf8.encode('\x1b]52;c;?\x07')));
    await Future<void>.delayed(Duration.zero);

    final encoded = base64.encode(utf8.encode('host clipboard'));
    expect(responses, ['\x1b]52;c;$encoded\x1b\\']);
  });

  test('terminal adapter synchronizes OSC 52 with host clipboard', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final copied = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, String>{'text': 'host clipboard'};
      }
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final adapter = MaidTermSessionAdapter();
    final output = adapter.outgoingBytes.first;
    adapter.write(Uint8List.fromList(utf8.encode('\x1b]52;c;?\x07')));
    expect(utf8.decode(await output), '\x1b]52;c;aG9zdCBjbGlwYm9hcmQ=\x1b\\');

    adapter.write(
      Uint8List.fromList(
        utf8.encode('\x1b]52;c;${base64.encode(utf8.encode('from TUI'))}\x07'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(copied, ['from TUI']);
    await adapter.dispose();
  });

  test('terminal activity follows shell integration markers', () async {
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);
    final states = <bool>[];
    final subscription = adapter.taskRunning.listen(states.add);
    addTearDown(subscription.cancel);

    adapter.write(Uint8List.fromList(utf8.encode('\x1b]133;C\x07')));
    adapter.write(Uint8List.fromList(utf8.encode('\x1b]133;D;0\x07')));
    await Future<void>.delayed(Duration.zero);

    expect(states, [true, false]);
    expect(adapter.isTaskRunning, isFalse);
  });

  test('terminal activity exposes reported progress percentages', () async {
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);
    final activities = <TerminalTaskActivity>[];
    final subscription = adapter.taskActivity.listen(activities.add);
    addTearDown(subscription.cancel);

    adapter.write(Uint8List.fromList(utf8.encode('\x1b]9;4;1;42\x07')));
    await Future<void>.delayed(Duration.zero);

    expect(adapter.currentTaskActivity.running, isTrue);
    expect(adapter.currentTaskActivity.progress, 0.42);
    expect(activities.last.progress, 0.42);
  });

  test('forwards shell output, terminal input, and resize events', () async {
    final stdout = StreamController<Uint8List>();
    final stderr = StreamController<Uint8List>();
    final adapter = _FakeTerminalSessionAdapter();
    final sent = <Uint8List>[];
    final resizes = <TerminalResize>[];
    final binding = TerminalSessionBinding(
      adapter: adapter,
      stdout: stdout.stream,
      stderr: stderr.stream,
      send: sent.add,
      resize: resizes.add,
    );

    stdout.add(Uint8List.fromList([1, 2]));
    stderr.add(Uint8List.fromList([3]));
    adapter.emitInput(Uint8List.fromList([4]));
    const resize = TerminalResize(
      columns: 120,
      rows: 36,
      pixelWidth: 960,
      pixelHeight: 720,
    );
    adapter.emitResize(resize);
    await Future<void>.delayed(const Duration(milliseconds: 12));

    expect(adapter.received, [
      Uint8List.fromList([1, 2, 3]),
    ]);
    expect(sent, [
      Uint8List.fromList([4]),
    ]);
    expect(resizes, [resize]);

    await binding.close();
    expect(adapter.disposed, isTrue);
    await stdout.close();
    await stderr.close();
  });

  test(
    'closing a shell binding stops forwarding and disposes the adapter',
    () async {
      final stdout = StreamController<Uint8List>();
      final stderr = StreamController<Uint8List>();
      final adapter = _FakeTerminalSessionAdapter();
      var sent = 0;
      final binding = TerminalSessionBinding(
        adapter: adapter,
        stdout: stdout.stream,
        stderr: stderr.stream,
        send: (_) => sent++,
        resize: (_) {},
      );

      await binding.close();
      stdout.add(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);

      expect(adapter.received, isEmpty);
      expect(sent, 0);
      expect(adapter.disposed, isTrue);
      await stdout.close();
      await stderr.close();
    },
  );
  test('surfaces remote OSC 9 notifications as system notifications', () async {
    final shown = await _mockNotificationChannels(focused: false);
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);

    // OSC 9 carries no title; the adapter falls back to the app name.
    adapter.write(Uint8List.fromList(utf8.encode('\x1b]9;build done\x07')));
    await pumpEventQueue();

    expect(shown, hasLength(1));
    expect(shown.single.toString(), contains('MaidKit'));
    expect(shown.single.toString(), contains('build done'));
  });

  test('suppresses remote notifications while the window is focused', () async {
    final shown = await _mockNotificationChannels(focused: true);
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);

    adapter.write(Uint8List.fromList(utf8.encode('\x1b]9;build done\x07')));
    await pumpEventQueue();

    expect(shown, isEmpty);
  });

  test('forwards OSC 777 and chunked OSC 99 notification payloads', () async {
    final shown = await _mockNotificationChannels(focused: false);
    final adapter = MaidTermSessionAdapter();
    addTearDown(adapter.dispose);

    adapter.write(
      Uint8List.fromList(utf8.encode('\x1b]777;notify;Deploy;all green\x07')),
    );
    await pumpEventQueue();

    // Chunked kitty OSC 99: d=0 opens the title, the body chunk completes it.
    adapter.write(Uint8List.fromList(utf8.encode('\x1b]99;i=7:d=0;Build\x1b\\')));
    adapter.write(
      Uint8List.fromList(utf8.encode('\x1b]99;i=7:p=body;passed\x1b\\')),
    );
    await pumpEventQueue();

    expect(shown, hasLength(2));
    expect(shown.first.toString(), contains('Deploy'));
    expect(shown.first.toString(), contains('all green'));
    expect(shown.last.toString(), contains('Build'));
    expect(shown.last.toString(), contains('passed'));
  });
}

/// Mocks the window-manager focus probe and the local-notification channel,
/// returning the captured `show` payloads.
Future<List<Object?>> _mockNotificationChannels({required bool focused}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);

  const windowManagerChannel = MethodChannel('window_manager');
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  // Production code registers this via the plugin's generated plugin class;
  // tests have no plugin registry and must register manually.
  MacOSFlutterLocalNotificationsPlugin.registerWith();
  final shown = <Object?>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
    if (call.method == 'isFocused') return focused;
    return null;
  });
  messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'show':
        shown.add(call.arguments);
        return null;
      default:
        return null;
    }
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });
  return shown;
}

class _FakeTerminalSessionAdapter implements TerminalSessionAdapter {
  final received = <Uint8List>[];
  final _outgoing = StreamController<Uint8List>.broadcast();
  final _resizes = StreamController<TerminalResize>.broadcast();
  var disposed = false;

  @override
  Stream<Uint8List> get outgoingBytes => _outgoing.stream;

  @override
  Stream<TerminalResize> get resizeEvents => _resizes.stream;

  @override
  bool get isTaskRunning => false;

  @override
  Stream<bool> get taskRunning => const Stream.empty();

  @override
  Stream<TerminalTaskActivity> get taskActivity => const Stream.empty();

  @override
  TerminalTaskActivity get currentTaskActivity =>
      const TerminalTaskActivity(running: false);
  @override
  String? get currentDirectory => null;

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _outgoing.close();
    await _resizes.close();
  }

  void emitInput(Uint8List bytes) => _outgoing.add(bytes);

  void emitResize(TerminalResize resize) => _resizes.add(resize);

  @override
  void write(Uint8List bytes) => received.add(bytes);

  @override
  void sendInput(String text) =>
      _outgoing.add(Uint8List.fromList(utf8.encode(text)));

  @override
  void showKeyboard() {}

  @override
  void hideKeyboard() {}
  @override
  Rect? get cursorGlobalRect => null;
}
