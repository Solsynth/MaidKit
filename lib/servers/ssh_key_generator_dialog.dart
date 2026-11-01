import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'credential_generator.dart';

/// What the generator hands back to the credential editor.
typedef SshKeyGeneratorResult = ({GeneratedSshKeyPair pair, String passphrase});

/// Opens the SSH key pair generator; returns the generated pair once the user
/// accepts it, or null when they cancel.
Future<SshKeyGeneratorResult?> showSshKeyGeneratorDialog(
  BuildContext context, {
  String initialPassphrase = '',
}) => showDialog<SshKeyGeneratorResult>(
  context: context,
  builder: (_) => _SshKeyGeneratorDialog(initialPassphrase: initialPassphrase),
);

class _SshKeyGeneratorDialog extends StatefulWidget {
  const _SshKeyGeneratorDialog({required this.initialPassphrase});

  final String initialPassphrase;

  @override
  State<_SshKeyGeneratorDialog> createState() => _SshKeyGeneratorDialogState();
}

class _SshKeyGeneratorDialogState extends State<_SshKeyGeneratorDialog> {
  final _comment = TextEditingController(text: defaultSshKeyComment);
  final _passphrase = TextEditingController();
  SshKeyType _type = SshKeyType.ed25519;
  int _rsaBits = 3072;
  bool _generating = false;
  String? _error;
  SshKeyGeneratorResult? _result;

  @override
  void initState() {
    super.initState();
    _passphrase.text = widget.initialPassphrase;
  }

  @override
  void dispose() {
    _comment.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final pair = await generateSshKeyPair(
        type: _type,
        rsaBits: _rsaBits,
        passphrase: _passphrase.text,
        comment: _comment.text,
      );
      if (!mounted) return;
      setState(() => _result = (pair: pair, passphrase: _passphrase.text));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copyPublicKey() async {
    final pair = _result?.pair;
    if (pair == null) return;
    await Clipboard.setData(ClipboardData(text: pair.publicKey));
    if (!mounted) return;
    showSnackBar('commonCopiedToClipboard'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    return AlertDialog(
      title: Text(
        result == null
            ? 'credentialsKeyGenerateTitle'.tr()
            : 'credentialsKeyResultTitle'.tr(),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: result == null ? _form(scheme) : _generated(result, scheme),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(result == null ? 'commonCancel'.tr() : 'commonDone'.tr()),
        ),
        if (result == null)
          FilledButton(
            onPressed: _generating ? null : _generate,
            child: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('credentialsKeyGenerateAction'.tr()),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, result),
            icon: const Icon(Symbols.check),
            label: Text('credentialsKeyUseKey'.tr()),
          ),
      ],
    );
  }

  Widget _form(ColorScheme scheme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<SshKeyType>(
        segments: [
          ButtonSegment(
            value: SshKeyType.ed25519,
            label: Text('credentialsKeyEd25519'.tr()),
          ),
          ButtonSegment(
            value: SshKeyType.rsa,
            label: Text('credentialsKeyRsa'.tr()),
          ),
        ],
        selected: {_type},
        onSelectionChanged: _generating
            ? null
            : (value) => setState(() => _type = value.first),
      ),
      if (_type == SshKeyType.rsa) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _rsaBits,
          decoration: InputDecoration(labelText: 'credentialsKeyRsaBits'.tr()),
          items: [
            for (final bits in rsaKeySizes)
              DropdownMenuItem(value: bits, child: Text('$bits')),
          ],
          onChanged: _generating
              ? null
              : (value) {
                  if (value != null) setState(() => _rsaBits = value);
                },
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _comment,
        enabled: !_generating,
        decoration: InputDecoration(
          labelText: 'credentialsKeyComment'.tr(),
          helperText: 'credentialsKeyCommentHint'.tr(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passphrase,
        enabled: !_generating,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'serverKeyPassphraseLabel'.tr(),
          helperText: 'credentialsKeyPassphraseHint'.tr(),
        ),
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 12),
        Text(
          'credentialsKeyGenerateFailed'.tr(args: [error]),
          style: TextStyle(color: scheme.error),
        ),
      ],
    ],
  );

  Widget _generated(SshKeyGeneratorResult result, ColorScheme scheme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'credentialsKeyPublicHint'.tr(),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            result.pair.publicKey,
            style: const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 12),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _copyPublicKey,
          icon: const Icon(Symbols.content_copy, size: 18),
          label: Text('commonCopy'.tr()),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        result.passphrase.isEmpty
            ? 'credentialsKeyInsertHint'.tr()
            : 'credentialsKeyInsertEncryptedHint'.tr(),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ],
  );
}
