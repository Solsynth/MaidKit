import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:xterm/xterm.dart' as xterm;
import 'package:flterm/flterm.dart' as flterm;
import 'package:maid_kit/servers/ghostty_terminal_session_adapter.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_adapter_preferences.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

void main() {
  test(
    'persists the selected terminal adapter through the settings store',
    () async {
      final settings = InMemoryTerminalAdapterSettings();
      final container = ProviderContainer(
        overrides: [
          terminalAdapterPreferencesProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(selectedTerminalSessionAdapterProvider), 'ghostty');

      await container
          .read(selectedTerminalSessionAdapterProvider.notifier)
          .select('xterm');

      expect(container.read(selectedTerminalSessionAdapterProvider), 'xterm');
      expect(settings.selectedAdapterId, 'xterm');
    },
  );

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

    container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
    expect(
      container.read(terminalColorSchemeProvider),
      TerminalColorSchemes.catppuccinLatte,
    );

    container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
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

  test('applies the selected palette to both terminal renderers', () async {
    final scheme = TerminalColorSchemes.catppuccinMocha;
    final xtermAdapter = XtermTerminalSessionAdapter(colorScheme: scheme);
    final ghostty = GhosttyTerminalSessionAdapter(colorScheme: scheme);
    addTearDown(xtermAdapter.dispose);
    addTearDown(ghostty.dispose);

    final xtermMenuView = xtermAdapter.buildView() as AppContextMenuRegion;
    final xtermView = xtermMenuView.child as KeyedSubtree;
    expect(
      (xtermView.child as xterm.TerminalView).theme.background,
      scheme.background,
    );

    final ghosttyMenuView = ghostty.buildView() as AppContextMenuRegion;
    final ghosttyView = ghosttyMenuView.child as flterm.TerminalView;
    expect(ghosttyView.theme!.background, scheme.background);
    expect(ghosttyView.theme!.foreground, scheme.foreground);
    expect(
      ghosttyView.theme!.cursorMotionDuration,
      const Duration(milliseconds: 90),
    );
  });
  test('tracks the shell directory reported through OSC 7', () async {
    final adapter = GhosttyTerminalSessionAdapter();
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
    final adapter = GhosttyTerminalSessionAdapter();
    final output = adapter.outgoingBytes.first;

    adapter.sendKey(flterm.Key.arrowUp);

    expect(utf8.decode(await output), '\u001b[A');
    await adapter.dispose();
  });

  test('Ghostty adapter encodes backspace for the remote shell', () async {
    final adapter = GhosttyTerminalSessionAdapter();
    final output = adapter.outgoingBytes.first;

    adapter.sendKey(flterm.Key.backspace);

    expect(utf8.decode(await output), '\u007f');
    await adapter.dispose();
  });

  testWidgets('Ghostty adapter renders with flterm and reports its grid size', (
    tester,
  ) async {
    final adapter = GhosttyTerminalSessionAdapter();
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

    expect(find.byType(flterm.TerminalView), findsOneWidget);
    expect(resizes, isNotEmpty);
    expect(resizes.last.columns, greaterThan(0));
    expect(resizes.last.rows, greaterThan(0));
    expect(adapter.cursorGlobalRect, isNotNull);
  });

  testWidgets('terminal key callback preempts shell input shortcuts', (
    tester,
  ) async {
    final adapter = GhosttyTerminalSessionAdapter();
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
    await tester.tap(find.byType(flterm.TerminalView));
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

      final adapter = GhosttyTerminalSessionAdapter();
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
      await tester.tap(find.byType(flterm.TerminalView));
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
    final adapter = GhosttyTerminalSessionAdapter();
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

    await tester.tap(find.byType(flterm.TerminalView));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();

    // Typing must not reach the log buffer.
    expect(adapter.find('original line'), 1);
    expect(adapter.find('z'), 0);
  });

  test('Ghostty adapter sends terminal control sequences', () async {
    final adapter = GhosttyTerminalSessionAdapter();
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

  test(
    'both terminal adapters synchronize OSC 52 with host clipboard',
    () async {
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
      for (final adapter in <TerminalSessionAdapter>[
        XtermTerminalSessionAdapter(
          colorScheme: TerminalColorSchemes.defaultScheme,
        ),
        GhosttyTerminalSessionAdapter(),
      ]) {
        final output = adapter.outgoingBytes.first;
        adapter.write(Uint8List.fromList(utf8.encode('\x1b]52;c;?\x07')));
        expect(
          utf8.decode(await output),
          '\x1b]52;c;aG9zdCBjbGlwYm9hcmQ=\x1b\\',
        );

        adapter.write(
          Uint8List.fromList(
            utf8.encode(
              '\x1b]52;c;${base64.encode(utf8.encode('from TUI'))}\x07',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await adapter.dispose();
      }
      expect(copied, ['from TUI', 'from TUI']);
    },
  );

  test('terminal activity follows shell integration markers', () async {
    final adapter = GhosttyTerminalSessionAdapter();
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
    final adapter = GhosttyTerminalSessionAdapter();
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
