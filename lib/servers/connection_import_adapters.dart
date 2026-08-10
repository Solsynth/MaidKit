import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/block/des_base.dart';

import 'server_models.dart';

/// A parsed connection from a MaidKit export or a third-party client,
/// ready for review before import.
class ImportedConnection {
  const ImportedConnection({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.connectionType,
    this.credential,
    this.proxy,
    this.environment = const {},
    this.tags = const [],
    this.serialConfig,
    this.source = 'MaidKit',
  });

  final String name;
  final String host;
  final int port;
  final String username;
  final ServerConnectionType connectionType;

  /// Null when the source was redacted or the secret could not be decrypted;
  /// the user assigns a credential after import.
  final ServerCredential? credential;

  /// Proxy with password already decrypted from the secrets block.
  final ServerProxy? proxy;
  final Map<String, String> environment;
  final List<String> tags;
  final SerialConfig? serialConfig;

  /// Origin label shown in the import preview, e.g. "FinalShell".
  final String source;
}

/// Parses connection data produced by another SSH client.
abstract interface class ConnectionImportAdapter {
  String get name;

  /// Whether [content] looks like this client's format. Must not throw.
  bool supports(String content);

  List<ImportedConnection> parse(String content, {String? baseDirectory});
}

/// Returns the adapter matching [content], or null when nothing does.
ConnectionImportAdapter? detectThirdPartyAdapter(String content) {
  for (final adapter in [
    FinalShellAdapter(),
    XShellAdapter(),
    SecureCrtAdapter(),
    MobaXtermAdapter(),
    PuTTYAdapter(),
    OpenSshConfigAdapter(),
  ]) {
    if (adapter.supports(content)) return adapter;
  }
  return null;
}

/// OpenSSH `~/.ssh/config`-style files: `Host` blocks with indented options.
/// Wildcard patterns are skipped; `IdentityFile` contents are imported when
/// the file is readable.
class OpenSshConfigAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'OpenSSH config';

  @override
  bool supports(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      return RegExp(r'^host\s+\S', caseSensitive: false).hasMatch(trimmed);
    }
    return false;
  }

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    final connections = <ImportedConnection>[];
    var patterns = <String>[];
    var hostName = '';
    var user = '';
    var port = 22;
    var identityFile = '';

    void flush() {
      final usable = patterns
          .where((pattern) => !pattern.contains('*') && !pattern.contains('?'))
          .toList();
      if (usable.isNotEmpty) {
        final host = hostName.isEmpty ? usable.first : hostName;
        connections.add(
          ImportedConnection(
            name: usable.first,
            host: host,
            port: port,
            username: user,
            credential: identityFile.isEmpty
                ? _readDefaultKeyCredential()
                : _readKeyCredential(identityFile, baseDirectory),
            connectionType: ServerConnectionType.ssh,
            source: name,
          ),
        );
      }
      patterns = const [];
      hostName = '';
      user = '';
      port = 22;
      identityFile = '';
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(r'^([A-Za-z][A-Za-z0-9]*)\s+(.*)$').firstMatch(line);
      if (match == null) continue;
      final key = match.group(1)!.toLowerCase();
      final value = match.group(2)!.trim();
      if (key == 'host') {
        flush();
        patterns = value.split(RegExp(r'\s+'));
      } else if (patterns.isEmpty) {
        continue; // Global options (HostKeyAlgorithms, ...) are ignored.
      } else if (key == 'hostname') {
        hostName = value;
      } else if (key == 'user') {
        user = value;
      } else if (key == 'port') {
        port = int.tryParse(value) ?? 22;
      } else if (key == 'identityfile' && identityFile.isEmpty) {
        identityFile = value;
      }
    }
    flush();
    return connections;
  }
}

