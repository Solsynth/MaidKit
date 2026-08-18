import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/remote_file_system.dart';

void main() {
  test('resolves a symbolic-link listing to its directory target', () {
    final listed = SftpFileAttrs(mode: SftpFileMode.value(0xA000));
    final target = SftpFileAttrs(mode: SftpFileMode.value(0x4000));

    expect(isRemoteDirectoryEntry(listed, followed: target), isTrue);
    expect(isRemoteFileEntry(listed, followed: target), isFalse);
  });
}
