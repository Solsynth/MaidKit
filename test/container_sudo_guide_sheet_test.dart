import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/containers/container_sudo_guide.dart';
import 'package:maid_kit/data/local/app_database.dart';

const _refusal =
    'Bad state: project "openlist" lives in podman in root\'s store, and the '
    'compose tool that runs there — /usr/local/bin/podman-compose — may not be '
    'run through `sudo -n` on this host; grant it (for example `maidcafe '
    'ALL=(root) NOPASSWD: /usr/local/bin/podman-compose` in a file under '
    '/etc/sudoers.d/) or run the step yourself as root';

/// A refusal with no fix to offer, of the length the daemon's store-conflict
/// messages reach.
const _longFailure =
    'Bad state: project "openlist" exists in more than one store (podman in '
    'root\'s store: openlist-web (running), openlist-db (exited); docker in '
    'the daemon user\'s own store: openlist-web (created)); this daemon will '
    'not choose between them — remove the copy you do not want, then try again';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpHost(
    WidgetTester tester,
    Widget host, {
    Size size = const Size(420, 760),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          child: MaterialApp(
            // The app's own chrome renders its overlay at this key, and the
            // failure notices go through it.
            home: Overlay(
              key: overlayKey,
              initialEntries: [OverlayEntry(builder: (context) => host)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the guide reads and offers the rule on a narrow surface', (
    tester,
  ) async {
    // A phone-width sheet: the blocks wrap, the buttons wrap, nothing is cut
    // off. A desktop-only layout would overflow here.
    await pumpHost(tester, const _GuideHost());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('containerSudoGuideTitle'.tr()), findsOneWidget);
    expect(find.text("openlist · podman in root's store"), findsOneWidget);
    expect(
      find.text('maidcafe ALL=(root) NOPASSWD: /usr/local/bin/podman-compose'),
      findsOneWidget,
    );
    expect(find.text('containerSudoGuideNoSsh'.tr()), findsOneWidget);
    // No SSH session in this test, so the rule can only be installed by hand.
    final install = tester.widget<FilledButton>(
      find.widgetWithText(
        FilledButton,
        'containerSudoGuideInstall'.tr(args: ['Build host']),
      ),
    );
    expect(install.onPressed, isNull);

    await tester.tap(find.text('commonClose'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('containerSudoGuideTitle'.tr()), findsNothing);
  });

  testWidgets('a long failure with no fix opens a sheet that can be copied', (
    tester,
  ) async {
    await pumpHost(tester, const _FailureHost(message: _longFailure));

    await tester.tap(find.text('fail'));
    await tester.pumpAndSettle();

    // The whole paragraph is there to read, not two truncated lines of it.
    expect(find.text(_longFailure), findsOneWidget);
    expect(find.text('deploymentActionFailed'.tr()), findsWidgets);
    expect(find.text('commonCopy'.tr()), findsOneWidget);
  });

  testWidgets('a failure a snackbar can hold stays a snackbar', (tester) async {
    await pumpHost(tester, const _FailureHost(message: 'connection closed'));

    await tester.tap(find.text('fail'));
    // The app's snackbars live 1.5s, so the assertion happens while one is up
    // and the settle that follows drains its timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('connection closed'), findsOneWidget);
    expect(find.text('commonCopy'.tr()), findsNothing);
    await tester.pumpAndSettle();
  });
}

Server get _server => Server(
  id: 1,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'builder',
  collectStats: true,
  collectSystemInfo: true,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

/// Opens the guide the way a refused container step does.
class _GuideHost extends ConsumerWidget {
  const _GuideHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showContainerSudoGuideSheet(
          context: context,
          ref: ref,
          server: _server,
          grant: parseContainerSudoGrant(_refusal)!,
        ),
        child: const Text('open'),
      ),
    ),
  );
}

/// Reports a failure the way every container action does.
class _FailureHost extends ConsumerWidget {
  const _FailureHost({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => reportContainerSudoFailure(
          context: context,
          ref: ref,
          server: _server,
          error: StateError(message),
          snackBarTitle: 'deploymentActionFailed'.tr(),
        ),
        child: const Text('fail'),
      ),
    ),
  );
}
