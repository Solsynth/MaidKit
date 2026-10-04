import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

/// How much of a text file rides with a turn, in characters. It mirrors the cap
/// tool results already come back under, so one attached file can never crowd
/// out the conversation it was attached to.
const int kMaxAttachmentChars = 12000;

/// The largest file read into an attachment. Anything above this is refused
/// rather than pulled into memory whole.
const int kMaxAttachmentReadBytes = 4 * 1024 * 1024;

/// The largest image sent to the model. Image bytes travel base64-encoded
/// inside every request that still carries the turn, so the cap keeps one
/// picture from dominating a conversation's payload.
const int kMaxAttachmentImageBytes = 2 * 1024 * 1024;

/// A block pasted into the composer at least this long is hard to read in the
/// message field, so it becomes a text attachment instead. Shorter pastes stay
/// inline, where they read as part of the message.
const int kPasteTextAttachmentChars = 1000;

/// What a truncated text attachment ends with, so the model knows the file
/// continues past what it was given.
const String kAttachmentTruncatedMarker = '\n[attachment truncated]';

/// One file riding with a user turn.
///
/// A text file and a pasted block carry their [content] — the text the model
/// reads. An image carries a `data:` URL under [content], with the picked
/// bytes kept beside it for the composer's preview. An attachment that could
/// not be read keeps its [error] instead, is never sent, and is shown on its
/// tile until the reader takes it out.
@immutable
class AgentAttachment {
  const AgentAttachment({
    required this.name,
    this.content,
    this.bytes,
    this.byteSize = 0,
    this.isImage = false,
    this.error,
  });

  /// A block of text pasted into the composer: there is no file behind it.
  const AgentAttachment.text(String text, {required this.name})
    : content = text,
      bytes = null,
      byteSize = 0,
      isImage = false,
      error = null;

  /// The file's name: what the reader sees, and what the model is told.
  final String name;

  /// What the model receives: the file's text, or an image's `data:` URL.
  final String? content;

  /// The picked bytes, kept for an image's preview. Null once a saved
  /// conversation is read back, where only [content] survives.
  final Uint8List? bytes;

  /// What the picker said the file weighs, when it is a file at all.
  final int byteSize;

  final bool isImage;

  /// Why the file could not be read. An attachment carrying one is shown with
  /// the problem and is left out of the turn.
  final String? error;

  bool get isSendable => error == null && (content?.isNotEmpty ?? false);

  int get characterCount => content?.length ?? 0;

  AgentAttachment copyWith({String? content}) => AgentAttachment(
    name: name,
    content: content ?? this.content,
    bytes: bytes,
    byteSize: byteSize,
    isImage: isImage,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (content != null) 'content': content,
    if (byteSize > 0) 'byteSize': byteSize,
    if (isImage) 'isImage': true,
  };

  factory AgentAttachment.fromJson(Map<String, dynamic> json) =>
      AgentAttachment(
        name: json['name'] as String? ?? '',
        content: json['content'] as String?,
        byteSize: json['byteSize'] as int? ?? 0,
        isImage: json['isImage'] as bool? ?? false,
      );
}

/// Reads one picked file into an attachment the composer can queue.
///
/// A file that cannot be read, or that is not UTF-8 text, comes back as an
/// attachment carrying its [AgentAttachment.error] rather than throwing: the
/// composer shows the problem next to the file the reader chose, and the turn
/// waits until the strip is resolved.
Future<AgentAttachment> readAgentAttachment({
  required String name,
  String? path,
  Uint8List? bytes,
}) async {
  final contentType = imageContentTypeFor(name);
  final isImage = contentType != null;
  final limit = isImage ? kMaxAttachmentImageBytes : kMaxAttachmentReadBytes;

  AgentAttachment tooLarge(int size) => AgentAttachment(
    name: name,
    byteSize: size,
    isImage: isImage,
    error: 'agentAttachmentTooLarge'.tr(
      args: [name, formatAttachmentBytes(limit)],
    ),
  );

  Uint8List data;
  try {
    if (bytes != null) {
      data = bytes;
    } else {
      if (path == null || path.isEmpty) {
        throw const FileSystemException('The picked file has no path.');
      }
      final file = File(path);
      // The size is asked for before the read so a very large file is refused
      // without pulling it into memory first.
      final size = await file.length();
      if (size > limit) return tooLarge(size);
      data = await file.readAsBytes();
    }
  } catch (error) {
    return AgentAttachment(
      name: name,
      isImage: isImage,
      error: 'agentAttachmentReadFailed'.tr(args: [name, '$error']),
    );
  }
  if (data.length > limit) return tooLarge(data.length);

  if (isImage) {
    return AgentAttachment(
      name: name,
      content: 'data:$contentType;base64,${base64Encode(data)}',
      bytes: data,
      byteSize: data.length,
      isImage: true,
    );
  }

  final String text;
  try {
    text = utf8.decode(data);
  } on FormatException {
    return AgentAttachment(
      name: name,
      byteSize: data.length,
      error: 'agentAttachmentNotTextFile'.tr(args: [name]),
    );
  }
  return AgentAttachment(
    name: name,
    content: text.length > kMaxAttachmentChars
        ? '${text.substring(0, kMaxAttachmentChars)}$kAttachmentTruncatedMarker'
        : text,
    byteSize: data.length,
  );
}

/// The user message content for one turn: the typed text, the attached text
/// files written under it, and images as multimodal parts.
///
/// A plain string is returned while nothing is attached, because that is what
/// every OpenAI-compatible endpoint accepts. The part list only appears once
/// there is a picture to send; the text part is dropped when the message was
/// nothing but attachments.
Object agentUserContent(String text, List<AgentAttachment> attachments) {
  final sendable = [
    for (final attachment in attachments)
      if (attachment.isSendable) attachment,
  ];
  final body = StringBuffer(text.trim());
  for (final attachment in sendable.where((file) => !file.isImage)) {
    if (body.isNotEmpty) body.write('\n\n');
    body
      ..write('--- Attached file: ${attachment.name} ---\n')
      ..write(attachment.content)
      ..write('\n--- End of ${attachment.name} ---');
  }
  final images = [
    for (final attachment in sendable)
      if (attachment.isImage) attachment.content ?? '',
  ];
  if (images.isEmpty) return body.toString();
  return [
    if (body.isNotEmpty) {'type': 'text', 'text': body.toString()},
    for (final url in images)
      {
        'type': 'image_url',
        'image_url': {'url': url},
      },
  ];
}

/// The MIME type an image file is sent as, from its name, or null when the
/// name does not look like an image this app sends.
String? imageContentTypeFor(String name) {
  final separator = name.lastIndexOf('.');
  if (separator < 0) return null;
  return switch (name.substring(separator + 1).toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'avif' => 'image/avif',
    'bmp' => 'image/bmp',
    'tif' || 'tiff' => 'image/tiff',
    _ => null,
  };
}

/// A file's size as a tile can hold it: `812 B`, `12.3 kB`, `4.5 MB`.
String formatAttachmentBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return _scaled(bytes / 1000, 'kB');
  return _scaled(bytes / 1000000, 'MB');
}

/// A text attachment's length as a tile can hold it: `812`, `12.3k`.
String formatAttachmentCharacters(int characters) {
  if (characters < 1000) return '$characters';
  return _scaled(characters / 1000, 'k');
}

String _scaled(double value, String unit) {
  final text = value.toStringAsFixed(value < 100 ? 1 : 0);
  final trimmed = text.endsWith('.0')
      ? text.substring(0, text.length - 2)
      : text;
  return '$trimmed $unit';
}