/// FinalShell connection JSON files (`*_connect_config.json`, one host per
/// file). Passwords are imported when decryptable: FinalShell 4.x uses an
/// 8-byte head seeding `java.util.Random` to derive a DES key (MD5 of eight
/// packed longs), older versions use DES with a hardcoded key.
class FinalShellAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'FinalShell';

  @override
  bool supports(String content) {
    if (!content.trimLeft().startsWith('{')) return false;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return false;
      if (decoded.containsKey('format')) return false; // MaidKit JSON.
      return decoded.containsKey('host') &&
          (decoded.containsKey('port') ||
              decoded.containsKey('user_name') ||
              decoded.containsKey('password'));
    } on FormatException {
      return false;
    }
  }

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) return const [];

    final host = _firstString(decoded, const ['host', '#host']) ?? '';
    if (host.isEmpty) return const [];
    final name = _firstString(decoded, const ['name', '#name']) ?? host;
    final port = _firstInt(decoded, const ['port', '#port']) ?? 22;
    final user =
        _firstString(decoded, const ['user_name', 'user', 'username']) ?? '';
    final authMode =
        (_firstString(decoded, const ['authMode', 'auth_mode', 'authmode']) ??
                'password')
            .toLowerCase();
    final password = _firstValue(decoded, const ['password', '#password']);
    final privateKeyPath =
        _firstString(decoded, const ['privateKey', 'private_key']) ?? '';
    final passphrase = _firstString(decoded, const ['passphrase']) ?? '';
    final rawTags = decoded['tags'];

    ServerCredential? credential;
    if (authMode.contains('privatekey')) {
      credential = _readKeyCredential(privateKeyPath, baseDirectory);
      if (credential != null && passphrase.isNotEmpty) {
        credential = ServerCredential.privateKey(
          privateKey: credential.privateKey!,
          keyPassphrase: passphrase,
        );
      }
    } else if (authMode.contains('password')) {
      final secret = password is String
          ? password
          : password is Map<String, dynamic>
          ? _firstValue(password, const ['secret'])?.toString()
          : null;
      if (secret != null) {
        final decodedPassword = _decodeFinalShellPassword(secret);
        if (decodedPassword != null) {
          credential = ServerCredential.password(decodedPassword);
        } else if (!_looksLikeBase64(secret)) {
          credential = ServerCredential.password(secret);
        }
      }
    }

    return [
      ImportedConnection(
        name: name,
        host: host,
        port: port,
        username: user,
        credential: credential,
        connectionType: ServerConnectionType.ssh,
        tags: [
          for (final tag in rawTags is List ? rawTags : const [])
            if (tag is String && tag.isNotEmpty) tag,
        ],
        source: this.name,
      ),
    ];
  }
}

/// NetSarang XShell session files (`.xsh`, INI format). Passwords are bound
/// to the Windows user SID and cannot be decrypted off that machine; the
/// connection metadata and (when readable) the public-key file are imported.
class XShellAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'XShell';

  @override
  bool supports(String content) {
    final lower = content.toLowerCase();
    return lower.contains('[connection]') && lower.contains('host=');
  }

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    final sections = _parseIni(content);
    final connection = sections['connection'] ?? const <String, String>{};
    final auth = sections['user_authentication'] ?? const <String, String>{};
    final host = connection['host'] ?? '';
    if (host.isEmpty) return const [];
    final user = (auth['username'] ?? connection['username'] ?? '').replaceAll(
      '"',
      '',
    );
    final keyPath = auth['keyfilepath'] ?? '';
    final authentication = (auth['authentication'] ?? '').toLowerCase();

    ServerCredential? credential;
    if (authentication.contains('publickey')) {
      credential = _readKeyCredential(keyPath, baseDirectory);
    }
    return [
      ImportedConnection(
        name: host,
        host: host,
        port: int.tryParse(connection['port'] ?? '') ?? 22,
        username: user,
        credential: credential,
        connectionType: ServerConnectionType.ssh,
        source: name,
      ),
    ];
  }
}

/// VanDyke SecureCRT session files (`.ini`). Session passwords are encrypted
/// with a machine-bound key and cannot be decrypted portably; the connection
/// metadata and public-key file are imported.
class SecureCrtAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'SecureCRT';

  @override
  bool supports(String content) =>
      content.contains('[Sessions') && content.contains('Hostname');

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    String? host;
    String? user;
    String? keyPath;
    var port = 22;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('[') || line.startsWith('#')) {
        continue;
      }
      final match = RegExp(r'^[SDB]:"([^"]+)"=(.*)$').firstMatch(line);
      if (match == null) continue;
      final key = match.group(1)!.toLowerCase();
      final value = match.group(2)!.trim();
      switch (key) {
        case 'hostname':
          host = value;
        case 'username':
          user = value;
        case 'port':
          // `D:"Port"` is a hex dword (e.g. 00000016).
          port = int.tryParse(value, radix: 16) ?? int.tryParse(value) ?? 22;
        case 'publickeyfile':
          keyPath = value;
      }
    }
    if (host == null || host.isEmpty) return const [];
    return [
      ImportedConnection(
        name: host,
        host: host,
        port: port,
        username: user ?? '',
        credential: _readKeyCredential(keyPath ?? '', baseDirectory),
        connectionType: ServerConnectionType.ssh,
        source: name,
      ),
    ];
  }
}

