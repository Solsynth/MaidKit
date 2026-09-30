import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';

/// drift_flutter resolves its native database directory through
/// path_provider; point it at the system temp directory in tests.
void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });
}

void main() {
  _mockPathProvider();

  group('SnippetRepository snippet metadata', () {
    late AppDatabase database;
    late SnippetRepository repository;

    setUp(() {
      final directory = Directory.systemTemp.createTempSync('snippet_test');
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      repository = SnippetRepository(database);
    });

    tearDown(() => database.close());

    test(
      'save keeps tags and flags, autocomplete hides excluded ones',
      () async {
        final deployId = await repository.save(
          name: 'Deploy',
          script: 'echo deploy',
          tags: const ['ops', ' ops ', '', 'prod'],
          dangerous: true,
        );
        final scratchId = await repository.save(
          name: 'Scratch',
          script: 'echo scratch',
          excludedFromAutocomplete: true,
        );

        final library = await repository.all();
        expect(library.map((snippet) => snippet.name), ['Deploy', 'Scratch']);
        expect(library, hasLength(2));

        final deploy = await repository.snippet(deployId);
        expect(decodeStringList(deploy!.tags), ['ops', 'prod']);
        expect(deploy.dangerous, isTrue);
        expect(deploy.excludedFromAutocomplete, isFalse);
        expect(deploy.lastServerIds, isNull);

        final scratch = await repository.snippet(scratchId);
        expect(scratch!.excludedFromAutocomplete, isTrue);
        expect(scratch.dangerous, isFalse);
        expect(scratch.tags, isNull);

        // Only the snippet left visible in terminal autocomplete is offered.
        expect((await repository.autocomplete()).map((snippet) => snippet.id), [
          deployId,
        ]);
      },
    );

    test('rememberServers round-trips and survives an edit', () async {
      final id = await repository.save(name: 'Deploy', script: 'echo deploy');
      expect((await repository.snippet(id))!.lastServerIds, isNull);

      await repository.rememberServers(id, const [2, 5]);
      expect(
        decodeSnippetIdList((await repository.snippet(id))!.lastServerIds),
        [2, 5],
      );

      // Editing name, script, tags, or flags must not drop the remembered
      // servers; the run dialog pre-selects them.
      await repository.save(
        id: id,
        name: 'Deploy v2',
        script: 'echo v2',
        tags: const ['ops'],
      );
      final edited = await repository.snippet(id);
      expect(edited!.name, 'Deploy v2');
      expect(decodeStringList(edited.tags), ['ops']);
      expect(decodeSnippetIdList(edited.lastServerIds), [2, 5]);

      await repository.rememberServers(id, null);
      expect((await repository.snippet(id))!.lastServerIds, isNull);
    });
  });
}
