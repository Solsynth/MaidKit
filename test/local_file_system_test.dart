import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/local_file_system.dart';

void main() {
  test('recognizes a directory symlink as a local directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'maidkit-local-file-system-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final target = Directory('${root.path}/target')..createSync();
    final link = Link('${root.path}/linked-folder');
    try {
      await link.create(target.path);
    } on FileSystemException {
      markTestSkipped('The test environment does not allow symlink creation.');
      return;
    }

    expect(isLocalDirectory(link), isTrue);
    expect(isLocalFile(link), isFalse);
  });
}
