import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:async/async.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/agent/mcp_client.dart';
import 'package:maid_kit/agent/mcp_repository.dart';
import 'package:maid_kit/agent/skill_repository.dart';
import 'package:maid_kit/agent/skill_registry.dart';
import 'package:maid_kit/agent/agent_repository.dart';
import 'package:maid_kit/agent/agent_model_catalog.dart';
import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/agent/agent_personality.dart';
import 'package:maid_kit/agent/agent_run_policy.dart';
import 'package:maid_kit/agent/agent_selection.dart';
import 'package:maid_kit/agent/billing_service.dart';
import 'package:maid_kit/agent/personality_service.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'app_theme_preferences.dart';
import 'ghostty_terminal_session_adapter.dart';
import 'cloud_sync_service.dart';
import 'maidcafe_preferences.dart';
import 'maidcafe_service.dart';
import 'maidcafe_metoer.dart';
import 'maidcafe_session_registry.dart';
import 'local_connection_manager.dart';
import 'local_machine_preferences.dart';
import 'metrics_refresh_preferences.dart';
import 'port_forwarding_models.dart';
import 'privacy_preferences.dart';
import 'server_repository.dart';
import 'server_metrics_refresh_scheduler.dart';
import 'serial_port_client.dart';
import 'serial_connection_manager.dart';
import 'ssh_connection_manager.dart';
import 'server_models.dart';
import 'terminal_session_adapter.dart';
import 'terminal_adapter_preferences.dart';
import 'terminal_color_scheme.dart';
import 'startup_connection_preferences.dart';
import 'vault_service.dart';
import 'vault_file_storage.dart';

/// The current vault's label (or file name), sanitized for use in exported
/// file names. Falls back to "vault" when no vault is active or the label is
/// empty.
String exportFileNamePrefix(WidgetRef ref) {
  final path = ref.read(activeVaultFileProvider);
  final label = path == null
      ? null
      : ref.read(vaultLabelsProvider)[path] ??
            ref.read(vaultFileStorageProvider).fileName(path);
  final sanitized = (label ?? 'vault')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return sanitized.isEmpty ? 'vault' : sanitized;
}

/// Local timestamp for exported file names, e.g. `20260806-143000`.
String exportTimestamp() =>
    DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());

final vaultFileStorageProvider = Provider<VaultFileStorage>(
  (ref) => VaultFileStorage(),
);

final cloudSyncServiceForVaultProvider =
    Provider.family<CloudSyncService, String>((ref, vaultId) {
      return CloudSyncService(vaultId: vaultId);
    });

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return ref.watch(
    cloudSyncServiceForVaultProvider(
      ref.watch(activeVaultFileProvider) ?? 'maid_kit',
    ),
  );
});

final cloudSyncConfigurationProvider = FutureProvider<CloudSyncConfiguration?>((
  ref,
) {
  return ref.watch(cloudSyncServiceProvider).configuration();
});

final cloudSyncConfigurationForVaultProvider =
    FutureProvider.family<CloudSyncConfiguration?, String>((ref, vaultId) {
      return ref
          .watch(cloudSyncServiceForVaultProvider(vaultId))
          .configuration();
    });

final cloudUserProvider = FutureProvider<CloudUser?>((ref) {
  return ref.watch(cloudSyncServiceProvider).currentUser();
});

final cloudWorkspacesProvider = FutureProvider<List<CloudWorkspace>>((ref) {
  return ref.watch(cloudSyncServiceProvider).listWorkspaces();
});
final maidCafeSettingsProvider = Provider<MaidCafeSettings>(
  (ref) => InMemoryMaidCafeSettings(),
);

final maidCafeCloudUrlProvider =
    NotifierProvider<MaidCafeCloudUrlNotifier, String>(
      MaidCafeCloudUrlNotifier.new,
    );

class MaidCafeCloudUrlNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(maidCafeSettingsProvider).cloudUrl;

  Future<void> save(String value) async {
    await ref.read(maidCafeSettingsProvider).saveCloudUrl(value);
    state = ref.read(maidCafeSettingsProvider).cloudUrl;
  }
}

final maidCafeWorkspaceIdProvider =
    NotifierProvider<MaidCafeWorkspaceIdNotifier, String?>(
      MaidCafeWorkspaceIdNotifier.new,
    );

class MaidCafeWorkspaceIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(maidCafeSettingsProvider).workspaceId;

  Future<void> save(String? value) async {
    await ref.read(maidCafeSettingsProvider).saveWorkspaceId(value);
    state = ref.read(maidCafeSettingsProvider).workspaceId;
  }
}

