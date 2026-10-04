import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/agent/agent_attachment.dart';
import 'package:maid_kit/agent/conversation_store.dart';

void main() {
  late Directory temp;
  late AgentConversationStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('conversation_store_test');
    store = AgentConversationStore(directory: temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  AgentConversationDraft draft(
    String title,
    List<AgentConversationMessage> messages,
  ) => AgentConversationDraft(
    title: title,
    messages: messages,
    providerId: 1,
    modelId: 2,
  );

  test('persists a conversation as a JSONL file and reloads it', () async {
    final id = await store.saveConversation(
      draft('Hello', const [
        AgentConversationMessage(role: 'user', text: 'hi'),
        AgentConversationMessage(role: 'assistant', text: 'hello!\nnext line'),
      ]),
    );
    expect(id, 1);
    final file = File('${temp.path}${Platform.pathSeparator}1.jsonl');
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines, hasLength(3));
    expect(jsonDecode(lines[0])['title'], 'Hello');
    expect(jsonDecode(lines[1]), {'role': 'user', 'text': 'hi'});
    // Embedded newlines stay inside a single JSONL line.
    expect(lines[2].split('\n'), hasLength(1));
    final loaded = await store.conversation(id);
    expect(loaded, isNotNull);
    expect(loaded!.title, 'Hello');
    expect(loaded.messages, hasLength(2));
    expect(loaded.messages[1].text, 'hello!\nnext line');
    expect(loaded.providerId, 1);
    expect(loaded.modelId, 2);
  });

  test('list returns conversations newest first', () async {
    final first = await store.saveConversation(
      draft('A', const [AgentConversationMessage(role: 'user', text: 'a')]),
    );
    final second = await store.saveConversation(
      draft('B', const [AgentConversationMessage(role: 'user', text: 'b')]),
    );
    // Updating the first conversation makes it the most recently touched.
    await store.saveConversation(
      draft('A2', const [AgentConversationMessage(role: 'user', text: 'a2')]),
      id: first,
    );
    final conversations = await store.list();
    expect(conversations.map((c) => c.id), [first, second]);
    expect(conversations.first.title, 'A2');
  });

  test('updating a conversation keeps its id and createdAt', () async {
    final id = await store.saveConversation(
      draft('First', const [
        AgentConversationMessage(role: 'user', text: 'one'),
      ]),
    );
    final before = await store.conversation(id);
    await store.saveConversation(
      draft('Second', const [
        AgentConversationMessage(role: 'user', text: 'two'),
      ]),
      id: id,
    );
    final after = await store.conversation(id);
    expect(after, isNotNull);
    expect(after!.id, id);
    expect(after.title, 'Second');
    expect(after.createdAt, before!.createdAt);
    expect(after.messages.single.text, 'two');
  });

  test('delete removes the conversation file', () async {
    final id = await store.saveConversation(
      draft('Gone', const [AgentConversationMessage(role: 'user', text: 'x')]),
    );
    await store.deleteConversation(id);
    expect(await store.conversation(id), isNull);
    expect(
      await File('${temp.path}${Platform.pathSeparator}$id.jsonl').exists(),
      isFalse,
    );
  });

  test('evicts the oldest conversations beyond the cap', () async {
    final ids = <int>[];
    for (var i = 0; i < AgentConversationStore.maxConversations + 3; i++) {
      ids.add(
        await store.saveConversation(
          draft('Chat $i', const [
            AgentConversationMessage(role: 'user', text: 'x'),
          ]),
        ),
      );
    }
    final conversations = await store.list();
    expect(conversations, hasLength(AgentConversationStore.maxConversations));
    for (final id in ids.take(3)) {
      expect(await store.conversation(id), isNull);
    }
  });

  test('history survives a fresh store over the same folder', () async {
    final id = await store.saveConversation(
      draft('Persistent', const [
        AgentConversationMessage(role: 'user', text: 'hi'),
      ]),
    );
    final reopened = AgentConversationStore(directory: temp);
    final conversations = await reopened.list();
    expect(conversations.single.id, id);
    expect((await reopened.conversation(id))!.messages.single.text, 'hi');
  });

  test('attachments ride a message through a save and a reload', () async {
    final id = await store.saveConversation(
      draft('With files', const [
        AgentConversationMessage(
          role: 'user',
          text: 'why is this failing',
          attachments: [
            AgentAttachment(name: 'app.log', content: 'line one\nline two'),
            AgentAttachment(
              name: 'shot.png',
              content: 'data:image/png;base64,cG5n',
              byteSize: 4,
              isImage: true,
            ),
          ],
        ),
        AgentConversationMessage(role: 'assistant', text: 'Because of X.'),
      ]),
    );
    final loaded = await store.conversation(id);
    expect(loaded, isNotNull);
    final attachments = loaded!.messages.first.attachments;
    expect(attachments, hasLength(2));
    expect(attachments.first.name, 'app.log');
    expect(attachments.first.content, 'line one\nline two');
    expect(attachments.first.isImage, isFalse);
    expect(attachments.last.name, 'shot.png');
    expect(attachments.last.content, 'data:image/png;base64,cG5n');
    expect(attachments.last.isImage, isTrue);
    expect(attachments.last.byteSize, 4);
    // A message without attachments stays written without the key.
    expect(loaded.messages.last.attachments, isEmpty);
  });

  test('corrupt and foreign files are ignored', () async {
    await File('${temp.path}${Platform.pathSeparator}99.jsonl').writeAsString(
      'not json\n{"id":99,"title":"broken","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}\n',
    );
    await File(
      '${temp.path}${Platform.pathSeparator}notes.txt',
    ).writeAsString('ignored\n');
    final id = await store.saveConversation(
      draft('Ok', const [AgentConversationMessage(role: 'user', text: 'y')]),
    );
    final conversations = await store.list();
    expect(conversations.map((c) => c.id), [id]);
    // The corrupt id 99 was not reused.
    expect(id, greaterThan(99));
  });

  test(
    'watchConversations emits the initial list and every mutation',
    () async {
      final events = <List<AgentConversation>>[];
      final subscription = store.watchConversations().listen(events.add);
      // Let the initial snapshot be delivered before mutating.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final id = await store.saveConversation(
        draft('Watched', const [
          AgentConversationMessage(role: 'user', text: 'w'),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.deleteConversation(id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      expect(events.map((list) => list.map((c) => c.id).toList()), [
        <int>[],
        [id],
        <int>[],
      ]);
    },
  );
}
