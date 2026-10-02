import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Verbose diagnostics for MaidCafe connections.
///
/// The connection path is where credentials, cloud tickets and daemon policy
/// meet, and every one of them fails the same way from the outside — a socket
/// that never upgraded. These messages name what the app actually sent and what
/// the daemon actually answered, so a failure can be read instead of guessed.
///
/// On by default in debug builds and silent in release ones. [maidCafeLogCredentials]
/// adds the raw values, which is what makes "the daemon expects X, the app sent
/// Y" answerable on a machine the user already controls.
bool maidCafeVerboseLogging = kDebugMode;

/// Whether [maidCafeLog] also prints credential material.
///
/// Off by default: a redacted value is enough to tell two credentials apart,
/// and these messages reach the console, journald and crash logs.
bool maidCafeLogCredentials = false;

/// Prints one MaidCafe diagnostic line when [maidCafeVerboseLogging] is on.
void maidCafeLog(String message, {Object? error}) {
  if (!maidCafeVerboseLogging) return;
  debugPrint(
    error == null ? '[MaidCafe] $message' : '[MaidCafe] $message: $error',
  );
}

/// How a credential reads in a log: how long it is and a stable digest of it.
///
/// The digest is not a secret in reverse — it only has to be equal for equal
/// inputs, so two logs can be compared, or a log compared with a value read
/// from the daemon, without the credential itself being written down. The raw
/// value appears only when [maidCafeLogCredentials] is on.
String maidCafeDescribeCredential(String? secret) {
  if (secret == null) return 'none';
  if (secret.isEmpty) return 'empty';
  if (maidCafeLogCredentials) return '"$secret" (len=${secret.length})';
  return 'len=${secret.length} digest=${_maidCafeDigest(secret)}';
}

/// FNV-1a over the UTF-8 bytes, as 8 hex digits.
String _maidCafeDigest(String value) {
  var hash = 0x811c9dc5;
  for (final byte in value.codeUnits) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Describes a credential that may be present, for a log line.
String maidCafeDescribeSecret({
  required String? terminalSecret,
  required String? metricsSecret,
  String? cloudSecret,
}) {
  final parts = <String>[
    'terminal=${maidCafeDescribeCredential(terminalSecret)}',
    'metrics=${maidCafeDescribeCredential(metricsSecret)}',
  ];
  if (cloudSecret != null) {
    parts.add('cloud=${maidCafeDescribeCredential(cloudSecret)}');
  }
  return parts.join(' ');
}
