import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'terminal_session_adapter.dart';

/// Overlays a small hint above the terminal cursor when the session can
/// autofill the saved password into an active `sudo` prompt.
///
/// The adapter exposes the latest [SudoPromptReason] as a plain field, so
/// this widget polls it at a modest cadence and only repaints on change.
/// The chip is deliberately non-interactive: filling happens on Enter via
/// [SudoPromptAutofill] interception; the hint just makes that behavior
/// discoverable.
class TerminalSudoAutofillHint extends StatefulWidget {
  const TerminalSudoAutofillHint({
    super.key,
    required this.adapter,
    required this.child,
  });

  final TerminalSessionAdapter adapter;
  final Widget child;

  @override
  State<TerminalSudoAutofillHint> createState() =>
      _TerminalSudoAutofillHintState();
}

class _TerminalSudoAutofillHintState extends State<TerminalSudoAutofillHint> {
  static const _pollInterval = Duration(milliseconds: 200);

  Timer? _timer;
  SudoPromptReason? _reason;

  @override
  void initState() {
    super.initState();
    _reason = widget.adapter.sudoAutofillReady;
    _timer = Timer.periodic(_pollInterval, (_) {
      final next = widget.adapter.sudoAutofillReady;
      if (next != _reason) setState(() => _reason = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final rect = reason == null ? null : widget.adapter.cursorGlobalRect;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          widget.child,
          if (reason != null && rect != null)
            Positioned(
              // Align the chip with the cursor row and place it to the right
              // of the cursor cell, keeping it inside the viewport. The cursor
              // rect is in global coordinates; the Stack fills the same
              // bounds, so the global offset cancels out.
              left: (rect.right + 6).clamp(
                0.0,
                (constraints.maxWidth - 240).clamp(0.0, double.infinity),
              ),
              // Center the chip on the cursor row so it reads as sitting on
              // the same line as the prompt.
              top: rect.top + rect.height / 2 - 12,
              child: _HintChip(reason: reason),
            ),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.reason});

  final SudoPromptReason reason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  reason == SudoPromptReason.prompt
                      ? Symbols.key
                      : Symbols.terminal,
                  size: 14,
                  color: scheme.onInverseSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  'terminalSudoAutofillHint'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
