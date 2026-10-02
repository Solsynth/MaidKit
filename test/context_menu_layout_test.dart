import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';
// The web/Android fallback menu session lives in the package internals; the
// app exercises it here so a regression is caught before it hits the browser.
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/desktop/menu_session.dart'
    as menu_session;

/// Regression test for
/// "A _RenderGroupIntrinsicWidth was mutated in _RenderLayoutBuilder.performLayout".
///
/// On web and Android super_context_menu renders context menus with Flutter
/// widgets inside `Overlay.of(context, rootOverlay: true)`. In MaidKit that
/// overlay lives under the app-wide `LayoutBuilder` inside MaidKitUiScale,
/// which rebuilds its whole subtree from inside its layout callback. Tearing
/// down an open menu while that callback runs used to abort, because the
/// package's shared `GroupIntrinsicWidthContainer` marked its remaining group
/// children from `detach()` after the container had already been detached from
/// its parent.
late BuildContext _pageContext;

Widget _app() {
  return MaterialApp(
    // Mirrors MaidKitApp: the root overlay is nested inside a LayoutBuilder.
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) => Overlay(
        initialEntries: [
          OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
        ],
      ),
    ),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            _pageContext = context;
            // A page-level LayoutBuilder, as used by the server cards.
            return LayoutBuilder(
              builder: (context, constraints) => const Text('target'),
            );
          },
        ),
      ),
    ),
  );
}

menu_session.ContextMenuSession _openMenu() {
  return menu_session.ContextMenuSession(
    context: _pageContext,
    iconTheme: const IconThemeData(),
    menu: Menu(
      children: [
        MenuAction(
          title: 'Copy',
          activator: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          callback: () {},
        ),
        MenuAction(
          title: 'Paste',
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () {},
        ),
      ],
    ),
    menuWidgetBuilder: maidKitDesktopMenuWidgetBuilder,
    onDone: (_) {},
    onInitialPointerUp: ChangeNotifier(),
    position: const Offset(100, 100),
    tapRegionGroupIds: const {},
  );
}

void main() {
  testWidgets(
    'closing a Flutter-rendered context menu does not mutate layout',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final menu = _openMenu();
      await tester.pumpAndSettle();

      // Dismissing the menu animates it out and removes the overlay entry while
      // the root LayoutBuilder rebuilds its subtree.
      menu.hide(itemSelected: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AppContextMenuRegion installs the isolated menu builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppContextMenuRegion(
          menuBuilder: () => Menu(
            children: [MenuAction(title: 'x', callback: () {})],
          ),
          child: const Text('row'),
        ),
      ),
    );

    final widget = tester.widget<ContextMenuWidget>(
      find.byType(ContextMenuWidget),
    );
    expect(
      widget.desktopMenuWidgetBuilder,
      same(maidKitDesktopMenuWidgetBuilder),
    );
  });
}
