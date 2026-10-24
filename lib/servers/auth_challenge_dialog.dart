import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'server_models.dart';

/// Asks the user for the answers to a keyboard-interactive challenge, such as
/// the verification code a bastion requires after the account password.
///
/// Returns null when the user cancels, which aborts the challenge and lets the
/// SSH client skip to the next authentication method. [onBeforePrompt] runs
/// before the dialog appears so callers can dismiss blocking loading overlays
/// that would otherwise sit above it.
Future<List<String>?> approveAuthChallenge(
  AuthChallenge challenge, {
  VoidCallback? onBeforePrompt,
}) async {
  onBeforePrompt?.call();
  return await showMaidKitOverlayDialog<List<String>>(
    barrierDismissible: false,
    builder: (context, close) =>
        _AuthChallengeDialog(challenge: challenge, close: close),
  );
}

class _AuthChallengeDialog extends StatefulWidget {
  const _AuthChallengeDialog({required this.challenge, required this.close});

  final AuthChallenge challenge;
  final void Function(List<String>? answers) close;

  @override
  State<_AuthChallengeDialog> createState() => _AuthChallengeDialogState();
}

class _AuthChallengeDialogState extends State<_AuthChallengeDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final prompt in widget.challenge.prompts)
        TextEditingController(text: prompt.initialValue ?? ''),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    // The server compares responses literally; surrounding whitespace only
    // comes from stray typing.
    widget.close([
      for (final controller in _controllers) controller.text.trim(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = widget.challenge;
    final instruction = challenge.instruction.trim();
    final prompts = challenge.prompts;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.verified_user,
                color: theme.colorScheme.primary,
                size: 36,
              ),
              const SizedBox(height: 16),
              Text(
                'serverAuthChallengeTitle'.tr(),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                challenge.name.trim().isEmpty
                    ? challenge.serverName
                    : '${challenge.serverName} · ${challenge.name.trim()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                instruction.isEmpty
                    ? 'serverAuthChallengeMessage'.tr()
                    : instruction,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < prompts.length; index++)
                        Padding(
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                          child: TextField(
                            controller: _controllers[index],
                            autofocus: index == 0,
                            obscureText: prompts[index].obscure,
                            textInputAction: index == prompts.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onSubmitted: index == prompts.length - 1
                                ? (_) => _submit()
                                : null,
                            decoration: InputDecoration(
                              labelText: prompts[index].text.trim().isEmpty
                                  ? 'serverAuthChallengeResponse'.tr()
                                  : prompts[index].text.trim(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => widget.close(null),
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
        ),
      ),
    );
  }
}
