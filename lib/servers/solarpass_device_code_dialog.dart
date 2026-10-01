import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_sync_service.dart';

/// Runs [action] with a callback that puts a device-flow code on screen.
///
/// The web build signs in with RFC 8628's device flow: nothing in a browser
/// can hand the `maidkit` scheme back into the page, so the provider hands out
/// a code and the app polls while the user approves it in a browser. Every
/// other platform signs in through a browser window and never calls back, so
/// no dialog is shown there.
///
/// Closing the dialog only stops showing the code. The authorization runs to
/// its own end — approved or expired — and its result still reaches [action].
Future<T> withSolarpassDeviceCode<T>(
  BuildContext context,
  Future<T> Function(CloudDeviceCodeCallback onDeviceCode) action,
) async {
  final authorization = ValueNotifier<SolarpassDeviceAuthorization?>(null);
  final closed = ValueNotifier(false);
  Future<void>? dialog;
  try {
    return await action((value) {
      authorization.value = value;
      if (!context.mounted) return;
      dialog = showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) =>
            _DeviceCodeDialog(authorization: authorization, closed: closed),
      );
    });
  } finally {
    closed.value = true;
    final pending = dialog;
    if (pending != null) await pending;
  }
}

class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({required this.authorization, required this.closed});

  final ValueNotifier<SolarpassDeviceAuthorization?> authorization;

  /// Set when the sign-in has ended, however it ended. Closing the dialog
  /// early does not set it: the authorization keeps running.
  final ValueNotifier<bool> closed;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  @override
  void initState() {
    super.initState();
    widget.closed.addListener(_close);
    // The sign-in can end before this route reaches the screen; that pop has
    // to wait for the frame that pushes it.
    if (widget.closed.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    if (!mounted) return;
    // The dialog's own close button may already have popped the route, which
    // stays mounted through the exit animation.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.closed.removeListener(_close);
    // The notifiers outlive this route on purpose: closing the dialog early
    // leaves the sign-in running, and the caller still writes the code and the
    // closed flag when it ends. They hold no resources, so they are left to the
    // collector rather than disposed under its feet.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('solarpassDeviceCodeTitle').tr(),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<SolarpassDeviceAuthorization?>(
          valueListenable: widget.authorization,
          builder: (context, value, _) {
            if (value == null) {
              return const LinearProgressIndicator();
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('solarpassDeviceCodeInstruction').tr(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          value.userCode,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: 'IBM Plex Mono',
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'commonCopy'.tr(),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: value.userCode),
                          );
                          if (context.mounted) {
                            showSnackBar('commonCopiedToClipboard'.tr());
                          }
                        },
                        icon: const Icon(Symbols.content_copy, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'solarpassDeviceCodeWaiting'.tr(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('commonClose').tr(),
        ),
        ValueListenableBuilder<SolarpassDeviceAuthorization?>(
          valueListenable: widget.authorization,
          builder: (context, value, _) => FilledButton.tonalIcon(
            onPressed: value == null
                ? null
                : () => launchUrl(value.verificationUriComplete),
            icon: const Icon(Symbols.open_in_new, size: 18),
            label: const Text('solarpassDeviceCodeOpenPage').tr(),
          ),
        ),
      ],
    );
  }
}
