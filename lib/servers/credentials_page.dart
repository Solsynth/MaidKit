import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';

import 'server_models.dart';
import 'server_providers.dart';

/// Opens the credential editor sheet; returns the draft when saved.
Future<SavedCredentialDraft?> showCredentialEditorSheet(
  BuildContext context, {
  SavedCredentialDraft? initial,
}) => showModalBottomSheet<SavedCredentialDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _CredentialEditorSheet(initial: initial),
);

class CredentialsPage extends ConsumerWidget {
  const CredentialsPage({super.key, this.showHeader = true});

  final bool showHeader;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentials = ref.watch(savedCredentialsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          LayoutBuilder(
            builder: (context, constraints) {
              final header = Text(
                'assetsCredentialsTitle'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              );
              final addButton = FilledButton.icon(
                onPressed: () => _addCredential(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('settingsCredentialAdd'.tr()),
              );
              return constraints.maxWidth < 600
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [header, const SizedBox(height: 8), addButton],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [header, addButton],
                    );
            },
          ),
        Text(
          'assetsCredentialsDescription'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        credentials.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(error.toString()),
          data: (items) => Column(
            children: [
              for (final credential in items)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    credential.credentialType == CredentialType.privateKey.name
                        ? Symbols.key
                        : Symbols.password,
                  ),
                  title: Text(credential.name),
                  subtitle: Text(
                    credential.credentialType == CredentialType.privateKey.name
                        ? 'serverAuthPrivateKey'.tr()
                        : 'serverAuthPassword'.tr(),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'settingsCredentialEdit'.tr(),
                        onPressed: () =>
                            _editCredential(context, ref, credential),
                        icon: const Icon(Symbols.edit),
                      ),
                      IconButton(
                        tooltip: 'commonDelete'.tr(),
                        onPressed: () =>
                            _deleteCredential(context, ref, credential),
                        icon: const Icon(Symbols.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addCredential(BuildContext context, WidgetRef ref) async {
    final draft = await showCredentialEditorSheet(context);
    if (draft == null) return;
    try {
      await ref.read(serverRepositoryProvider).createCredential(draft);
    } catch (error) {
      if (context.mounted) _showMessage(context, error.toString());
    }
  }

  Future<void> _editCredential(
    BuildContext context,
    WidgetRef ref,
    SavedCredential credential,
  ) async {
    try {
      final value = await ref
          .read(serverRepositoryProvider)
          .decryptCredential(credential);
      if (!context.mounted) return;
      final draft = await showCredentialEditorSheet(
        context,
        initial: SavedCredentialDraft(name: credential.name, credential: value),
      );
      if (draft != null) {
        await ref
            .read(serverRepositoryProvider)
            .updateCredential(credential, draft);
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, error.toString());
    }
  }

  Future<void> _deleteCredential(
    BuildContext context,
    WidgetRef ref,
    SavedCredential credential,
  ) async {
    final repository = ref.read(serverRepositoryProvider);
    final uses = await repository.serversUsingCredential(credential.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('settingsCredentialDeleteTitle').tr(),
        content: Text(
          'settingsCredentialDeleteDescription'.tr(args: ['$uses']),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('commonCancel').tr(),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('commonDelete').tr(),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteCredential(credential);
  }
}

class _CredentialEditorSheet extends StatefulWidget {
  const _CredentialEditorSheet({this.initial});

  final SavedCredentialDraft? initial;

  @override
  State<_CredentialEditorSheet> createState() => _CredentialEditorSheetState();
}

class _CredentialEditorSheetState extends State<_CredentialEditorSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _secret = TextEditingController();
  final _passphrase = TextEditingController();
  CredentialType _type = CredentialType.privateKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _name.text = initial.name;
    _type = initial.credential.type;
    _secret.text =
        initial.credential.password ?? initial.credential.privateKey ?? '';
    _passphrase.text = initial.credential.keyPassphrase ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'commonRequired'.tr() : null;
  String? _requiredSecret(String? value) =>
      value == null || value.isEmpty ? 'commonRequired'.tr() : null;

  Future<void> _pickKey() async {
    final result = await FilePicker.pickFiles(withData: true);
    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes != null && mounted) {
      setState(() => _secret.text = String.fromCharCodes(bytes));
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final credential = _type == CredentialType.password
        ? ServerCredential.password(_secret.text)
        : ServerCredential.privateKey(
            privateKey: _secret.text,
            keyPassphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
          );
    Navigator.pop(
      context,
      SavedCredentialDraft(name: _name.text, credential: credential),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    child: SheetScaffold(
      titleText: widget.initial == null
          ? 'settingsCredentialAdd'.tr()
          : 'settingsCredentialEdit'.tr(),
      heightFactor: 0.62,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'settingsCredentialName'.tr(),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            SegmentedButton<CredentialType>(
              segments: [
                ButtonSegment(
                  value: CredentialType.password,
                  label: Text('serverAuthPassword'.tr()),
                ),
                ButtonSegment(
                  value: CredentialType.privateKey,
                  label: Text('serverAuthPrivateKey'.tr()),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
            ),
            const SizedBox(height: 12),
            if (_type == CredentialType.password)
              TextFormField(
                controller: _secret,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'serverPasswordLabel'.tr(),
                ),
                validator: _requiredSecret,
              )
            else ...[
              TextFormField(
                controller: _secret,
                minLines: 4,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: 'serverPrivateKeyLabel'.tr(),
                  suffixIcon: IconButton(
                    onPressed: _pickKey,
                    icon: const Icon(Symbols.upload_file),
                  ),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'serverKeyPassphraseLabel'.tr(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: Text('commonSave'.tr())),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _showMessage(BuildContext context, String message) {
  showSnackBar(message);
}
