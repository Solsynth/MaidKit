import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/shared/services/package_info_provider.dart';

import 'server_providers.dart';
import 'cloud_sync_service.dart';
import 'database_backup_service.dart';
import 'vault_create_page.dart';
import 'vault_file_storage.dart';

class VaultGate extends ConsumerStatefulWidget {
  const VaultGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  bool _unlocked = false;
  bool _busy = false;
  Timer? _autoSyncTimer;
  bool _autoSyncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _autoSync(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  Future<void> _autoSync() async {
    if (!_unlocked || _autoSyncing || !mounted) return;
    _autoSyncing = true;
    try {
      final vault = ref.read(vaultServiceProvider);
      final password = await vault.syncPassphrase();
      if (password == null || !mounted) return;
      final sync = ref.read(cloudSyncServiceProvider);
      if (await sync.configuration() == null || !mounted) return;
      final backup = DatabaseBackupService(ref.read(databaseProvider), vault);
      await sync.sync(
        archive: await backup.exportArchive(password),
        applyArchive: (archive) => backup.importArchive(archive, password),
        compareAndMergeArchive:
            ({required localArchive, required remoteArchive}) =>
                backup.compareAndMergeArchives(
                  localArchive: localArchive,
                  remoteArchive: remoteArchive,
                  password: password,
                ),
        contentFingerprint: backup.contentFingerprint,
      );
      if (mounted) ref.invalidate(cloudSyncConfigurationProvider);
    } catch (_) {
      // Auto-sync is best effort. Manual sync remains available for errors.
    } finally {
      _autoSyncing = false;
    }
  }

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state|ArgumentError): '),
    '',
  );
  void _retryVaultOpen() {
    ref.invalidate(vaultExistsProvider);
  }

  Future<void> _submit(bool exists) async {
    if (_busy) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    final vault = ref.read(vaultServiceProvider);
    try {
      var downloadedCloudVault = false;
      if (exists) {
        final ok = await vault.unlockWithPassword(_password.text);
        if (!ok) {
          throw StateError('vaultInvalidPassword'.tr());
        }
      } else {
        final sync = ref.read(cloudSyncServiceProvider);
        final configuration = await sync.configuration();
        final isCloudDownload = configuration?.pendingDownload == true;
        await vault.create(_password.text);
        if (isCloudDownload) {
          final backup = DatabaseBackupService(
            ref.read(databaseProvider),
            vault,
          );
          try {
            await sync.sync(
              archive: await backup.exportArchive(_password.text),
              applyArchive: (archive) =>
                  backup.importArchive(archive, _password.text),
              conflictResolution: CloudSyncConflictResolution.downloadRemote,
              contentFingerprint: backup.contentFingerprint,
            );
            await sync.completePendingDownload();
            ref.invalidate(cloudSyncConfigurationProvider);
            downloadedCloudVault = true;
          } on CloudSyncException {
            await vault.discardNewVault();
            rethrow;
          } catch (_) {
            await vault.discardNewVault();
            throw StateError('vaultDownloadedPasswordInvalid'.tr());
          }
        }
      }
      if (mounted) {
        setState(() => _unlocked = true);
        if (!downloadedCloudVault) unawaited(_autoSync());
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted && !_unlocked) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final unlocked = await ref
          .read(vaultServiceProvider)
          .unlockWithBiometrics();
      if (unlocked && mounted) {
        setState(() => _unlocked = true);
        unawaited(_autoSync());
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted && !_unlocked) setState(() => _busy = false);
    }
  }

  Future<void> _openVaultFile() async {
    if (_busy || !externalVaultsSupported) return;
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db', 'maidkit'],
    );
    final path = selection?.files.singleOrNull?.path;
    if (path == null) return;
    try {
      final managedPath = await ref
          .read(vaultFileStorageProvider)
          .importVault(path);
      await ref.read(activeVaultFileProvider.notifier).select(managedPath);
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
      return;
    }
    if (mounted) {
      setState(() {
        _error = null;
        _password.clear();
      });
    }
  }

  Future<void> _openCreatePage() async {
    if (_busy) return;
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VaultCreatePage()));
    if (created == true && mounted) {
      setState(() => _unlocked = true);
      unawaited(_autoSync());
    }
  }

  Future<void> _selectVault(String path) async {
    if (_busy) return;
    await ref.read(activeVaultFileProvider.notifier).select(path);
    if (!mounted) return;
    setState(() {
      _error = null;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeVaultFileProvider, (previous, next) {
      if (previous != next && mounted) {
        setState(() {
          _unlocked = false;
          _error = null;
          _busy = false;
          _password.clear();
        });
      }
    });
    final exists = ref.watch(vaultExistsProvider);
    final biometricEnabled = ref.watch(biometricUnlockEnabledProvider);
    final cloudConfiguration = ref.watch(cloudSyncConfigurationProvider);
    final activeFile = ref.watch(activeVaultFileProvider);
    final vaultFiles = ref.watch(vaultFilesProvider);
    final vaultLabels = ref.watch(vaultLabelsProvider);
    final theme = Theme.of(context);
    final packageInfo = ref.watch(packageInfoProvider);
    final showBiometricUnlock = biometricEnabled.asData?.value ?? false;
    final isCloudDownload =
        cloudConfiguration.asData?.value?.pendingDownload == true;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _unlocked
          ? KeyedSubtree(
              key: const ValueKey('vault_gate_unlocked'),
              child: widget.child,
            )
          : KeyedSubtree(
              key: const ValueKey('vault_gate_locked'),
              child: exists.when(
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('vaultOpenError'.tr(args: [error.toString()])),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _retryVaultOpen,
                          child: Text('commonRetry'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (hasVault) => Scaffold(
                  body: SafeArea(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Center(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Image.asset(
                                              'assets/icons/icon.png',
                                              width: 72,
                                              height: 72,
                                              errorBuilder: (_, _, _) =>
                                                  Container(
                                                    width: 72,
                                                    height: 72,
                                                    alignment: Alignment.center,
                                                    color: theme
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    child: Icon(
                                                      Symbols.lock,
                                                      size: 36,
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          hasVault
                                              ? 'vaultUnlockTitle'.tr()
                                              : isCloudDownload
                                              ? 'vaultDownloadedTitle'.tr()
                                              : 'vaultCreateTitle'.tr(),
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          hasVault
                                              ? 'vaultUnlockSubtitle'.tr()
                                              : isCloudDownload
                                              ? 'vaultDownloadedSubtitle'.tr()
                                              : 'vaultCreateSubtitle'.tr(),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 24),
                                        if (vaultFiles.isNotEmpty) ...[
                                          DropdownButtonFormField<String>(
                                            key: ValueKey(activeFile),
                                            initialValue: activeFile,
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                              labelText: 'vaultSelectLabel'
                                                  .tr(),
                                            ),
                                            onChanged: _busy
                                                ? null
                                                : (value) {
                                                    if (value != null) {
                                                      _selectVault(value);
                                                    }
                                                  },
                                            items: [
                                              for (final path in vaultFiles)
                                                DropdownMenuItem(
                                                  value: path,
                                                  child: Text(
                                                    vaultLabels[path] ??
                                                        ref
                                                            .read(
                                                              vaultFileStorageProvider,
                                                            )
                                                            .fileName(path),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (hasVault || isCloudDownload) ...[
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _password,
                                            obscureText: true,
                                            autofocus: true,
                                            enabled: !_busy,
                                            onSubmitted: (_) =>
                                                _submit(hasVault),
                                            decoration: InputDecoration(
                                              labelText: 'vaultPasswordLabel'
                                                  .tr(),
                                              suffix: showBiometricUnlock
                                                  ? IconButton(
                                                      icon: const Icon(
                                                        Symbols.fingerprint,
                                                      ),
                                                      onPressed: _busy
                                                          ? null
                                                          : _unlockWithBiometrics,
                                                      tooltip:
                                                          'vaultBiometricAction'
                                                              .tr(),
                                                      constraints:
                                                          const BoxConstraints(),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      iconSize: 20,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ],
                                        if (_error != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: Text(
                                              _error!,
                                              style: TextStyle(
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                          onPressed: _busy
                                              ? null
                                              : hasVault
                                              ? () => _submit(true)
                                              : isCloudDownload
                                              ? () => _submit(false)
                                              : _openCreatePage,
                                          child: _busy
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : Text(
                                                  hasVault
                                                      ? 'vaultUnlockAction'.tr()
                                                      : isCloudDownload
                                                      ? 'vaultDownloadedAction'
                                                            .tr()
                                                      : 'vaultAddAction'.tr(),
                                                ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (externalVaultsSupported)
                                          OutlinedButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : _openVaultFile,
                                            icon: const Icon(
                                              Symbols.folder_open,
                                            ),
                                            label: Text(
                                              'vaultOpenFileAction'.tr(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8,
                          child: Center(
                            child: packageInfo.maybeWhen(
                              data: (info) => Text(
                                'Build ${info.version}+${info.buildNumber}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              orElse: () => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
