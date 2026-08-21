import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import 'terminal_controller.dart';

/// Clear terminal screen and scrollback.
@internal
class ClearIntent extends Intent {
  const ClearIntent();
}

/// Copy the current terminal selection.
@internal
class CopyIntent extends Intent {
  const CopyIntent();
}

/// Paste clipboard content into the terminal.
@internal
class PasteIntent extends Intent {
  const PasteIntent();
}

/// Select all terminal content.
@internal
class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

/// Platform-adaptive default shortcut bindings for terminal actions.
@internal
abstract final class TerminalShortcuts {
  static Map<ShortcutActivator, Intent> defaultsFor([
    TargetPlatform? platform,
  ]) {
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => {
        const SingleActivator(.keyC, meta: true): const CopyIntent(),
        const SingleActivator(.keyV, meta: true): const PasteIntent(),
        const SingleActivator(.keyA, meta: true): const SelectAllIntent(),
        const SingleActivator(.keyK, meta: true): const ClearIntent(),
      },
      TargetPlatform.linux || TargetPlatform.fuchsia => {
        const SingleActivator(.keyC, control: true, shift: true):
            const CopyIntent(),
        const SingleActivator(.keyV, control: true, shift: true):
            const PasteIntent(),
        const SingleActivator(.keyA, control: true, shift: true):
            const SelectAllIntent(),
        const SingleActivator(.keyK, control: true, shift: true):
            const ClearIntent(),
      },
      TargetPlatform.windows || TargetPlatform.android => {
        const SingleActivator(.keyC, control: true): const CopyIntent(),
        const SingleActivator(.keyV, control: true): const PasteIntent(),
        const SingleActivator(.keyA, control: true): const SelectAllIntent(),
        const SingleActivator(.keyK, control: true): const ClearIntent(),
      },
    };
  }
}

/// Wraps [child] with platform-adaptive terminal shortcuts and actions.
///
/// Copy is only enabled when the controller has an active selection.
/// On platforms where the copy shortcut conflicts with a terminal control
/// sequence (e.g. Ctrl+C on Windows), the key event propagates to the
/// terminal when no selection is present.
///
/// ```dart
/// TerminalShortcutScope(
///   controller: controller,
///   onPaste: handlePaste,
///   child: terminalContent,
/// )
/// ```
@internal
class TerminalShortcutScope extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPaste;
  final TerminalController controller;

  /// Whether the select-all shortcut is active.
  final bool enableSelectAll;

  /// Additional shortcut bindings merged over platform defaults.
  final Map<ShortcutActivator, Intent>? shortcuts;

  const TerminalShortcutScope({
    super.key,
    required this.child,
    required this.controller,
    this.onPaste,
    this.enableSelectAll = true,
    this.shortcuts,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {...TerminalShortcuts.defaultsFor(), ...?shortcuts},
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopyIntent: _ConditionalAction<CopyIntent>(
            isEnabledFn: () => controller.hasSelection,
            onInvokeFn: () {
              final text = controller.selectedText();
              if (text.isNotEmpty) {
                unawaited(Clipboard.setData(ClipboardData(text: text)));
              }
            },
          ),
          PasteIntent: CallbackAction<PasteIntent>(
            onInvoke: (_) => onPaste?.call(),
          ),
          SelectAllIntent: _ConditionalAction<SelectAllIntent>(
            isEnabledFn: () => enableSelectAll,
            onInvokeFn: controller.selectAll,
          ),
          ClearIntent: CallbackAction<ClearIntent>(
            onInvoke: (_) => controller.clear(),
          ),
        },
        child: child,
      ),
    );
  }
}

class _ConditionalAction<T extends Intent> extends Action<T> {
  final VoidCallback? onInvokeFn;
  final ValueGetter<bool> isEnabledFn;

  _ConditionalAction({required this.isEnabledFn, this.onInvokeFn});

  @override
  Object? invoke(T intent) {
    onInvokeFn?.call();
    return null;
  }

  @override
  bool isEnabled(T intent) => isEnabledFn();
}
