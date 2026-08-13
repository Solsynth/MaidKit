import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

/// Matches Island's dialog max width for app-level prompts.
const kMaidKitDialogMaxWidth = 480.0;

class _FadeOverlay extends StatefulWidget {
  const _FadeOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<_FadeOverlay> createState() => _FadeOverlayState();
}

class _FadeOverlayState extends State<_FadeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  Future<void> animateOut() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _controller, curve: Curves.linear),
    child: widget.child,
  );
}

/// A non-dismissible, app-wide progress overlay for operations that wait on a
/// remote server. Keep the returned handle and always dismiss it in `finally`.
MaidKitLoadingHandle showMaidKitLoadingModal(
  BuildContext context, {
  required String message,
}) {
  final overlay = IslandUIFoundation.overlayKey?.currentState;
  if (overlay == null) return MaidKitLoadingHandle._();

  final key = GlobalKey<_FadeOverlayState>();
  late final OverlayEntry entry;
  final handle = MaidKitLoadingHandle._(
    onDismiss: () async {
      final state = entry.mounted ? key.currentState : null;
      if (state != null) await state.animateOut();
      entry.remove();
    },
  );
  entry = OverlayEntry(
    builder: (context) => _FadeOverlay(
      key: key,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: AlertDialog(
            content: Row(
              children: [
                // Island explicitly uses the 2024 Material spinner here.
                CircularProgressIndicator(
                  // ignore: deprecated_member_use
                  year2023: false,
                  padding: EdgeInsets.zero,
                ).width(28).height(28).padding(horizontal: 8),
                const SizedBox(width: 16),
                Flexible(child: Text(message)),
              ],
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return handle;
}

class MaidKitLoadingHandle {
  MaidKitLoadingHandle._({this.onDismiss});

  final Future<void> Function()? onDismiss;
  var _dismissed = false;

  Future<void> dismiss() async {
    if (_dismissed) return;
    _dismissed = true;
    await onDismiss?.call();
  }
}

/// An Overlay-based dialog patterned after Island's alert helper. It keeps
/// transient confirmation UI above the desktop window frame and avoids route
/// dialogs for app-level prompts.
Future<T?> showMaidKitOverlayDialog<T>({
  required Widget Function(BuildContext context, void Function(T? result) close)
  builder,
  bool barrierDismissible = true,
}) {
  final overlay = IslandUIFoundation.overlayKey?.currentState;
  if (overlay == null) return Future.value(null);

  final completer = Completer<T?>();
  late final OverlayEntry entry;

  void close(T? result) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: barrierDismissible ? () => close(null) : null,
            child: const ColoredBox(color: Colors.black54),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
            ),
            child: builder(context, close),
          ),
        ),
      ],
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

String _formatErrorMessage(dynamic err) {
  return switch (err) {
    String message => message,
    Exception exception => exception.toString(),
    _ => err.toString(),
  };
}

/// An error dialog patterned after Island's [showErrorAlert]. Uses the
/// app-wide overlay so prompts sit above the desktop window frame.
void showMaidKitErrorAlert(dynamic err, {IconData? icon, String? title}) {
  final text = _formatErrorMessage(err);

  showMaidKitOverlayDialog<void>(
    builder: (context, close) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: AlertDialog(
        title: null,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon ?? Symbols.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                title ?? 'commonSomethingWentWrong'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(text),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(null),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}

/// A confirmation dialog patterned after Island's [showConfirmAlert]. Returns
/// `true` when the user confirms, otherwise `false`.
Future<bool> showMaidKitConfirmAlert(
  String message,
  String title, {
  IconData? icon,
  bool isDanger = false,
}) async {
  final result = await showMaidKitOverlayDialog<bool>(
    builder: (context, close) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: AlertDialog(
        title: null,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ?? Symbols.help_rounded,
              size: 48,
              fill: 1,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => close(true),
            style: isDanger
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Prompts the user to pick which copy wins when the cloud has a newer
/// revision during sync. Returns `true` to download the cloud version and
/// `false` to keep the local one. The barrier is not dismissible because
/// either choice permanently discards one of the two copies.
Future<bool> showMaidKitCloudSyncConflictAlert({
  required int remoteRevision,
}) async {
  final result = await showMaidKitOverlayDialog<bool>(
    barrierDismissible: false,
    builder: (context, close) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: AlertDialog(
        title: null,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Symbols.cloud_sync_rounded,
              size: 48,
              fill: 1,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'settingsVaultSyncConflictTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'settingsVaultSyncConflictBody'.tr(
                args: [remoteRevision.toString()],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: Text('settingsVaultSyncKeepLocal'.tr()),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: Text('settingsVaultSyncUseCloud'.tr()),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Prompts the user to reconnect before retrying an interrupted server action.
Future<bool> showMaidKitReconnectAlert(String serverName) async {
  final result = await showMaidKitOverlayDialog<bool>(
    builder: (context, close) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: AlertDialog(
        title: null,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Symbols.link_off,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'serverConnectionLostTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('serverConnectionLostRetry'.tr(args: [serverName])),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: Text('serverConnectAndRetry'.tr()),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// An Island command-palette-shaped overlay for searchable app actions.
Future<T?> showMaidKitCommandPalette<T>({
  required Widget Function(BuildContext context, void Function(T? result) close)
  builder,
  bool barrierDismissible = true,
}) {
  final overlay = IslandUIFoundation.overlayKey?.currentState;
  if (overlay == null) return Future.value(null);

  final completer = Completer<T?>();
  late final OverlayEntry entry;

  void close(T? result) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (context) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: barrierDismissible ? () => close(null) : null,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.5),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.2,
              ),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                tween: Tween(begin: 0.8, end: 1),
                builder: (context, scale, child) => Opacity(
                  opacity: ((scale - 0.8) / 0.2).clamp(0, 1),
                  child: Transform.scale(scale: scale, child: child),
                ),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: math.max(
                      MediaQuery.sizeOf(context).width * 0.6,
                      320,
                    ),
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                      maxHeight: 500,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      child: builder(context, close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  return completer.future;
}
