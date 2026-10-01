import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/solarpass_device_code_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _authorization = SolarpassDeviceAuthorization(
  userCode: 'ABCD-1234',
  verificationUri: Uri.parse('https://id.solian.app/auth/device'),
  verificationUriComplete: Uri.parse(
    'https://id.solian.app/auth/device?code=ABCD-1234',
  ),
  expiresAt: DateTime(2026, 1, 1),
);

/// Pumps a host page and hands back a context the flow can open the dialog on.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return context;
}

/// The waiting row spins forever, so `pumpAndSettle` never returns: pump the
/// route transition by hand instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('shows the code a pending sign-in waits on', (tester) async {
    final context = await _pumpHost(tester);
    final pending = Completer<void>();

    final result = withSolarpassDeviceCode<String>(context, (
      onDeviceCode,
    ) async {
      onDeviceCode(_authorization);
      await pending.future;
      return 'signed-in';
    });
    await _settle(tester);

    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.text('solarpassDeviceCodeWaiting'.tr()), findsOneWidget);

    pending.complete();
    await _settle(tester);

    expect(await result, 'signed-in');
    expect(find.text('ABCD-1234'), findsNothing);
  });

  testWidgets('closes when the sign-in ends before the dialog is on screen', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    // The code arrives and the flow ends in the same turn, so the route is
    // asked to close before it has ever been built.
    final result = withSolarpassDeviceCode<String>(context, (onDeviceCode) async {
      onDeviceCode(_authorization);
      return 'signed-in';
    });
    await _settle(tester);

    expect(await result, 'signed-in');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('closing the dialog leaves the sign-in running', (tester) async {
    final context = await _pumpHost(tester);
    final pending = Completer<void>();
    var finished = false;

    final result = withSolarpassDeviceCode<String>(context, (
      onDeviceCode,
    ) async {
      onDeviceCode(_authorization);
      await pending.future;
      finished = true;
      return 'signed-in';
    });
    await _settle(tester);

    await tester.tap(find.text('commonClose'.tr()));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(finished, isFalse, reason: 'the authorization keeps running');

    pending.complete();
    await _settle(tester);

    expect(await result, 'signed-in');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
