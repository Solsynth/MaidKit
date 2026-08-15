import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_server_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
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
