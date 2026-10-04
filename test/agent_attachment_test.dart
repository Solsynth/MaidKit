import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/agent/agent_attachment.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agent_attachment_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<AgentAttachment> readPicked(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return readAgentAttachment(name: name, path: file.path);
  }

  group('readAgentAttachment', () {
    test('reads a text file whole, name and length included', () async {
      final attachment = await readPicked(
        'app.log',
        utf8.encode('line one\nline two'),
      );
      expect(attachment.name, 'app.log');
      expect(attachment.content, 'line one\nline two');
      expect(attachment.isImage, isFalse);
      expect(attachment.error, isNull);
      expect(attachment.isSendable, isTrue);
      expect(attachment.characterCount, 17);
    });

    test('truncates a long file and marks where it stopped', () async {
      final attachment = await readPicked(
        'huge.log',
        utf8.encode('x' * (kMaxAttachmentChars + 500)),
      );
      expect(
        attachment.content,
        hasLength(kMaxAttachmentChars + kAttachmentTruncatedMarker.length),
      );
      expect(attachment.content!.endsWith(kAttachmentTruncatedMarker), isTrue);
      expect(attachment.isSendable, isTrue);
    });

    test('refuses a file that is not UTF-8 text', () async {
      final attachment = await readPicked('blob.bin', const [
        0xff,
        0xfe,
        0x00,
        0x01,
      ]);
      expect(attachment.error, isNotNull);
      expect(attachment.content, isNull);
      expect(attachment.isSendable, isFalse);
    });

    test('refuses a file larger than the cap', () async {
      final attachment = await readPicked(
        'big.log',
        Uint8List(kMaxAttachmentReadBytes + 1),
      );
      expect(attachment.error, isNotNull);
      expect(attachment.content, isNull);
    });

    test('an image becomes a data URL with its bytes kept', () async {
      final bytes = utf8.encode('png bytes');
      final attachment = await readPicked('shot.png', bytes);
      expect(attachment.isImage, isTrue);
      expect(
        attachment.content,
        'data:image/png;base64,${base64Encode(bytes)}',
      );
      expect(attachment.bytes, bytes);
      expect(attachment.byteSize, bytes.length);
      expect(attachment.isSendable, isTrue);
    });

    test('an oversized image is refused', () async {
      final attachment = await readAgentAttachment(
        name: 'shot.png',
        bytes: Uint8List(kMaxAttachmentImageBytes + 1),
      );
      expect(attachment.error, isNotNull);
      expect(attachment.content, isNull);
      expect(attachment.isSendable, isFalse);
    });

    test('a pick with nothing to read is an error, not a crash', () async {
      final attachment = await readAgentAttachment(name: 'x.txt');
      expect(attachment.error, isNotNull);
      expect(attachment.isSendable, isFalse);
    });
  });

  test('imageContentTypeFor knows the formats the app sends', () {
    expect(imageContentTypeFor('a.PNG'), 'image/png');
    expect(imageContentTypeFor('a.jpeg'), 'image/jpeg');
    expect(imageContentTypeFor('a.webp'), 'image/webp');
    expect(imageContentTypeFor('a.log'), isNull);
    expect(imageContentTypeFor('noextension'), isNull);
  });

  group('agentUserContent', () {
    const text = AgentAttachment(name: 'app.log', content: 'boom');
    const image = AgentAttachment(
      name: 'shot.png',
      content: 'data:image/png;base64,cG5n',
      isImage: true,
    );
    const failed = AgentAttachment(name: 'blob.bin', error: 'unreadable');

    test('is the plain message while nothing is attached', () {
      expect(agentUserContent('hello', const []), 'hello');
    });

    test('writes attached text files under a header', () {
      final content = agentUserContent('look', const [text]);
      expect(content, isA<String>());
      final body = content as String;
      expect(body, startsWith('look'));
      expect(body, contains('--- Attached file: app.log ---\nboom'));
      expect(body, contains('--- End of app.log ---'));
    });

    test('turns an image into a multimodal part list', () {
      final content = agentUserContent('look', const [text, image]);
      expect(content, isA<List<Map<String, dynamic>>>());
      final parts = content as List<Map<String, dynamic>>;
      expect(parts, hasLength(2));
      expect(parts.first['type'], 'text');
      expect(parts.first['text'], contains('boom'));
      expect(parts.last['type'], 'image_url');
      expect(parts.last['image_url'], {'url': 'data:image/png;base64,cG5n'});
    });

    test('leaves out an attachment that could not be read', () {
      final parts =
          agentUserContent('look', const [failed, image])
              as List<Map<String, dynamic>>;
      expect(parts, hasLength(2));
      final textPart = parts.singleWhere((part) => part['type'] == 'text');
      expect(textPart['text'], 'look');
      expect(textPart['text'], isNot(contains('blob.bin')));
    });

    test('an attachment-only turn carries no empty text part', () {
      final parts = agentUserContent('', const [image]);
      expect(parts, hasLength(1));
      expect((parts as List<Map<String, dynamic>>).single['type'], 'image_url');
    });
  });
}
