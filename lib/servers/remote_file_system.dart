import 'package:dartssh2/dartssh2.dart';

/// Whether an SFTP listing entry resolves to a directory.
bool isRemoteDirectoryEntry(SftpFileAttrs listed, {SftpFileAttrs? followed}) {
  return listed.isDirectory ||
      (listed.isSymbolicLink && followed?.isDirectory == true);
}

/// Whether an SFTP listing entry resolves to a regular file.
bool isRemoteFileEntry(SftpFileAttrs listed, {SftpFileAttrs? followed}) {
  return listed.isFile || (listed.isSymbolicLink && followed?.isFile == true);
}
