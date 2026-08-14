import 'package:flutter/material.dart' as flutter;
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/shared/presentation/maidkit_window_scaffold.dart';
import 'package:maid_kit/theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('bridges the app theme to the Island window frame', (
    tester,
  ) async {
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
}