final maidCafeMetoerClientProvider = Provider<MaidCafeMetoerClient>((ref) {
  return MaidCafeMetoerClient(
    baseUrl: CloudSyncService.apiBase,
    accessToken: () => ref.watch(cloudSyncServiceProvider).accessToken(),
  );
});

final maidCafeMetoerNotificationsProvider =
    FutureProvider<List<MaidCafeMetoerNotification>>((ref) async {
      return (await ref.watch(maidCafeMetoerClientProvider).list()).items;
    });

final maidCafeMetoerUnreadCountProvider = FutureProvider<int>(
  (ref) => ref.watch(maidCafeMetoerClientProvider).unreadCount(),
);

final maidCafeServiceProvider = Provider<MaidCafeService>((ref) {
  return MaidCafeService(
    baseUrl: ref.watch(maidCafeCloudUrlProvider),
    cloudSync: ref.watch(cloudSyncServiceProvider),
  );
});

final maidCafeDaemonsProvider =
    FutureProvider.family<List<MaidCafeDaemon>, String>((ref, workspaceId) {
      return ref
          .watch(maidCafeServiceProvider)
          .listDaemons(workspaceId: workspaceId);
    });

final maidCafeMetricsProvider =
    FutureProvider.family<List<MaidCafeMetric>, String>((ref, daemonId) {
      return ref.watch(maidCafeServiceProvider).listMetrics(daemonId);
    });

final maidCafeCloudActionsProvider =
    FutureProvider.family<List<MaidCafeCloudAction>, String>((ref, daemonId) {
      return ref.watch(maidCafeServiceProvider).listActions(daemonId);
    });

final maidCafeCredentialsProvider = FutureProvider<List<MaidCafeCredential>>((
  ref,
) {
  return ref.watch(maidCafeServiceProvider).listCredentials();
});

final personalityBillingPolicyProvider = FutureProvider<BillingPolicy?>((
  ref,
) async {
  final accessToken = await ref.watch(cloudSyncServiceProvider).accessToken();
  if (accessToken == null) return null;
  return const PersonalityBillingService().getMyBilling(
    baseUrl: PersonalityBillingService.productionBaseUrl,
    accessToken: accessToken,
  );
});

final personalityAgentsProvider = FutureProvider<List<PersonalityAgent>>((
  ref,
) async {
  final accessToken = await ref.watch(cloudSyncServiceProvider).accessToken();
  if (accessToken == null) return const [];
  try {
    return await const PersonalityService().listAgents(
      baseUrl: PersonalityService.productionBaseUrl,
      accessToken: accessToken,
    );
  } catch (_) {
    return const [];
  }
});

final databaseProvider = Provider.autoDispose<AppDatabase>((ref) {
  final database = AppDatabase(filePath: ref.watch(activeVaultFileProvider));
  ref.onDispose(database.close);
  return database;
});

const _activeVaultFilePreference = 'active_vault_file';
const _vaultFilesPreference = 'vault_files';
const _vaultLabelsPreference = 'vault_labels';

