import 'package:flterm/flterm.dart' as flterm;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/ghostty_terminal_session_adapter.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_find_host.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';

void main() {
  Widget buildApp({required bool transparent}) {
    return ProviderScope(
      overrides: [
        selectedTerminalSessionAdapterProvider.overrideWith(
          SelectedTerminalSessionAdapterNotifier.new,
        ),
        terminalSessionAdapterFactoryProvider.overrideWithValue(
          const GhosttyTerminalSessionAdapterFactory(
            cursorAnimationEnabled: false,
            colorScheme: TerminalColorSchemes.defaultScheme,
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

    final view = tester.widget<flterm.TerminalView>(
      find.byType(flterm.TerminalView),
    );
    expect(view.theme!.backgroundOpacity, 0);
  });

  testWidgets('AnsiLogView keeps the opaque slab when transparency is off', (
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
    expect(backdropColors, contains(const Color(0xFF111315)));

    final view = tester.widget<flterm.TerminalView>(
      find.byType(flterm.TerminalView),
    );
    expect(view.theme!.backgroundOpacity, 1);
  });
}