/// MobaXterm session exports (`.mxtsessions`). The format carries no
/// passwords; folders become tags and the public-key path is imported when
/// readable. Only SSH sessions (icon 109) are imported.
class MobaXtermAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'MobaXterm';

  @override
  bool supports(String content) {
    final lower = content.toLowerCase();
    return lower.contains('[bookmarks') &&
        (lower.contains('subrep=') || lower.contains('#109#'));
  }

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    final connections = <ImportedConnection>[];
    var folder = '';
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        folder = '';
        continue;
      }
      if (line.toLowerCase().startsWith('subrep=')) {
        folder = line.substring(line.indexOf('=') + 1).trim();
        continue;
      }
      final equals = line.indexOf('=');
      if (equals <= 0) continue;
      final sessionName = line.substring(0, equals).trim();
      final value = line.substring(equals + 1).trim();
      final parsed = _parseSession(value, sessionName, folder, baseDirectory);
      if (parsed != null) connections.add(parsed);
    }
    return connections;
  }

  ImportedConnection? _parseSession(
    String value,
    String sessionName,
    String folder,
    String? baseDirectory,
  ) {
    if (!value.startsWith('#')) return null;
    final parts = value.split('#');
    // parts[1] is the session icon; 109 identifies SSH.
    if (parts.length < 3 || parts[1] != '109') return null;
    final group = parts[2].split('%');
    // group: 0=type, 1=host, 2=port, 3=username, 14=private key path.
    if (group.isEmpty || group[0] != '0') return null;
    final host = group.length > 1 ? group[1] : '';
    if (host.isEmpty) return null;
    final user = group.length > 3 && group[3] != '<default>' ? group[3] : '';
    final keyPath = group.length > 14
        ? group[14]
              .replaceAll('_CurrentDrive_', 'C:')
              .replaceAll('__PIPE__', '|')
        : '';
    return ImportedConnection(
      name: sessionName,
      host: host,
      port: group.length > 2 ? int.tryParse(group[2]) ?? 22 : 22,
      username: user,
      credential: _readKeyCredential(keyPath, baseDirectory),
      connectionType: ServerConnectionType.ssh,
      tags: folder.isEmpty ? const [] : [folder],
      source: name,
    );
  }
}

/// PuTTY session registry exports (`.reg`). PuTTY does not store SSH
/// passwords in sessions; host/port/username and the public-key file are
/// imported.
class PuTTYAdapter implements ConnectionImportAdapter {
  @override
  String get name => 'PuTTY';

  @override
  bool supports(String content) =>
      content.contains('SimonTatham') && content.contains('Sessions');

  @override
  List<ImportedConnection> parse(String content, {String? baseDirectory}) {
    final connections = <ImportedConnection>[];
    var sessionName = '';
    String? hostName;
    String? user;
    String? keyPath;
    var port = 22;

    void flush() {
      if (hostName == null || hostName!.isEmpty) return;
      var host = hostName!;
      final colon = host.lastIndexOf(':');
      if (colon > 0 && int.tryParse(host.substring(colon + 1)) != null) {
        port = int.parse(host.substring(colon + 1));
        host = host.substring(0, colon);
      }
      connections.add(
        ImportedConnection(
          name: sessionName.isEmpty ? host : sessionName,
          host: host,
          port: port,
          username: user ?? '',
          credential: _readKeyCredential(keyPath ?? '', baseDirectory),
          connectionType: ServerConnectionType.ssh,
          source: name,
        ),
      );
      sessionName = '';
      hostName = null;
      user = null;
      keyPath = null;
      port = 22;
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        flush();
        final match = RegExp(r'Sessions\\([^\]]+)\]$').firstMatch(line);
        final path = match?.group(1) ?? '';
        sessionName = path.contains(r'\')
            ? path.substring(path.lastIndexOf(r'\') + 1)
            : path;
        continue;
      }
      final match = RegExp(r'^"([^"]+)"=(.*)$').firstMatch(line);
      if (match == null) continue;
      final key = match.group(1)!;
      final value = match.group(2)!;
      switch (key) {
        case 'HostName':
          hostName = _regString(value);
        case 'UserName':
          user = _regString(value);
        case 'PortNumber':
          port = _regDword(value) ?? port;
        case 'PublicKeyFile':
          keyPath = _regString(value);
      }
    }
    flush();
    return connections;
  }
}

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

/// The user's home directory: `USERPROFILE` on Windows, `HOME` elsewhere.
/// Falls back to `HOMEDRIVE`+`HOMEPATH` on Windows when `USERPROFILE` is
/// unset. Returns null when nothing usable is set.
String? _homeDir() {
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) return profile;
    final drive = Platform.environment['HOMEDRIVE'];
    final path = Platform.environment['HOMEPATH'];
    if (drive != null && path != null) return '$drive$path';
  }
  final home = Platform.environment['HOME'];
  return (home != null && home.isNotEmpty) ? home : null;
}