/// Moves the pre-multi-vault app database into a managed vault location once.
/// Platforms that support external vaults use the user-visible Documents
/// location so existing data is also available to synchronization tools;
/// restricted platforms keep the migrated vault in private application-support
/// storage.
///
/// The original database lived at the app default location under the fixed
/// "maid_kit" vault id. Cloud sync, biometric and sync-passphrase keys are
/// moved to the new path-based vault id so existing bindings keep working.
Future<void> migrateLegacyVault({required String defaultName}) async {
  final preferences = await SharedPreferences.getInstance();
  final documents = await getApplicationDocumentsDirectory();
  final legacy = File(
    '${documents.path}${Platform.pathSeparator}maid_kit.sqlite',
  );
  if (!await legacy.exists()) return;

  final database = AppDatabase(filePath: legacy.path);
  final hasVault = await database.select(database.vaultMetadata).get();
  await database.close();
  if (hasVault.isEmpty) return;

  final managedPath = await VaultFileStorage().moveVault(
    legacy.path,
    directoryPath: externalVaultsSupported ? documents.path : null,
    name: defaultName,
  );

  final storage = const FlutterSecureStorage();
  for (final prefix in [
    'maidkit_cloud_sync',
    'maidkit_vault_data_key',
    'maidkit_vault_sync_passphrase',
  ]) {
    final oldKey = '${prefix}_${base64UrlEncode(utf8.encode('maid_kit'))}';
    final newKey = '${prefix}_${base64UrlEncode(utf8.encode(managedPath))}';
    try {
      final value = await storage.read(key: oldKey);
      if (value != null) {
        await storage.write(key: newKey, value: value);
        await storage.delete(key: oldKey);
      }
    } catch (_) {
      // Keychain migration is best-effort; the sync passphrase also lives in
      // the vault metadata and biometric unlock can be re-enabled with it.
    }
  }

  final storedFiles =
      preferences.getStringList(_vaultFilesPreference) ?? const [];
  if (!storedFiles.contains(managedPath)) {
    await preferences.setStringList(_vaultFilesPreference, [
      managedPath,
      ...storedFiles,
    ]);
  }
  final active = preferences.getString(_activeVaultFilePreference);
  if (active == null || active.isEmpty) {
    await preferences.setString(_activeVaultFilePreference, managedPath);
  }
  final rawLabels = preferences.getString(_vaultLabelsPreference);
  final labels = <String, String>{};
  if (rawLabels != null) {
    try {
      final values = Map<String, dynamic>.from(jsonDecode(rawLabels) as Map);
      labels.addAll(
        values.map((key, value) => MapEntry(key, value.toString())),
      );
    } catch (_) {
      // Ignore malformed labels and fall back to a clean map.
    }
  }
  labels[managedPath] = defaultName;
  await preferences.setString(_vaultLabelsPreference, jsonEncode(labels));

  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${legacy.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

final vaultLabelsProvider =
    NotifierProvider<VaultLabelsNotifier, Map<String, String>>(
      VaultLabelsNotifier.new,
    );

class VaultLabelsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    _restore();
    return const {};
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_vaultLabelsPreference);
    if (raw == null) return;
    try {
      final values = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      state = values.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      await preferences.remove(_vaultLabelsPreference);
    }
  }

  Future<void> rename(String vaultId, String name) async {
    final normalized = name.trim();
    final updated = {...state};
    if (normalized.isEmpty) {
      updated.remove(vaultId);
    } else {
      updated[vaultId] = normalized;
    }
    state = updated;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_vaultLabelsPreference, jsonEncode(state));
  }

  Future<void> remove(String vaultId) async {
    state = {...state}..remove(vaultId);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_vaultLabelsPreference, jsonEncode(state));
  }
}

/// The database file backing the currently selected vault. A null value keeps
/// using the original MaidKit database so existing users migrate seamlessly.
final activeVaultFileProvider =
    NotifierProvider<ActiveVaultFileNotifier, String?>(
      ActiveVaultFileNotifier.new,
    );

class ActiveVaultFileNotifier extends Notifier<String?> {
  @override
  String? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final path = preferences.getString(_activeVaultFilePreference);
    if (path != null && path.isNotEmpty) {
      try {
        final storage = ref.read(vaultFileStorageProvider);
        final managedPath = await storage.importVault(path);
        await ref.read(vaultFilesProvider.notifier).remember(managedPath);
        state = managedPath;
        await preferences.setString(_activeVaultFilePreference, managedPath);
      } on FileSystemException {
        await preferences.remove(_activeVaultFilePreference);
      }
    }
  }

  Future<void> select(String? path) async {
    if (path != null) {
      final storage = ref.read(vaultFileStorageProvider);
      if (!externalVaultsSupported && await storage.isExternalPath(path)) {
        throw FileSystemException(
          'External managed vaults are not supported on this platform.',
          path,
        );
      }
      await ref.read(vaultFilesProvider.notifier).remember(path);
    }
    state = path;
    final preferences = await SharedPreferences.getInstance();
    if (path == null) {
      await preferences.remove(_activeVaultFilePreference);
    } else {
      await preferences.setString(_activeVaultFilePreference, path);
    }
  }
}

/// Vault database files known to MaidKit. The original app database is a
/// separate built-in option and is therefore not included in this list.
final vaultFilesProvider = NotifierProvider<VaultFilesNotifier, List<String>>(
  VaultFilesNotifier.new,
);
final vaultExternalPathProvider = FutureProvider.family<bool, String>((
  ref,
  path,
) {
  return ref.read(vaultFileStorageProvider).isExternalPath(path);
});

class VaultFilesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _restore();
    return const [];
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_vaultFilesPreference) ?? const [];
    final managedPaths = <String>[];
    final storage = ref.read(vaultFileStorageProvider);
    for (final path in stored) {
      try {
        final managedPath = await storage.importVault(path);
        if (!managedPaths.contains(managedPath)) managedPaths.add(managedPath);
      } on FileSystemException {
        // Missing or unsupported vault files are no longer selectable.
      }
    }
    state = [
      ...managedPaths,
      ...state.where((path) => !managedPaths.contains(path)),
    ];
    await preferences.setStringList(_vaultFilesPreference, state);
  }

  Future<void> remember(String path) async {
    state = [path, ...state.where((value) => value != path)];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_vaultFilesPreference, state);
  }

  Future<void> forget(String path) async {
    state = state.where((value) => value != path).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_vaultFilesPreference, state);
  }
}

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(
    ref.watch(databaseProvider),
    ref.watch(vaultServiceProvider),
  );
});

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(
    ref.watch(databaseProvider),
    ref.watch(vaultServiceProvider),
  );
});

final agentModelCatalogProvider = Provider<AgentModelCatalog>(
  (ref) => AgentModelCatalog(),
);

final agentConfiguredProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(agentRepositoryProvider)
      .watchProviders()
      .map((providers) => providers.isNotEmpty);
});

final agentProvidersProvider = StreamProvider<List<AgentProvider>>((ref) {
  return ref.watch(agentRepositoryProvider).watchProviders();
});

final agentProviderModelsProvider =
    StreamProvider.family<List<AgentProviderModel>, int>((ref, providerId) {
      return ref.watch(agentRepositoryProvider).watchModels(providerId);
    });

final conversationStoreProvider = Provider<AgentConversationStore>((ref) {
  return AgentConversationStore();
});

final agentConversationsProvider = StreamProvider<List<AgentConversation>>(
  (ref) => ref.watch(conversationStoreProvider).watchConversations(),
);

final mcpRepositoryProvider = Provider<McpRepository>((ref) {
  return McpRepository(ref.watch(databaseProvider));
});

final mcpServersProvider = StreamProvider<List<McpServer>>((ref) {
  return ref.watch(mcpRepositoryProvider).watchAll();
});

final skillRepositoryProvider = Provider<SkillRepository>((ref) {
  return SkillRepository(ref.watch(databaseProvider));
});

final agentSkillsProvider = StreamProvider<List<AgentSkill>>((ref) {
  return ref.watch(skillRepositoryProvider).watchAll();
});

final skillRegistryClientProvider = Provider<SkillRegistryClient>((ref) {
  return SkillRegistryClient();
});

/// Owns live MCP server processes for the whole app session. Processes are
/// killed when the provider is disposed (app teardown) or a server is
/// deleted, disabled, or edited.
final mcpClientManagerProvider = Provider<McpClientManager>((ref) {
  final manager = McpClientManager();
  ref.onDispose(manager.disposeAll);
  return manager;
});

final agentSelectionProvider =
    AsyncNotifierProvider<AgentSelectionNotifier, AgentSelectionSettings>(
      AgentSelectionNotifier.new,
    );

class AgentSelectionNotifier extends AsyncNotifier<AgentSelectionSettings> {
  @override
  Future<AgentSelectionSettings> build() async =>
      AgentSelectionPreferences.load();

  Future<void> select({int? providerId, int? modelId}) async {
    final settings = state.value ?? await build();
    await settings.saveSelection(providerId: providerId, modelId: modelId);
    state = AsyncData(settings);
  }
}

final agentRunPolicyProvider =
    AsyncNotifierProvider<AgentRunPolicyNotifier, AgentRunPolicy>(
      AgentRunPolicyNotifier.new,
    );

class AgentRunPolicyNotifier extends AsyncNotifier<AgentRunPolicy> {
  @override
  Future<AgentRunPolicy> build() async {
    return (await AgentRunPolicyPreferences.load()).policy;
  }

  Future<void> setPolicy(AgentRunPolicy policy) async {
    await AgentRunPolicyPreferences.load().then((settings) {
      return settings.savePolicy(policy);
    });
    state = AsyncData(policy);
  }
}

final agentPersonalityProvider =
    AsyncNotifierProvider<AgentPersonalityNotifier, String>(
      AgentPersonalityNotifier.new,
    );

class AgentPersonalityNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async =>
      (await AgentPersonalityPreferences.load()).personality;

  Future<void> setPersonality(String personality) async {
    await AgentPersonalityPreferences.load().then((settings) {
      return settings.savePersonality(personality);
    });
    state = AsyncData(personality.trim());
  }
}

