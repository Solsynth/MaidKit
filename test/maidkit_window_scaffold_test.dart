import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:maid_kit/shared/presentation/maidkit_window_scaffold.dart';
import 'package:maid_kit/servers/vault_gate.dart';
import 'package:maid_kit/shared/presentation/window_chrome.dart';
import 'package:maid_kit/shared/presentation/task_progress.dart';
import 'package:maid_kit/theme.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  /// Pumps the shell as if it ran in a desktop window.
  Future<void> pumpDesktopShell(
    WidgetTester tester, {
    required bool vaultUnlocked,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope per pump: Riverpod keeps the first scope's overrides
        // when the same ProviderScope is rebuilt.
        key: ValueKey(vaultUnlocked),
        overrides: [
          desktopWindowProvider.overrideWithValue(true),
          vaultUnlockedProvider.overrideWith(
            () => _StubVaultUnlocked(vaultUnlocked),
          ),
        ],
        child: MaterialApp(
          theme: createMaidKitTheme(Brightness.light),
          home: const MaidKitWindowScaffold(child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('draws the title bar band on desktop regardless of the strip', (
    tester,
  ) async {
    await pumpDesktopShell(tester, vaultUnlocked: false);
    expect(
      find.byType(MaidKitTitleBar),
      findsOneWidget,
      reason: 'the locked vault has no tab strip, but still needs a drag band',
    );

    // The workspace is unlocked and has its dashboard tab, so its pane tab
    // strip is drawn below the band; the band still owns the window drag.
    await pumpDesktopShell(tester, vaultUnlocked: true);
    expect(find.byType(MaidKitTitleBar), findsOneWidget);
  });

  testWidgets('bridges the app theme to the window chrome', (tester) async {
    final appTheme = createMaidKitTheme(
      Brightness.dark,
      seedColor: const Color(0xFF2563EB),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [desktopWindowProvider.overrideWithValue(false)],
        child: MaterialApp(
          theme: appTheme,
          home: MaidKitWindowScaffold(
            child: Builder(
              builder: (context) => Column(
                children: [
                  Text(
                    'flutter:${flutter.MaterialLocalizations.of(context).okButtonLabel}',
                  ),
                  Text(
                    'material_ui:${MaterialLocalizations.of(context).okButtonLabel}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final windowFrameTheme = tester.widget<flutter.Theme>(
      find.byType(flutter.Theme),
    );
    final windowFrameColors = windowFrameTheme.data.colorScheme;
    expect(find.text('flutter:OK'), findsOneWidget);
    expect(find.text('material_ui:OK'), findsOneWidget);

    expect(windowFrameTheme.data.brightness, Brightness.dark);
    expect(windowFrameTheme.data.useMaterial3, isTrue);
    expect(
      windowFrameColors.surfaceContainer,
      appTheme.colorScheme.surfaceContainer,
    );
    expect(windowFrameColors.onSurface, appTheme.colorScheme.onSurface);
    expect(windowFrameTheme.data.iconTheme.color, appTheme.iconTheme.color);
    expect(
      windowFrameTheme.data.inputDecorationTheme.border,
      isA<flutter.OutlineInputBorder>(),
    );
    final legacyMaterial = tester.widget<flutter.Material>(
      find.byType(flutter.Material),
    );

    expect(legacyMaterial.type, flutter.MaterialType.transparency);
  });

  testWidgets('provides both Material localization types for zh-CN', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [desktopWindowProvider.overrideWithValue(false)],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            flutter_localizations.GlobalMaterialLocalizations.delegate,
          ],
          home: MaidKitWindowScaffold(
            child: Builder(
              builder: (context) => Text(
                '${flutter.MaterialLocalizations.of(context).okButtonLabel}:'
                '${MaterialLocalizations.of(context).okButtonLabel}',
                key: const ValueKey('localizations_loaded'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('localizations_loaded')), findsOneWidget);
  });

  testWidgets('task progress sheet uses SheetScaffold chrome', (tester) async {
    // Prime translations so the sheet title resolves; the asset loader never
    // completes under FakeAsync.
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );

    final container = ProviderContainer(
      overrides: [desktopWindowProvider.overrideWithValue(false)],
    );
    // The action stays pending so the task is still active while the sheet is
    // open; the teardown releases it so the container disposes cleanly.
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      container.dispose();
    });
    container
        .read(taskProgressProvider.notifier)
        .run(
          AppTaskRequest(
            title: 'Upload build.tar.gz',
            totalBytes: 10 * 1024 * 1024,
            action: (control, report) async {
              report(1024 * 1024);
              await gate.future;
            },
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: createMaidKitTheme(Brightness.light),
          home: const MaidKitWindowScaffold(child: SizedBox()),
        ),
      ),
    );

    await tester.tap(find.text('Upload build.tar.gz'));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<SheetScaffold>(find.byType(SheetScaffold));
    expect(scaffold.leading, isNull, reason: 'no icon beside the title');
    expect(scaffold.titleText, '1 active transfers');

    await tester.tap(
      find
          .descendant(
            of: find.byType(SheetScaffold),
            matching: find.byIcon(Symbols.close),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SheetScaffold), findsNothing);
  });
  testWidgets('scales the window subtree and its logical viewport', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const flutter.Size(800, 400)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var tapped = false;
    await tester.pumpWidget(
      flutter.MaterialApp(
        home: MaidKitUiScale(
          scale: 2,
          child: Builder(
            builder: (context) => flutter.Container(
              key: const flutter.ValueKey('scaled-child'),
              color: flutter.Colors.red,
              child: flutter.Stack(
                children: [
                  flutter.Align(
                    alignment: flutter.Alignment.topCenter,
                    child: flutter.Text(
                      '${flutter.MediaQuery.sizeOf(context).width}',
                    ),
                  ),
                  flutter.Positioned(
                    top: 40,
                    left: 60,
                    child: flutter.ElevatedButton(
                      onPressed: () => tapped = true,
                      child: const flutter.Text('Tap'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('200.0'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const flutter.ValueKey('scaled-child'))),
      const flutter.Size(200, 100),
    );

    await tester.tap(find.text('Tap'));
    expect(tapped, isTrue);
  });
  testWidgets('retains child state when the scale changes', (tester) async {
    var scale = 1.0;
    late void Function(VoidCallback) rebuild;

    await tester.pumpWidget(
      flutter.MaterialApp(
        home: flutter.Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MaidKitUiScale(
                scale: scale,
                child: const flutter.TextField(
                  key: flutter.ValueKey('persistent-field'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const flutter.ValueKey('persistent-field')),
      'persisted',
    );
    scale = 1.5;
    rebuild(() {});
    await tester.pumpAndSettle();

    expect(find.text('persisted'), findsOneWidget);
  });
}

class _StubVaultUnlocked extends VaultUnlocked {
  _StubVaultUnlocked(this.unlocked);

  final bool unlocked;

  @override
  bool build() => unlocked;
}