/// Reads a resolved private-key file into a credential, or null when it is
/// unreadable or empty.
ServerCredential? _readKeyFile(String? resolvedPath) {
  if (resolvedPath == null) return null;
  try {
    final content = File(resolvedPath).readAsStringSync();
    if (content.trim().isEmpty) return null;
    return ServerCredential.privateKey(privateKey: content);
  } catch (_) {
    return null;
  }
}

/// Reads a private-key file named by [path] (resolved against
/// [baseDirectory]) into a credential, or null when the path is empty,
/// points at a file outside this machine, or is unreadable.
ServerCredential? _readKeyCredential(String path, String? baseDirectory) {
  if (path.isEmpty) return null;
  return _readKeyFile(_resolvePath(path, baseDirectory));
}

/// The OpenSSH default key files, tried in order when a `Host` block has no
/// explicit `IdentityFile` — mirrors what `ssh` does automatically.
const List<String> _defaultKeyFiles = [
  'id_ed25519',
  'id_ecdsa',
  'id_rsa',
  'id_dsa',
];

/// Reads the first existing OpenSSH default key in `~/.ssh` into a
/// credential, or null when none is readable. Used when an imported `Host`
/// block omits `IdentityFile`, matching `ssh`'s default-key behavior.
ServerCredential? _readDefaultKeyCredential() {
  final home = _homeDir();
  if (home == null) return null;
  for (final name in _defaultKeyFiles) {
    final cred = _readKeyFile('$home/.ssh/$name');
    if (cred != null) return cred;
  }
  return null;
}

/// Resolves a key path: `~/` expands to the home directory, relative paths
/// resolve against [baseDirectory] (the folder of the imported file), and
/// foreign Windows paths (e.g. `C:\...` on macOS) yield null.
///
/// Security: a third-party connection file is untrusted input, so a key path
/// in it is constrained to stop a crafted file from silently exfiltrating
/// arbitrary local files into the credential vault:
/// - `~/` may only resolve inside `$HOME/.ssh` (the standard key location).
///   Anything else under `~/` is rejected.
/// - relative paths may not escape [baseDirectory] via `..`.
/// A file the user deliberately placed next to the import, or their own
/// `~/.ssh/*` key, is still imported; exotic paths are refused rather than
/// silently copied.
String? _resolvePath(String path, String? baseDirectory) {
  final expanded = path.trim();
  if (expanded.isEmpty) return null;
  final home = _homeDir();
  final sshDir = home == null ? null : '$home/.ssh';
  if (expanded.startsWith('~/')) {
    if (sshDir == null) return null;
    final candidate = '$home/${expanded.substring(2)}';
    if (!_isWithinDirectory(candidate, sshDir)) return null;
    return candidate;
  }
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(expanded)) {
    // Drive-letter paths are native on Windows (e.g. the user's own
    // `C:\Users\me\.ssh\id_rsa`); elsewhere they are foreign (a macOS import
    // referencing a Windows path) and ignored. On Windows the key must
    // still live under the user's own `.ssh`.
    if (!Platform.isWindows || sshDir == null) return null;
    if (!_isWithinDirectory(expanded, sshDir)) return null;
    return expanded;
  }
  if (expanded.startsWith('/') || expanded.startsWith('\\')) {
    // Absolute paths are only followed when they point at the user's own
    // `~/.ssh` key directory, so a crafted file cannot name an arbitrary
    // local file for silent exfiltration.
    if (sshDir == null) return null;
    if (!_isWithinDirectory(expanded, sshDir)) return null;
    return expanded;
  }
  if (baseDirectory == null) return null;
  final candidate = '$baseDirectory/$expanded';
  if (!_isWithinDirectory(candidate, baseDirectory)) return null;
  return candidate;
}

