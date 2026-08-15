import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_server_tab.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solsynth_express/solsynth_express.dart';

const _testChannels = [
  DistributionChannel(
    id: 'stable-id',
    name: 'stable',
    displayName: 'Stable',
    displayNames: {},
    description: '',
    descriptions: {},
    latest: null,
  ),
  DistributionChannel(
    id: 'beta-id',
    name: 'beta',
    displayName: 'Beta',
    displayNames: {},
    description: '',
    descriptions: {},
    latest: null,
  ),
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpInstallSheet(
    WidgetTester tester, {
    required bool updating,
    required void Function(String?) onChosen,
  }) async {
    // `.tr()` resolves to the raw key in widget tests, so button labels are
    // long; widen the surface so the sheet's action row lays out on screen.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: MaterialApp(
          localizationsDelegates: [
            ...material_ui.GlobalMaterialLocalizations.delegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    onChosen(
                      await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        constraints: const BoxConstraints(maxWidth: 1400),
                        builder: (_) => MaidCafeInstallSheet(
                          channels: _testChannels,
                          updating: updating,
                          transport: 'http',
                          scriptBuilder: (channel) async =>
                              'script-for-$channel',
                        ),
                      ),
                    );
                  },
                  child: const Text('open-sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'install sheet locks the install button until every step is reviewed',
    (WidgetTester tester) async {
      String? chosen;
      await pumpInstallSheet(
        tester,
        updating: false,
        onChosen: (v) {
          chosen = v;
        },
      );

      await tester.tap(find.text('open-sheet'));
      await tester.pumpAndSettle();

      // Step 1 (channel): Next is disabled until a channel is picked.
      final nextButton = find.widgetWithText(
        FilledButton,
        'maidCafeInstallNext'.tr(),
      );
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);

      // Picking a channel advances to step 2 (what the script does).
      await tester.tap(find.text('stable'));
      await tester.pumpAndSettle();
      expect(find.text('maidCafeInstallStepCurlTitle'.tr()), findsOneWidget);
      expect(tester.widget<FilledButton>(nextButton).onPressed, isNotNull);

      // Step 3 (script): the exact script is shown and install unlocks.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.text('script-for-stable'), findsOneWidget);
      final installButton = find.widgetWithText(
        FilledButton,
        'maidCafeInstallApplication'.tr(),
      );
      expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);

      await tester.tap(installButton);
      await tester.pumpAndSettle();
      expect(chosen, 'stable');
    },
  );

  testWidgets('update sheet needs only a channel, not the review walkthrough', (
    WidgetTester tester,
  ) async {
    String? chosen;
    await pumpInstallSheet(
      tester,
      updating: true,
      onChosen: (v) {
        chosen = v;
      },
    );

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();

    expect(find.text('maidCafeUpdateApplication'.tr()), findsOneWidget);

    await tester.tap(find.text('stable'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'maidCafeInstallNext'.tr()),
    );
    await tester.pumpAndSettle();

    final installButton = find.widgetWithText(
      FilledButton,
      'maidCafeUpdateApplication'.tr(),
    );
    expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);

    await tester.tap(installButton);
    await tester.pumpAndSettle();
    expect(chosen, 'stable');
  });

  Future<void> pumpDetailTabs(WidgetTester tester) async {
    final server = Server(
      id: 1,
      name: 'Build host',
      host: 'build.example',
      port: 22,
      username: 'builder',
      collectStats: true,
      collectSystemInfo: true,
      connectionType: 'ssh',
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'US')],
            home: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Cafe'),
                      Tab(text: 'Other'),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    MaidCafeServerTab(
                      server: server,
                      connected: false,
                      connectionError: null,
                      onConnect: () async {},
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MaidCafe tab state survives detail page tab switches so the tunnel '
    'stays up until the page closes',
    (WidgetTester tester) async {
      await pumpDetailTabs(tester);

      final before = tester.state<State<MaidCafeServerTab>>(
        find.byType(MaidCafeServerTab),
      );

      // The server detail page's TabBarView must keep the MaidCafe tab
      // mounted: disposing it would tear down the SSH tunnel to the daemon.
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(
        tester.state<State<MaidCafeServerTab>>(
          find.byType(MaidCafeServerTab, skipOffstage: false),
        ),
        same(before),
      );

      await tester.tap(find.text('Cafe'));
      await tester.pumpAndSettle();
      expect(
        tester.state<State<MaidCafeServerTab>>(find.byType(MaidCafeServerTab)),
        same(before),
      );
    },
  );
}