final agentPersonalityAgentProvider =
    AsyncNotifierProvider<AgentPersonalityAgentNotifier, String>(
      AgentPersonalityAgentNotifier.new,
    );

class AgentPersonalityAgentNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async =>
      (await AgentPersonalityAgentPreferences.load()).agentId;

  Future<void> setAgentId(String agentId) async {
    final normalized = agentId.trim();
    await AgentPersonalityAgentPreferences.load().then((settings) {
      return settings.saveAgentId(normalized);
    });
    state = AsyncData(
      normalized.isEmpty
          ? AgentPersonalityAgentPreferences.defaultAgentId
          : normalized,
    );
  }
}

final savedCredentialsProvider = StreamProvider<List<SavedCredential>>((ref) {
  return ref.watch(serverRepositoryProvider).watchCredentials();
});

final vaultServiceProvider = Provider<VaultService>((ref) {
  return VaultService(
    ref.watch(databaseProvider),
    vaultId: ref.watch(activeVaultFileProvider) ?? 'maid_kit',
  );
});

final vaultOpenTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

final vaultExistsProvider = FutureProvider<bool>((ref) {
  return ref
      .watch(vaultServiceProvider)
      .hasVault()
      .timeout(ref.watch(vaultOpenTimeoutProvider));
}, retry: (_, _) => null);

final biometricUnlockEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(vaultServiceProvider).isBiometricUnlockEnabled();
});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(appThemeSettingsProvider).themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(appThemeSettingsProvider).saveThemeMode(mode);
    state = mode;
  }
}

final appThemeSettingsProvider = Provider<AppThemeSettings>(
  (ref) => InMemoryAppThemeSettings(),
);

final appSeedColorProvider = NotifierProvider<AppSeedColorNotifier, Color>(
  AppSeedColorNotifier.new,
);

class AppSeedColorNotifier extends Notifier<Color> {
  @override
  Color build() => ref.read(appThemeSettingsProvider).seedColor;

  Future<void> setSeedColor(Color color) async {
    await ref.read(appThemeSettingsProvider).saveSeedColor(color);
    state = color;
  }
}

final dashboardCompactViewProvider =
    NotifierProvider<DashboardCompactViewNotifier, bool>(
      DashboardCompactViewNotifier.new,
    );

class DashboardCompactViewNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(appThemeSettingsProvider).compactDashboard;

  Future<void> setCompact(bool compact) async {
    await ref.read(appThemeSettingsProvider).saveCompactDashboard(compact);
    state = compact;
  }
}

final terminalSessionAdapterOptionsProvider =
    Provider<List<TerminalSessionAdapterOption>>((ref) {
      final cursorAnimationEnabled = ref.watch(cursorAnimationEnabledProvider);
      final colorScheme = ref.watch(terminalColorSchemeProvider);
      final terminalFontFamily = ref.watch(terminalFontFamilyProvider);
      final transparentBackground = ref.watch(
        transparentTerminalBackgroundProvider,
      );
      return [
        TerminalSessionAdapterOption(
          id: 'ghostty',
          label: 'Ghostty',
          description: 'The default libghostty-vt renderer for new terminals.',
          factory: GhosttyTerminalSessionAdapterFactory(
            cursorAnimationEnabled: cursorAnimationEnabled,
            colorScheme: colorScheme,
            transparentBackground: transparentBackground,
            fontFamily: terminalFontFamily,
          ),
        ),
        TerminalSessionAdapterOption(
          id: 'xterm',
          label: 'xterm',
          description: 'The built-in Flutter fallback renderer.',
          factory: XtermTerminalSessionAdapterFactory(
            colorScheme: colorScheme,
            transparentBackground: transparentBackground,
            fontFamily: terminalFontFamily,
          ),
        ),
      ];
    });

final terminalAdapterPreferencesProvider = Provider<TerminalAdapterSettings>(
  (ref) => InMemoryTerminalAdapterSettings(),
);

final startupConnectionSettingsProvider = Provider<StartupConnectionSettings>(
  (ref) => InMemoryStartupConnectionSettings(),
);

final metricsRefreshSettingsProvider = Provider<MetricsRefreshSettings>(
  (ref) => InMemoryMetricsRefreshSettings(),
);

final privacySettingsProvider = Provider<PrivacySettings>(
  (ref) => InMemoryPrivacySettings(),
);