/// True when [path] normalizes to a location inside [directory] with no `..`
/// escape. A lexical check — sufficient to reject traversal in imported key
/// paths, which are not expected to involve symlinks the importer controls.
bool _isWithinDirectory(String path, String directory) {
  String normalize(String p) {
    final segments = <String>[];
    for (final part in p.split(RegExp(r'[/\\]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(part);
    }
    return segments.join('/');
  }
  final normalized = normalize(path);
  final base = normalize(directory);
  if (base.isEmpty) return normalized.isNotEmpty;
  return normalized == base || normalized.startsWith('$base/');
}

/// Decodes a FinalShell password. Tries the modern head-seeded scheme first,
/// then the classic hardcoded-key scheme; returns null when neither produces
/// valid UTF-8, or when [encoded] is not base64.
String? _decodeFinalShellPassword(String encoded) {
  final trimmed = encoded.trim();
  if (trimmed.isEmpty) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(trimmed);
  } on FormatException {
    return null;
  }
  if (bytes.length >= 16) {
    final fromHead = _decryptFinalShellHeadScheme(bytes);
    if (fromHead != null) return fromHead;
  }
  final fromClassic = _decryptFinalShellClassic(bytes);
  if (fromClassic != null) return fromClassic;
  return null;
}

/// FinalShell 4.x: first 8 bytes seed a `java.util.Random` chain that
/// produces a DES key (MD5 of eight packed longs); the rest is DES-ECB.
String? _decryptFinalShellHeadScheme(Uint8List bytes) {
  final head = Uint8List.sublistView(bytes, 0, 8);
  final ciphertext = Uint8List.sublistView(bytes, 8);
  final key = _finalshellKeyFromHead(head);
  return _decryptAndValidate(key, ciphertext);
}

/// Older FinalShell: DES-ECB with the first 8 bytes of the hardcoded key.
String? _decryptFinalShellClassic(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length % 8 != 0) return null;
  return _decryptAndValidate(
    utf8.encode('Smart\$S!e2!etHu9y6'.substring(0, 8)),
    bytes,
  );
}

String? _decryptAndValidate(List<int> keyBytes, Uint8List ciphertext) {
  if (ciphertext.isEmpty || ciphertext.length % 8 != 0) return null;
  final key = keyBytes.length >= 8
      ? Uint8List.fromList(keyBytes.sublist(0, 8))
      : Uint8List.fromList(keyBytes);
  final des = DesBase();
  final workingKey = des.generateWorkingKey(false, key);
  final plain = Uint8List(ciphertext.length);
  for (var offset = 0; offset < ciphertext.length; offset += 8) {
    des.desFunc(workingKey, ciphertext, offset, plain, offset);
  }
  final padLength = plain[plain.length - 1];
  if (padLength < 1 || padLength > 8) return null;
  for (var i = plain.length - padLength; i < plain.length; i++) {
    if (plain[i] != padLength) return null;
  }
  try {
    return utf8.decode(
      Uint8List.sublistView(plain, 0, plain.length - padLength),
      allowMalformed: false,
    );
  } on FormatException {
    return null;
  }
}

/// Faithful port of the FinalShell `ranDomKey` derivation, itself a
/// translation of the Java code (java.util.Random semantics).
Uint8List _finalshellKeyFromHead(Uint8List head) {
  final divisorRandom = _JavaRandom(BigInt.from(_signedByte(head[5])));
  var divisor = divisorRandom.nextInt(127);
  if (divisor == 0) divisor = 1;
  final ks = BigInt.from(3680984568597093857) ~/ BigInt.from(divisor);
  final random = _JavaRandom(ks);
  final t = _signedByte(head[0]);
  for (var i = 0; i < t; i++) {
    random.nextLong();
  }
  final n = random.nextLong();
  final r2 = _JavaRandom(n);
  final longs = <BigInt>[
    BigInt.from(_signedByte(head[4])),
    r2.nextLong(),
    BigInt.from(_signedByte(head[7])),
    BigInt.from(_signedByte(head[3])),
    r2.nextLong(),
    BigInt.from(_signedByte(head[1])),
    random.nextLong(),
    BigInt.from(_signedByte(head[2])),
  ];
  final data = BytesBuilder(copy: false);
  for (final value in longs) {
    data.add(_int64BigEndian(value));
  }
  return Uint8List.fromList(md5.convert(data.takeBytes()).bytes);
}

