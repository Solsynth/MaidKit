import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'cloud_sync_service.dart';
import 'connection_import_service.dart';
import 'connection_import_sheet.dart';
import 'server_providers.dart';
import 'vault_file_storage.dart';

/// Full-screen vault onboarding reached from the locked vault gate.
///
/// The user either creates a brand-new local vault file or signs in to
/// Solarpass to download an existing cloud vault.
class VaultCreatePage extends ConsumerStatefulWidget {
  const VaultCreatePage({super.key});

  @override
  ConsumerState<VaultCreatePage> createState() => _VaultCreatePageState();
}

class _VaultCreatePageState extends ConsumerState<VaultCreatePage> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _folderPath;
  bool _externalStorage = false;
  bool _creatingLocal = false;
  bool _importMode = false;
  List<ImportCandidate>? _pendingCandidates;
  bool _busy = false;

  /// Whether the Solarpass sign-in/download request is in flight. Kept
  /// separate from [_busy] so the choices view can show progress feedback:
  /// the sign-in can take seconds (OIDC discovery, browser authorization,
  /// token exchange, workspace list) with no modal to signal it.
  bool _cloudBusy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state|ArgumentError): '),
    '',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('vaultCreateTitle'.tr())),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _creatingLocal
                    ? _buildLocalForm(theme)
                    : _buildChoices(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoices(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'vaultCreateTitle'.tr(),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'vaultCreateSubtitle'.tr(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Symbols.add),
                title: Text('vaultCreateFileAction'.tr()),
                subtitle: Text('settingsVaultCreateLocalHint'.tr()),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _creatingLocal = true;
                        _error = null;
                      }),
              ),
              if (externalVaultsSupported) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Symbols.folder_open),
                  title: Text('vaultCreateExternalAction'.tr()),
                  subtitle: Text('vaultCreateExternalHint'.tr()),
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          _creatingLocal = true;
                          _externalStorage = true;
                          _error = null;
                        }),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Symbols.dns),
                title: Text('vaultCreateImportAction'.tr()),
                subtitle: Text('vaultCreateImportHint'.tr()),
                onTap: _busy ? null : _pickConnectionFiles,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Symbols.cloud_download),
                title: Text('vaultCreateFromCloudAction'.tr()),
                subtitle: Text('vaultCreateFromCloudHint'.tr()),
                onTap: _busy ? null : _downloadFromCloud,
              ),
            ],
          ),
        ),
        if (_cloudBusy)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 12),
                Text(
                  'settingsCloudSigningIn'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
      ],
    );
  }

  Widget _buildLocalForm(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _importMode
              ? 'vaultCreateImportAction'.tr()
              : 'vaultCreateFileAction'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _importMode
              ? 'vaultCreateImportHint'.tr()
              : 'settingsVaultCreateLocalHint'.tr(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          enabled: !_busy,
          decoration: InputDecoration(labelText: 'settingsVaultName'.tr()),
        ),
        if (_externalStorage) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickVaultFolder,
            icon: const Icon(Symbols.folder_open),
            label: Text(
              _folderPath == null
                  ? 'vaultChooseFolder'.tr()
                  : 'vaultChangeFolder'.tr(),
            ),
          ),
          if (_folderPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _folderPath!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'vaultExternalStorageHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'vaultInternalStorageHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          enabled: !_busy,
          onSubmitted: (_) =>
              _importMode ? _createVaultFromImport() : _createLocalVault(),
          decoration: InputDecoration(labelText: 'vaultPasswordLabel'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmation,
          obscureText: true,
          enabled: !_busy,
          onSubmitted: (_) =>
              _importMode ? _createVaultFromImport() : _createLocalVault(),
          decoration: InputDecoration(
            labelText: 'vaultConfirmPasswordLabel'.tr(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : _importMode
              ? _createVaultFromImport
              : _createLocalVault,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _importMode
                      ? 'vaultCreateImportCreate'.tr()
                      : 'vaultCreateAction'.tr(),
                ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _creatingLocal = false;
                  _importMode = false;
                  _externalStorage = false;
                  _folderPath = null;
                  _pendingCandidates = null;
                  _error = null;
                }),
          child: Text('commonCancel'.tr()),
        ),
      ],
    );
  }

  Future<void> _pickVaultFolder() async {
    if (_busy || !externalVaultsSupported) return;
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'vaultChooseFolder'.tr(),
        initialDirectory: _folderPath,
      );
      if (path != null && mounted) {
        setState(() {
          _folderPath = path;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _createLocalVault() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'vaultNameRequired'.tr());
      return;
    }
    if (_externalStorage && _folderPath == null) {
      setState(() => _error = 'vaultFolderRequired'.tr());
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'vaultPasswordsDontMatch'.tr());
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    var success = false;
    try {
      final path = await ref
          .read(vaultFileStorageProvider)
          .createVaultPath(
            name: name,
            directoryPath: _externalStorage ? _folderPath : null,
          );
      await ref.read(vaultLabelsProvider.notifier).rename(path, name);
      await ref.read(activeVaultFileProvider.notifier).select(path);
      await ref.read(vaultServiceProvider).create(_password.text);
      success = true;
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _busy = false);
        }
      }
    }
  }

  Future<void> _pickConnectionFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: 'settingsConnectionsImportTitle'.tr(),
        type: FileType.any,
        allowMultiple: true,
      );
      final paths =
          selection?.files
              .map((file) => file.path)
              .whereType<String>()
              .where((path) => path.isNotEmpty)
              .toList() ??
          const [];
      if (paths.isEmpty || !mounted) return;

      final service = ConnectionImportService(
        ref.read(databaseProvider),
        ref.read(vaultServiceProvider),
      );
      final preview = await service.previewFiles(
        paths,
        requestPassphrase: () => _importPassphraseSheet(context),
      );
      if (!mounted || preview.aborted) return;
      if (preview.isEmpty) {
        if (mounted) {
          setState(() {
            _error = preview.firstError is ConnectionSecretsPassphraseException
                ? 'settingsConnectionsImportWrongPassphrase'.tr()
                : 'settingsConnectionsImportEmpty'.tr();
          });
        }
        return;
      }

      final selected = await showModalBottomSheet<List<ImportCandidate>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) =>
            ConnectionImportPreviewSheet(candidates: preview.candidates),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      setState(() {
        _pendingCandidates = selected;
        _importMode = true;
        _externalStorage = false;
        _folderPath = null;
        _creatingLocal = true;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createVaultFromImport() async {
    if (_busy) return;
    final candidates = _pendingCandidates;
    if (candidates == null || candidates.isEmpty) {
      setState(() {
        _creatingLocal = false;
        _importMode = false;
        _externalStorage = false;
        _folderPath = null;
        _error = null;
      });
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'vaultNameRequired'.tr());
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'vaultPasswordsDontMatch'.tr());
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    var success = false;
    try {
      final path = await ref
          .read(vaultFileStorageProvider)
          .createVaultPath(name: name);
      await ref.read(vaultLabelsProvider.notifier).rename(path, name);
      await ref.read(activeVaultFileProvider.notifier).select(path);
      await ref.read(vaultServiceProvider).create(_password.text);
      final result = await ConnectionImportService(
        ref.read(databaseProvider),
        ref.read(vaultServiceProvider),
      ).import(candidates);
      if (result.created == 0 && mounted) {
        setState(() => _error = 'settingsConnectionsImportEmpty'.tr());
      }
      success = result.created > 0;
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _busy = false);
        }
      }
    }
  }

  Future<String?> _importPassphraseSheet(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (context) => const _ImportPassphraseSheet(),
      );

  Future<void> _downloadFromCloud() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _busy = true;
      _cloudBusy = true;
    });
    try {
      final accountService = ref.read(cloudSyncServiceProvider);
      final workspaces = await accountService.signInAndListWorkspaces();
      if (!mounted) return;
      final workspace = await _chooseCloudWorkspace(workspaces);
      if (workspace == null || !mounted) return;
      final blobs = await accountService.listVaultBlobs(workspace);
      if (!mounted) return;
      final blob = await _chooseCloudVault(blobs);
      if (blob == null || !mounted) return;
      final name = await _chooseVaultName(initialValue: workspace.name);
      if (name == null || !mounted) return;

      final path = await ref
          .read(vaultFileStorageProvider)
          .createVaultPath(name: name);
      final sync = ref.read(cloudSyncServiceForVaultProvider(path));
      await sync.enable(workspace, existingBlob: blob);
      ref.invalidate(cloudSyncConfigurationForVaultProvider(path));
      await ref.read(activeVaultFileProvider.notifier).select(path);
      if (mounted) Navigator.of(context).pop(false);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cloudBusy = false;
        });
      }
    }
  }

  Future<CloudWorkspace?> _chooseCloudWorkspace(
    List<CloudWorkspace> workspaces,
  ) => showModalBottomSheet<CloudWorkspace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetContext) => SheetScaffold(
      titleText: 'vaultCloudWorkspaceTitle'.tr(),
      heightFactor: 0.6,
      child: workspaces.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [const Text('settingsCloudSyncNoWorkspaces').tr()],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                for (final workspace in workspaces)
                  ListTile(
                    title: Text(workspace.name),
                    onTap: () => Navigator.of(sheetContext).pop(workspace),
                  ),
              ],
            ),
    ),
  );

  Future<CloudVaultBlob?> _chooseCloudVault(List<CloudVaultBlob> blobs) =>
      showModalBottomSheet<CloudVaultBlob>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) => SheetScaffold(
          titleText: 'settingsVaultDownloadCloud'.tr(),
          heightFactor: 0.6,
          child: blobs.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [const Text('settingsVaultNoCloudVaults').tr()],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final blob in blobs)
                      ListTile(
                        leading: const Icon(Symbols.lock),
                        title: Text(
                          'settingsVaultCloudVault'.tr(
                            args: [blob.revision.toString()],
                          ),
                        ),
                        subtitle: Text(blob.id),
                        onTap: () => Navigator.of(sheetContext).pop(blob),
                      ),
                  ],
                ),
        ),
      );

  Future<String?> _chooseVaultName({String? initialValue}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) =>
            _VaultNameSheet(initialValue: initialValue ?? ''),
      );
}

class _VaultNameSheet extends StatefulWidget {
  const _VaultNameSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_VaultNameSheet> createState() => _VaultNameSheetState();
}

class _VaultNameSheetState extends State<_VaultNameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: 'settingsVaultName'.tr(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'settingsVaultName'.tr()),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('commonCancel').tr(),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _submit,
              child: const Text('commonContinue').tr(),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Single-field passphrase prompt for importing a protected MaidKit JSON
/// export while creating a vault.
class _ImportPassphraseSheet extends StatefulWidget {
  const _ImportPassphraseSheet();

  @override
  State<_ImportPassphraseSheet> createState() => _ImportPassphraseSheetState();
}

class _ImportPassphraseSheetState extends State<_ImportPassphraseSheet> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_password.text);

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: 'settingsConnectionsImportPasswordTitle'.tr(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('settingsConnectionsImportPasswordHint').tr(),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: 'vaultPasswordLabel'.tr()),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('commonCancel').tr(),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _submit,
              child: const Text('settingsConnectionsImportAction').tr(),
            ),
          ],
        ),
      ],
    ),
  );
}
