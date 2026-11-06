import 'package:maidterm/maidterm.dart' as maidterm;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/app_theme_preferences.dart';
import 'package:maid_kit/servers/maidterm_session_adapter.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_adapter_preferences.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_find_host.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';

void main() {
  Widget buildApp({required bool transparent}) {
    return ProviderScope(
      overrides: [
        appThemeSettingsProvider.overrideWithValue(
          InMemoryAppThemeSettings(themeMode: ThemeMode.light),
        ),
        terminalAdapterPreferencesProvider.overrideWithValue(
          InMemoryTerminalAdapterSettings(),
        ),
        terminalSessionAdapterFactoryProvider.overrideWithValue(
          const TerminalRendererFactory(
            cursorAnimationEnabled: false,
            colorScheme: TerminalColorSchemes.defaultLightScheme,
          ),
        ),
        transparentTerminalBackgroundProvider.overrideWithValue(transparent),
      ],
      child: MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: AnsiLogView(text: 'line one\nline two'),
        ),
      ),
    );
  }

  testWidgets('AnsiLogView backdrop follows the transparent terminal setting', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(transparent: true));
    await tester.pump(); // bind the adapter after the first frame
    await tester.pump(); // render the terminal view

    final host = find.byType(TerminalFindHost);
    expect(host, findsOneWidget);

    final backdropColors = tester
        .widgetList<ColoredBox>(
          find.ancestor(of: host, matching: find.byType(ColoredBox)),
        )
        .map((box) => box.color)
        .toList();
    expect(backdropColors, contains(Colors.transparent));

    final view = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(view.theme!.backgroundOpacity, 0);
  });

  testWidgets('AnsiLogView keeps an opaque slab in the terminal palette', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(transparent: false));
    await tester.pump();
    await tester.pump();

    final host = find.byType(TerminalFindHost);
    final backdropColors = tester
        .widgetList<ColoredBox>(
          find.ancestor(of: host, matching: find.byType(ColoredBox)),
        )
        .map((box) => box.color)
        .toList();
    // The slab sits behind the renderer, so it has to be the palette's own
    // background: a fixed dark slab would frame a light terminal in black.
    expect(
      backdropColors,
      contains(TerminalColorSchemes.defaultLightScheme.background),
    );

    final view = tester.widget<maidterm.TerminalView>(
      find.byType(maidterm.TerminalView),
    );
    expect(view.theme!.backgroundOpacity, 1);
  });

  testWidgets('AnsiLogView repaints in the palette for the new brightness', (
    tester,
  ) async {
    // The adapter — and with it the palette it captured at creation — lives
    // as long as the log pane. A brightness switch must still repaint the
    // already-mounted renderer instead of waiting for a restart.
    final container = ProviderContainer(
      overrides: [
        appThemeSettingsProvider.overrideWithValue(
          InMemoryAppThemeSettings(themeMode: ThemeMode.dark),
        ),
        terminalAdapterPreferencesProvider.overrideWithValue(
          InMemoryTerminalAdapterSettings(),
        ),
        terminalSessionAdapterFactoryProvider.overrideWithValue(
          const TerminalRendererFactory(
            cursorAnimationEnabled: false,
            colorScheme: TerminalColorSchemes.defaultScheme,
          ),
        ),
        transparentTerminalBackgroundProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: AnsiLogView(text: 'line one'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    maidterm.TerminalTheme renderedTheme() => tester
        .widget<maidterm.TerminalView>(find.byType(maidterm.TerminalView))
        .theme!;

    expect(
      renderedTheme().background,
      TerminalColorSchemes.defaultScheme.background,
    );

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pump();
    await tester.pump();

    expect(
      renderedTheme().background,
      TerminalColorSchemes.defaultLightScheme.background,
    );
  });
}