/// Simulates `java.util.Random` exactly (JDK 8+ semantics, signed
/// overflow), using BigInt so it behaves identically on native and web.
class _JavaRandom {
  static const _multiplier = 0x5DEECE66D;
  static const _addend = 0xB;
  static final _mask48 = BigInt.from(0xFFFFFFFFFFFF);
  static final _mask64 = BigInt.from(0xFFFFFFFFFFFFFFFF);
  static final _uint64 = BigInt.from(1) << 64;
  static final _uint32 = BigInt.from(1) << 32;

  _JavaRandom(BigInt seed)
    : _seed = ((seed & _mask64) ^ BigInt.from(_multiplier)) & _mask48;

  BigInt _seed;

  int _next(int bits) {
    _seed = (_seed * BigInt.from(_multiplier) + BigInt.from(_addend)) & _mask48;
    var result = _seed >> (48 - bits);
    if (bits >= 32 && result >= BigInt.from(0x80000000)) {
      result -= _uint32;
    }
    return result.toInt();
  }

  int nextInt(int bound) {
    final m = bound - 1;
    var r = _next(31);
    if ((bound & m) == 0) {
      return _toInt32(bound * r) >> 31;
    }
    var u = r;
    r = u % bound;
    while (_toInt32(u - r + m) < 0) {
      u = _next(31);
      r = u % bound;
    }
    return r;
  }

  /// Java `((long) next(32)) << 32 + next(32)` with 64-bit wrap-around.
  BigInt nextLong() {
    var value = (BigInt.from(_next(32)) << 32) + BigInt.from(_next(32));
    value = value & _mask64;
    if (value >= BigInt.from(0x8000000000000000)) {
      value -= _uint64;
    }
    return value;
  }

  static int _toInt32(int value) {
    final wrapped = value & 0xFFFFFFFF;
    return wrapped >= 0x80000000 ? wrapped - 0x100000000 : wrapped;
  }
}

Uint8List _int64BigEndian(BigInt value) {
  final result = Uint8List(8);
  var remaining = value & BigInt.from(0xFFFFFFFFFFFFFFFF);
  for (var i = 7; i >= 0; i--) {
    result[i] = (remaining & BigInt.from(0xFF)).toInt();
    remaining = remaining >> 8;
  }
  return result;
}

int _signedByte(int value) => value >= 128 ? value - 256 : value;

bool _looksLikeBase64(String value) =>
    RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(value);

/// Parses an INI document into lowercase section → lowercase key → value.
Map<String, Map<String, String>> _parseIni(String content) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      current = sections.putIfAbsent(
        line.substring(1, line.length - 1).trim().toLowerCase(),
        () => <String, String>{},
      );
      continue;
    }
    final equals = line.indexOf('=');
    if (equals <= 0) continue;
    current?[line.substring(0, equals).trim().toLowerCase()] = line
        .substring(equals + 1)
        .trim();
  }
  return sections;
}

String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

int? _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

Object? _firstValue(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) return value;
  }
  return null;
}

String? _regString(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  // REG_EXPAND_SZ / REG_BINARY as comma-separated hex bytes.
  if (trimmed.startsWith('hex:') || trimmed.startsWith('hex(2):')) {
    final bytes = _hexBytes(trimmed.substring(trimmed.indexOf(':') + 1));
    return bytes.isEmpty
        ? null
        : ascii.decode(bytes, allowInvalid: true).trim();
  }
  return null;
}

int? _regDword(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('dword:')) {
    return int.tryParse(trimmed.substring(6), radix: 16);
  }
  if (trimmed.startsWith('hex:')) {
    // Little-endian dword bytes.
    final bytes = _hexBytes(trimmed.substring(4));
    if (bytes.length < 4) return null;
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }
  return null;
}

List<int> _hexBytes(String value) => [
  for (final part in value.split(',')) ?int.tryParse(part.trim(), radix: 16),
];