final hideServerAddressesProvider =
    NotifierProvider<HideServerAddressesNotifier, bool>(
      HideServerAddressesNotifier.new,
    );

class HideServerAddressesNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(privacySettingsProvider).hideServerAddresses;

  Future<void> setEnabled(bool value) async {
    await ref.read(privacySettingsProvider).saveHideServerAddresses(value);
    state = value;
  }
}

final localMachineSettingsProvider = Provider<LocalMachineSettings>(
  (ref) => InMemoryLocalMachineSettings(),
);

final localMachineEnabledProvider =
    NotifierProvider<LocalMachineEnabledNotifier, bool>(
      LocalMachineEnabledNotifier.new,
    );

class LocalMachineEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(localMachineSettingsProvider).localMachineEnabled;

  Future<void> setEnabled(bool value) async {
    await ref.read(localMachineSettingsProvider).saveLocalMachineEnabled(value);
    state = value;
    // Collect stats as soon as the toggle turns on rather than waiting for
    // the next scheduled tick (up to the background refresh interval).
    if (value && localMachineSupported) {
      unawaited(ref.read(localConnectionManagerProvider).refreshNow());
    }
  }
}

final serverMetricsRefreshIntervalProvider =
    NotifierProvider<ServerMetricsRefreshIntervalNotifier, Duration>(
      ServerMetricsRefreshIntervalNotifier.new,
    );

class ServerMetricsRefreshIntervalNotifier extends Notifier<Duration> {
  @override
  Duration build() =>
      ref.read(metricsRefreshSettingsProvider).backgroundInterval;

  Future<void> setInterval(Duration value) async {
    await ref
        .read(metricsRefreshSettingsProvider)
        .saveBackgroundInterval(value);
    state = value;
  }
}

final focusedServerRefreshIntervalProvider =
    NotifierProvider<FocusedServerRefreshIntervalNotifier, Duration>(
      FocusedServerRefreshIntervalNotifier.new,
    );

class FocusedServerRefreshIntervalNotifier extends Notifier<Duration> {
  @override
  Duration build() => ref.read(metricsRefreshSettingsProvider).focusedInterval;

  Future<void> setInterval(Duration value) async {
    await ref.read(metricsRefreshSettingsProvider).saveFocusedInterval(value);
    state = value;
  }
}

final focusedServerIdProvider = NotifierProvider<FocusedServerNotifier, int?>(
  FocusedServerNotifier.new,
);

class FocusedServerNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void focus(int serverId) => state = serverId;

  void clear(int serverId) {
    if (state == serverId) state = null;
  }
}

final connectOnStartupProvider =
    NotifierProvider<ConnectOnStartupNotifier, bool>(
      ConnectOnStartupNotifier.new,
    );

class ConnectOnStartupNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(startupConnectionSettingsProvider).connectOnStartup;

  Future<void> setEnabled(bool value) async {
    await ref
        .read(startupConnectionSettingsProvider)
        .saveConnectOnStartup(value);
    state = value;
  }
}

final selectedTerminalSessionAdapterProvider =
    NotifierProvider<SelectedTerminalSessionAdapterNotifier, String>(
      SelectedTerminalSessionAdapterNotifier.new,
    );

class SelectedTerminalSessionAdapterNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.read(terminalAdapterPreferencesProvider).selectedAdapterId;

  Future<void> select(String adapterId) async {
    await ref
        .read(terminalAdapterPreferencesProvider)
        .saveSelectedAdapterId(adapterId);
    state = adapterId;
  }
}

final cursorAnimationEnabledProvider =
    NotifierProvider<CursorAnimationEnabledNotifier, bool>(
      CursorAnimationEnabledNotifier.new,
    );

class CursorAnimationEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(terminalAdapterPreferencesProvider).cursorAnimationEnabled;

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(terminalAdapterPreferencesProvider)
        .saveCursorAnimationEnabled(enabled);
    state = enabled;
  }
}

final terminalBrandingEnvironmentEnabledProvider =
    NotifierProvider<TerminalBrandingEnvironmentEnabledNotifier, bool>(
      TerminalBrandingEnvironmentEnabledNotifier.new,
    );

class TerminalBrandingEnvironmentEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(terminalAdapterPreferencesProvider).brandingEnvironmentEnabled;

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(terminalAdapterPreferencesProvider)
        .saveBrandingEnvironmentEnabled(enabled);
    state = enabled;
  }
}

