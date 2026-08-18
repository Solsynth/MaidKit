import 'dart:io';

/// Whether [entity] resolves to a directory, including directory symlinks.
bool isLocalDirectory(FileSystemEntity entity) {
  if (entity is Directory) return true;
  return entity is Link && Directory(entity.path).existsSync();
}

/// Whether [entity] resolves to a regular file, including file symlinks.
bool isLocalFile(FileSystemEntity entity) {
  if (entity is File) return true;
  return entity is Link && File(entity.path).existsSync();
}
