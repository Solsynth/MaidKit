import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_health_section.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

/// A session stub serving one canned `/api/v1/health` answer; the card reads
/// nothing else from the session.
class _FakeSession implements MaidCafeStreamSession {
  _FakeSession(this.answer);

  final Future<Map<String, dynamic>> Function() answer;

  @override
  Future<Map<String, dynamic>> healthReport() => answer();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pumpCard(
  WidgetTester tester,
  MaidCafeStreamSession session,
) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: MaidCafeHealthSection(session: session),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('renders the score, its band and every dimension', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      _FakeSession(
        () async => {
          'score': 84,
          'status': 'degraded',
          'evaluated_at': '2026-08-15T12:00:00Z',
          'host_id': 'host-1',
          'checks': [
            {
              'name': 'cpu',
              'status': 'ok',
              'score': 100,
              'value': 12.3,
              'unit': 'percent',
              'warn': 75,
              'crit': 95,
            },
            {
              'name': 'disk',
              'status': 'warning',
              'score': 33.3,
              'value': 90,
              'unit': 'percent',
              'detail': '/var',
              'warn': 80,
              'crit': 95,
            },
            {
              'name': 'swap',
              'status': 'ok',
              'score': 100,
              'value': 0,
              'unit': 'percent',
              'warn': 50,
              'crit': 90,
              'skipped': true,
            },
          ],
          'issues': ['Disk usage /var at 90.0% (warn 80.0%, crit 95.0%)'],
        },
      ),
    );

    expect(find.text('detailHealth'.tr()), findsOneWidget);
    expect(find.text('84'), findsOneWidget);
    expect(find.text('maidCafeHealthOutOf'.tr()), findsOneWidget);
    expect(find.text('healthStatusDegraded'.tr()), findsOneWidget);
    // Only the disk dimension crossed a threshold, and the skipped swap one is
    // never counted as an issue.
    expect(
      find.text('maidCafeHealthIssueCount'.tr(args: ['1'])),
      findsOneWidget,
    );
    expect(find.text('maidCafeHealthCheckCpu'.tr()), findsOneWidget);
    expect(find.text('12.3%'), findsOneWidget);
    expect(find.text('maidCafeHealthCheckDisk'.tr()), findsNothing);
    expect(find.textContaining('/var'), findsOneWidget);
    expect(
      find.text('maidCafeHealthThresholds'.tr(args: ['80.0%', '95.0%'])),
      findsOneWidget,
    );
    expect(find.text('maidCafeHealthNotApplicable'.tr()), findsOneWidget);
    // A dimension that does not apply shows no reading at all.
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('tells the user to update a daemon without the health route', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      _FakeSession(
        () async => throw const MaidCafeRouteMissingException('/api/v1/health'),
      ),
    );

    expect(find.text('maidCafeHealthUnsupported'.tr()), findsOneWidget);
    expect(find.text('maidCafeHealthOutOf'.tr()), findsNothing);
  });

  testWidgets('a failed read reports itself and the refresh retries', (
    tester,
  ) async {
    var calls = 0;
    await _pumpCard(
      tester,
      _FakeSession(() async {
        calls++;
        if (calls == 1) throw StateError('daemon unreachable');
        return {'score': 96, 'status': 'healthy', 'checks': const []};
      }),
    );

    expect(find.textContaining('daemon unreachable'), findsOneWidget);

    await tester.tap(find.byTooltip('commonRefresh'.tr()));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('96'), findsOneWidget);
    expect(find.text('healthStatusHealthy'.tr()), findsOneWidget);
    expect(find.text('maidCafeHealthAllWithinThresholds'.tr()), findsOneWidget);
  });
}