final terminalFontFamilyProvider =
    NotifierProvider<TerminalFontFamilyNotifier, String>(
      TerminalFontFamilyNotifier.new,
    );

class TerminalFontFamilyNotifier extends Notifier<String> {
  @override
  String build() {
    final value = TerminalFonts.sanitize(
      ref.read(terminalAdapterPreferencesProvider).terminalFontFamily,
    );
    unawaited(_loadFont(value));
    return value;
  }

  Future<void> setFontFamily(String family) async {
    final value = TerminalFonts.sanitize(family);
    await _loadFont(value);
    await ref
        .read(terminalAdapterPreferencesProvider)
        .saveTerminalFontFamily(value);
    state = value;
  }

  Future<void> _loadFont(String family) async {
    try {
      await SystemFonts().loadFont(family);
    } on Object {
      // Font not available on this system; rendering falls back.
    }
  }
}

final availableTerminalFontsProvider = FutureProvider<List<TerminalFontOption>>(
  (ref) async {
    final options = TerminalFonts.dedupe(SystemFonts().getFontList());
    final defaultOption = TerminalFontOption(
      label: TerminalFonts.defaultFamily,
      family: TerminalFonts.defaultFamily,
    );
    if (!options.any(
      (option) => option.family == TerminalFonts.defaultFamily,
    )) {
      options.insert(0, defaultOption);
    }
    final persisted = ref.read(terminalFontFamilyProvider);
    if (!options.any((option) => option.family == persisted)) {
      options.insert(
        0,
        TerminalFontOption(label: persisted, family: persisted),
      );
    }
    return List.unmodifiable(options);
  },
);

final monospaceTerminalFontsOnlyProvider =
    NotifierProvider<MonospaceTerminalFontsOnlyNotifier, bool>(
      MonospaceTerminalFontsOnlyNotifier.new,
    );

class MonospaceTerminalFontsOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool enabled) => state = enabled;
}

final platformBrightnessProvider =
    NotifierProvider<PlatformBrightnessNotifier, Brightness>(
      PlatformBrightnessNotifier.new,
    );

class PlatformBrightnessNotifier extends Notifier<Brightness> {
  @override
  Brightness build() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    dispatcher.onPlatformBrightnessChanged = () {
      state = dispatcher.platformBrightness;
    };
    ref.onDispose(() => dispatcher.onPlatformBrightnessChanged = null);
    return dispatcher.platformBrightness;
  }
}

/// The brightness the app actually renders in, honoring the theme mode and
/// falling back to the OS setting for `ThemeMode.system`.
final appBrightnessProvider = Provider<Brightness>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.light) return Brightness.light;
  if (mode == ThemeMode.dark) return Brightness.dark;
  return ref.watch(platformBrightnessProvider);
});

final terminalLightThemeProvider =
    NotifierProvider<TerminalLightThemeNotifier, TerminalColorScheme>(
      TerminalLightThemeNotifier.new,
    );

class TerminalLightThemeNotifier extends Notifier<TerminalColorScheme> {
  @override
  TerminalColorScheme build() =>
      ref.read(terminalAdapterPreferencesProvider).lightTheme;

  Future<void> save(TerminalColorScheme theme) async {
    await ref.read(terminalAdapterPreferencesProvider).saveLightTheme(theme);
    state = theme;
  }
}

final terminalDarkThemeProvider =
    NotifierProvider<TerminalDarkThemeNotifier, TerminalColorScheme>(
      TerminalDarkThemeNotifier.new,
    );

class TerminalDarkThemeNotifier extends Notifier<TerminalColorScheme> {
  @override
  TerminalColorScheme build() =>
      ref.read(terminalAdapterPreferencesProvider).darkTheme;

  Future<void> save(TerminalColorScheme theme) async {
    await ref.read(terminalAdapterPreferencesProvider).saveDarkTheme(theme);
    state = theme;
  }
}

/// The terminal palette that matches the current app brightness.
final terminalColorSchemeProvider = Provider<TerminalColorScheme>((ref) {
  final brightness = ref.watch(appBrightnessProvider);
  return brightness == Brightness.light
      ? ref.watch(terminalLightThemeProvider)
      : ref.watch(terminalDarkThemeProvider);
});

final terminalSessionAdapterFactoryProvider =
    Provider<TerminalSessionAdapterFactory>((ref) {
      final options = ref.watch(terminalSessionAdapterOptionsProvider);
      final selectedId = ref.watch(selectedTerminalSessionAdapterProvider);
      return options
              .where((option) => option.id == selectedId)
              .firstOrNull
              ?.factory ??
          options.first.factory;
    });

