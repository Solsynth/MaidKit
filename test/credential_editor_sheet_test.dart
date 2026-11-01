import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/credentials_page.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// The last text the app put on the system clipboard.
  var clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String? ?? '';
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Pumps a host page and opens the credential editor sheet on top of it.
  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
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
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(builder: (_) => const _SheetHost()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('settingsCredentialAdd'.tr()));
    await tester.pumpAndSettle();
  }

  testWidgets('offers a password generator that fills the field', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('serverAuthPassword'.tr()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('credentialsGeneratePassword'.tr()));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'serverPasswordLabel'.tr()).first,
    );
    final password = field.controller!.text;
    expect(password, hasLength(20));
    expect(password.contains(RegExp('[a-z]')), isTrue);
    expect(password.contains(RegExp('[A-Z]')), isTrue);
    expect(password.contains(RegExp('[0-9]')), isTrue);
  });

  testWidgets('generates a key pair and fills the private key field', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('credentialsGenerateKey'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('credentialsKeyGenerateTitle'.tr()), findsOneWidget);
    expect(find.text('credentialsKeyEd25519'.tr()), findsOneWidget);
    expect(find.text('credentialsKeyRsa'.tr()), findsOneWidget);

    // The sheet underneath has a passphrase field of its own, so scope the
    // dialog's fields explicitly.
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextField, 'credentialsKeyComment'.tr()),
      ),
      'workstation',
    );
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(
          TextField,
          'serverKeyPassphraseLabel'.tr(),
        ),
      ),
      'vault-pass',
    );

    // Key generation runs on an isolate, which only advances inside runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.text('credentialsKeyGenerateAction'.tr()));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(find.text('credentialsKeyResultTitle'.tr()), findsOneWidget);

    await tester.tap(find.text('credentialsKeyUseKey'.tr()));
    await tester.pumpAndSettle();

    final keyField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'serverPrivateKeyLabel'.tr()).first,
    );
    final pem = keyField.controller!.text;
    expect(pem, contains('BEGIN OPENSSH PRIVATE KEY'));
    expect(
      SSHKeyPair.isEncryptedPem(pem),
      isTrue,
      reason: 'the saved private key must be passphrase-protected',
    );
    expect(SSHKeyPair.fromPem(pem, 'vault-pass').single.comment, 'workstation');

    final passphraseField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'serverKeyPassphraseLabel'.tr()).first,
    );
    expect(passphraseField.controller!.text, 'vault-pass');

    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'settingsCredentialName'.tr()).first,
    );
    expect(nameField.controller!.text, 'workstation');

    // The public half is the part the server needs, so it is left on the
    // clipboard instead of buried in the private key field.
    expect(clipboard, startsWith('ssh-ed25519 AAAA'));
    expect(clipboard, endsWith(' workstation'));
  });

  testWidgets('refuses to save a protected key after clearing its passphrase', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('credentialsGenerateKey'.tr()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(
          TextField,
          'serverKeyPassphraseLabel'.tr(),
        ),
      ),
      'vault-pass',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('credentialsKeyGenerateAction'.tr()));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('credentialsKeyUseKey'.tr()));
    await tester.pumpAndSettle();

    // Clearing the passphrase would leave a PEM the connection manager cannot
    // open, so the sheet refuses that save instead of writing it.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'serverKeyPassphraseLabel'.tr()).first,
      '',
    );
    await tester.tap(find.text('commonSave'.tr()));
    await tester.pumpAndSettle();

    // The sheet stays open instead of writing a credential the connection
    // manager could never open.
    expect(
      find.widgetWithText(TextFormField, 'serverPrivateKeyLabel'.tr()),
      findsOneWidget,
    );
    final keyField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'serverPrivateKeyLabel'.tr()).first,
    );
    expect(keyField.controller!.text, contains('BEGIN OPENSSH PRIVATE KEY'));
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => showCredentialEditorSheet(context),
        child: Text('settingsCredentialAdd'.tr()),
      ),
    ),
  );
}
