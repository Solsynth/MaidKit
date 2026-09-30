import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/assets_page.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';

/// In-memory stand-in so the widget test can drive the editor without waiting
/// on the database. The real column mapping is covered by
/// `snippet_repository_test.dart`.
class _FakeSnippetRepository extends SnippetRepository {
  _FakeSnippetRepository(AppDatabase database) : super(database);

  final rows = <ScriptSnippet>[];
  int _nextId = 1;

  int? savedId;
  List<String>? savedTags;
  bool? savedExcludedFromAutocomplete;
  bool? savedDangerous;

  @override
  Future<int> save({
    int? id,
    required String name,
    required String script,
    List<String> tags = const [],
    bool excludedFromAutocomplete = false,
    bool dangerous = false,
  }) async {
    savedId = id;
    savedTags = tags;
    savedExcludedFromAutocomplete = excludedFromAutocomplete;
    savedDangerous = dangerous;
    final resolved = id ?? _nextId++;
    rows.removeWhere((row) => row.id == resolved);
    rows.add(
      ScriptSnippet(
        id: resolved,
        name: name.trim(),
        script: script,
        tags: encodeStringList(tags),
        excludedFromAutocomplete: excludedFromAutocomplete,
        dangerous: dangerous,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    return resolved;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('editor saves tags and flags, and the library renders them', (
    tester,
  ) async {
    // The fake never touches the database, so the handle only satisfies the
    // repository constructor.
    final repository = _FakeSnippetRepository(
      AppDatabase(filePath: '${Directory.systemTemp.path}/unused.sqlite'),
    );

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    repository.rows
      ..clear()
      ..add(
        ScriptSnippet(
          id: 1,
          name: 'Deploy',
          script: 'echo deploy',
          excludedFromAutocomplete: false,
          dangerous: false,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    final controller = StreamController<List<ScriptSnippet>>();
    addTearDown(controller.close);
    controller.add(List.of(repository.rows));

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            snippetRepositoryProvider.overrideWithValue(repository),
            scriptSnippetsProvider.overrideWith((ref) => controller.stream),
          ],
          child: const MaterialApp(home: Scaffold(body: SnippetsSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deploy'), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.edit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'snippetsTagAdd'.tr()),
      'ops, prod',
    );
    await tester.tap(find.byIcon(Symbols.add));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'ops'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'prod'), findsOneWidget);

    final excluded = find.widgetWithText(
      SwitchListTile,
      'snippetsExcludeFromAutocomplete'.tr(),
    );
    final dangerous = find.widgetWithText(
      SwitchListTile,
      'snippetsDangerous'.tr(),
    );
    await tester.ensureVisible(excluded);
    await tester.tap(excluded);
    await tester.pumpAndSettle();
    await tester.ensureVisible(dangerous);
    await tester.tap(dangerous);
    await tester.pumpAndSettle();

    final save = find.text('commonSave'.tr());
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.savedId, 1);
    expect(repository.savedTags, ['ops', 'prod']);
    expect(repository.savedExcludedFromAutocomplete, isTrue);
    expect(repository.savedDangerous, isTrue);

    // The library row surfaces the tags and both flags once the stream emits
    // the updated row.
    controller.add(List.of(repository.rows));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'ops'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'prod'), findsOneWidget);
    expect(find.byIcon(Symbols.warning), findsOneWidget);
    expect(find.byIcon(Symbols.visibility_off), findsOneWidget);
  });
}