final connectionManagerProvider = Provider<SshConnectionManager>((ref) {
  final manager = SshConnectionManager(
    () => ref.read(terminalSessionAdapterFactoryProvider),
    brandingEnvironmentEnabled: () =>
        ref.read(terminalBrandingEnvironmentEnabledProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Shares one MaidCafe session (and one SSH port forward) per server across
/// the Activity, Processes, Containers, Systemd and MaidCafe-management tabs.
final maidCafeSessionRegistryProvider = Provider<MaidCafeSessionRegistry>((
  ref,
) {
  return MaidCafeSessionRegistry(
    manager: ref.watch(connectionManagerProvider),
    serverRepository: ref.watch(serverRepositoryProvider),
  );
});

/// The shared native serial-port client.
final serialPortClientProvider = Provider<SerialPortClient>(
  (ref) => SerialPortClient(),
);

final serialConnectionManagerProvider = Provider<SerialConnectionManager>((
  ref,
) {
  final manager = SerialConnectionManager(
    () => ref.read(terminalSessionAdapterFactoryProvider),
    serialClient: ref.watch(serialPortClientProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// The virtual "this computer" server shown on the dashboard when local
/// machine management is enabled. It is deliberately not persisted: it has no
/// credentials, must not leak into cloud sync, and can never collide with a
/// stored row (its id is 0).
final localMachineServerProvider = Provider<Server>((ref) {
  String hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'localhost';
    }
  }

  return Server(
    id: localMachineServerId,
    name: hostname(),
    host: '127.0.0.1',
    port: 22,
    username: Platform.environment['USER'] ?? '',
    collectStats: true,
    collectSystemInfo: true,
    connectionType: ServerConnectionType.local.name,
  );
});

final localConnectionManagerProvider = Provider<LocalConnectionManager>((ref) {
  final manager = LocalConnectionManager(
    () => ref.read(terminalSessionAdapterFactoryProvider),
    isEnabled: () =>
        localMachineSupported && ref.read(localMachineEnabledProvider),
    interval: () => ref.read(serverMetricsRefreshIntervalProvider),
    serverName: () => ref.read(localMachineServerProvider).name,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final sessionsProvider = StreamProvider<List<SshSessionInfo>>((ref) {
  final manager = ref.watch(connectionManagerProvider);
  final serial = ref.watch(serialConnectionManagerProvider);
  final local = ref.watch(localConnectionManagerProvider);
  return _watchSessions(manager, serial, local);
});

final portForwardsProvider = StreamProvider<List<ActivePortForward>>((ref) {
  final manager = ref.watch(connectionManagerProvider);
  return _watchPortForwards(manager);
});

Stream<List<ActivePortForward>> _watchPortForwards(
  SshConnectionManager manager,
) async* {
  yield manager.currentPortForwards;
  yield* manager.portForwards;
}

Stream<List<SshSessionInfo>> _watchSessions(
  SshConnectionManager manager,
  SerialConnectionManager serial,
  LocalConnectionManager local,
) async* {
  yield [...manager.current, ...serial.current, ...local.current];
  yield* StreamGroup.merge([manager.sessions, serial.sessions, local.sessions]);
}

final serversProvider = StreamProvider<List<Server>>((ref) {
  final stored = ref.watch(serverRepositoryProvider).watchAll();
  if (!localMachineSupported) return stored;
  if (!ref.watch(localMachineEnabledProvider)) return stored;
  final local = ref.watch(localMachineServerProvider);
  return stored.map((servers) => [local, ...servers]);
});

final serverMetricsRefreshSchedulerProvider =
    Provider<ServerMetricsRefreshScheduler>((ref) {
      final scheduler = ServerMetricsRefreshScheduler(
        ref.watch(connectionManagerProvider),
      );
      final interval = ref.watch(serverMetricsRefreshIntervalProvider);
      final focusedServerId = ref.watch(focusedServerIdProvider);
      final servers =
          ref.watch(serversProvider).asData?.value ?? const <Server>[];
      final sessions =
          ref.watch(sessionsProvider).asData?.value ?? const <SshSessionInfo>[];
      scheduler.update(
        interval: interval,
        servers: servers,
        sessions: sessions,
        focusedServerId: focusedServerId,
      );
      ref.onDispose(scheduler.dispose);
      return scheduler;
    });
