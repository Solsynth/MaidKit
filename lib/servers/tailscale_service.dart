import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tailscale/tailscale.dart';

import 'server_providers.dart';
import 'vault_service.dart';

/// Whether the embedded Tailscale runtime is available on this platform.
/// `package:tailscale` is POSIX-only today, so Windows and web are excluded.
bool get tailscaleSupported => Platform.isMacOS || Platform.isLinux;

bool _tailscaleInitialized = false;

/// Configures the embedded Tailscale node exactly once per process.
///
/// The state directory holds the node's WireGuard private key and must stay
/// out of cloud backups. The application-support directory is not synced by
/// iCloud on macOS and is the location recommended by the package.
Future<void> ensureTailscaleInitialized() async {
  if (_tailscaleInitialized) return;
  if (!tailscaleSupported) {
    throw const TailscaleUsageException(
      'Tailscale is not supported on this platform.',
    );
  }
  final support = await getApplicationSupportDirectory();
  Tailscale.init(
    stateDir: p.join(support.path, 'tailscale'),
    appId: 'dev.solsynth.maid',
  );
  _tailscaleInitialized = true;
}

/// The singleton embedded node, typed as [TailscaleClient] so tests can
/// substitute a fake without loading the native runtime.
final tailscaleClientProvider = Provider<TailscaleClient>((ref) {
  return Tailscale.instance;
});

/// Thin wrapper that ensures the runtime is initialized before each call.
class TailscaleService {
  TailscaleService(this._client, this._vault);

  final TailscaleClient _client;
  final VaultService _vault;

  /// Hostname this app's node uses on the tailnet.
  static const hostname = 'MaidKit';

  /// Brings the node up. [authKey] is required on first registration; later
  /// launches reconnect with the vault-encrypted key when one is available.
  Future<TailscaleStatus> up({String? authKey}) async {
    await ensureTailscaleInitialized();
    final providedKey = authKey?.trim();
    final key = providedKey == null || providedKey.isEmpty
        ? await _vault.tailscaleAuthKey()
        : providedKey;
    final status = await _client.up(hostname: hostname, authKey: key);
    if (providedKey != null && providedKey.isNotEmpty) {
      await _vault.storeTailscaleAuthKey(providedKey);
    }
    return status;
  }

  Future<bool> hasStoredAuthKey() async =>
      (await _vault.tailscaleAuthKey()) != null;

  Future<TailscaleStatus> status() async {
    await ensureTailscaleInitialized();
    return _client.status();
  }

  Future<List<TailscaleNode>> nodes() async {
    await ensureTailscaleInitialized();
    return _client.nodes();
  }

  Future<void> logout() async {
    await ensureTailscaleInitialized();
    await _client.logout();
    await _vault.clearTailscaleAuthKey();
  }

  Stream<NodeState> get onStateChange => _client.onStateChange;
  Stream<TailscaleRuntimeError> get onError => _client.onError;
}

final tailscaleServiceProvider = Provider<TailscaleService>((ref) {
  return TailscaleService(
    ref.watch(tailscaleClientProvider),
    ref.watch(vaultServiceProvider),
  );
});
