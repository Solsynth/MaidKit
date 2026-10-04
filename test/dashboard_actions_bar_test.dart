import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/dashboard_actions_bar.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required double width,
    bool isArranging = false,
    bool canArrange = true,
    bool isSearching = false,
    VoidCallback? onToggleArrange,
    VoidCallback? onToggleSearch,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DashboardActionsBar(
                  isArranging: isArranging,
                  canArrange: canArrange,
                  onToggleArrange: onToggleArrange ?? () {},
                  isSearching: isSearching,
                  onToggleSearch: onToggleSearch ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The bar used to be a fixed [Row], which overflowed once the pane holding
  /// the dashboard was narrower than its labelled buttons.
  testWidgets('reflows instead of overflowing in a narrow pane', (
    tester,
  ) async {
    for (final width in [160.0, 240.0, 280.0, 340.0, 420.0]) {
      await pumpBar(tester, width: width);

      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(
        find.text('serversArrange'.tr()),
        findsOneWidget,
        reason: 'width $width',
      );
      expect(
        find.text('serversSearch'.tr()),
        findsOneWidget,
        reason: 'width $width',
      );
    }
  });

  testWidgets('reports the toggle taps', (tester) async {
    var arrangeTaps = 0;
    var searchTaps = 0;
    await pumpBar(
      tester,
      width: 640,
      onToggleArrange: () => arrangeTaps++,
      onToggleSearch: () => searchTaps++,
    );

    await tester.tap(find.text('serversArrange'.tr()));
    await tester.tap(find.text('serversSearch'.tr()));
    expect(arrangeTaps, 1);
    expect(searchTaps, 1);
  });

  testWidgets('names the engaged states and disables a lone server', (
    tester,
  ) async {
    var arrangeTaps = 0;
    await pumpBar(
      tester,
      width: 640,
      isArranging: true,
      canArrange: false,
      isSearching: true,
      onToggleArrange: () => arrangeTaps++,
    );

    expect(find.text('serversDoneArranging'.tr()), findsOneWidget);
    expect(find.text('serversHideSearch'.tr()), findsOneWidget);

    await tester.tap(find.text('serversDoneArranging'.tr()));
    expect(arrangeTaps, 0);
  });
}
