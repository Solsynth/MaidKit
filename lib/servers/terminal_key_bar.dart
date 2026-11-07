import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';
import 'terminal_session_adapter.dart';

/// One key on the deck: the glyph it prints, the bytes it sends, and whether a
/// held thumb keeps sending it.
class _DeckKey {
  const _DeckKey(
    this.label,
    this.input, {
    required this.name,
    this.repeat = false,
  });

  final String label;
  final String input;

  /// The key's spoken name, so a screen reader says "Escape", not "esc".
  final String name;

  /// Whether holding the key keeps sending it — the arrows and page keys a
  /// cursor is moved with.
  final bool repeat;
}

/// The keys a phone's keyboard cannot type, on the pane's own sheet.
///
/// A software keyboard has letters, a space bar and a return key — no Esc, no
/// Tab, no arrows and no Ctrl, which are what a shell asks for most. The deck
/// is a strip of mono keycaps along the pane's bottom edge: one modifier key at
/// the leading edge, a scrolling run of keys, and the keyboard key at the
/// trailing edge.
///
/// The `ctrl` key is the deck's one idea, and it replaces the expander a
/// two-row key list would need: pressed once it arms, and the run under it
/// swaps from navigation keys to control chords. There is no third layer and no
/// chevron, because a thumb above a keyboard has one axis of reach to spend on
/// extra keys.
///
/// A key sends bytes straight into the session and never takes focus, so a
/// chord leaves the IME up and the cursor where it was. Only [KeyboardKey]
/// moves focus, because that is the whole of what it does.
class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({required this.terminal, super.key});

  final TerminalSessionAdapter terminal;

  /// Height the deck asks for.
  static const contentHeight = 52.0;

  /// Height of one keycap.
  static const _capHeight = 36.0;

  /// Navigation: what a cursor, a pager and a shell prompt are driven with when
  /// there is no physical keyboard to drive them.
  ///
  /// Two rules hold this vocabulary together. Every label is real IBM Plex Mono
  /// — arrows and letters, never a symbol glyph the mono face lacks — so a key
  /// never renders as a tofu box. And the labels are the key's *own* name, not
  /// a chord: the control layer prints the chord, so a keycap only ever says
  /// what it will send.
  static const _navigationKeys = [
    _DeckKey('esc', '\u001b', name: 'Escape'),
    _DeckKey('tab', '\t', name: 'Tab'),
    _DeckKey('shift tab', '\u001b[Z', name: 'Shift Tab'),
    _DeckKey('←', '\u001b[D', name: 'Left arrow', repeat: true),
    _DeckKey('↑', '\u001b[A', name: 'Up arrow', repeat: true),
    _DeckKey('↓', '\u001b[B', name: 'Down arrow', repeat: true),
    _DeckKey('→', '\u001b[C', name: 'Right arrow', repeat: true),
    _DeckKey('home', '\u001b[H', name: 'Home'),
    _DeckKey('end', '\u001b[F', name: 'End'),
    _DeckKey('pgup', '\u001b[5~', name: 'Page up'),
    _DeckKey('pgdn', '\u001b[6~', name: 'Page down'),
    _DeckKey('del', '\u007f', name: 'Delete'),
  ];

  /// Chords worth a thumb: line editing, history, and the signals that stop a
  /// stuck program or end a session.
  static const _controlKeys = [
    _DeckKey('C', '\u0003', name: 'Control C'),
    _DeckKey('D', '\u0004', name: 'Control D'),
    _DeckKey('L', '\u000c', name: 'Control L'),
    _DeckKey('R', '\u0012', name: 'Control R'),
    _DeckKey('Z', '\u001a', name: 'Control Z'),
    _DeckKey('A', '\u0001', name: 'Control A'),
    _DeckKey('E', '\u0005', name: 'Control E'),
    _DeckKey('U', '\u0015', name: 'Control U'),
    _DeckKey('W', '\u0017', name: 'Control W'),
    _DeckKey('K', '\u000b', name: 'Control K'),
  ];

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  var _controlLayer = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final keys = _controlLayer
        ? TerminalKeyBar._controlKeys
        : TerminalKeyBar._navigationKeys;

    return SizedBox(
      height: TerminalKeyBar.contentHeight,
      child: Row(
        children: [
          const SizedBox(width: MaidKitSpace.sm),
          // The modifier leads the run and does not scroll away with it: it
          // changes what the run means, so it cannot be one of the keys the
          // run offers.
          _KeyCap(
            label: 'ctrl',
            semanticsLabel: 'terminalKeyLayerCtrl'.tr(),
            armed: _controlLayer,
            width: 52,
            onPressed: () => setState(() => _controlLayer = !_controlLayer),
          ),
          Expanded(
            // The run is longer than the deck: Esc, Tab, four arrows, Home,
            // End, two page keys and Delete cannot fit a phone. The trailing
            // fade is what says "more keys this way" — the alternative, a
            // chevron, would be another control to decode, and a cap sliced
            // flat at the edge reads as a broken key rather than a seam.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Colors.white, Colors.transparent],
                // The fade starts late and stays short: it is a seam, not a
                // dimmer. A cap that fades before its own right edge reads as
                // disabled rather than as off-screen.
                stops: [0, 0.94, 1],
              ).createShader(bounds),
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) {
                  final curve = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  );
                  return FadeTransition(
                    opacity: curve,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(curve),
                      child: child,
                    ),
                  );
                },
                child: ListView.separated(
                  key: ValueKey(_controlLayer),
                  // A key run is scrolled by thumb: the deck must not bounce
                  // or settle under a resting press.
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    MaidKitSpace.xs,
                    (TerminalKeyBar.contentHeight - TerminalKeyBar._capHeight) /
                        2,
                    MaidKitSpace.md,
                    (TerminalKeyBar.contentHeight - TerminalKeyBar._capHeight) /
                        2,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: keys.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MaidKitSpace.xs),
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return _KeyCap(
                      label: key.label,
                      semanticsLabel: key.name,
                      height: TerminalKeyBar._capHeight,
                      style: theme.textTheme.labelMedium,
                      repeat: key.repeat,
                      onPressed: () => widget.terminal.sendInput(key.input),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: MaidKitSpace.sm),
          KeyboardKey(terminal: widget.terminal),
          const SizedBox(width: MaidKitSpace.sm),
        ],
      ),
    );
  }
}

/// A mono keycap on the deck.
///
/// Tonal, never outlined: a soft fill at rest, the deepest container under a
/// thumb, the accent container while armed. Mono type with tabular figures, on
/// the app's 8 pt chip radius, so a key reads as a key and never as one of the
/// status band's pills.
///
/// A repeatable key sends once when it is tapped and then keeps sending on a
/// timer while the thumb stays down — a line of arrows is one gesture, not
/// twelve.
class _KeyCap extends StatefulWidget {
  const _KeyCap({
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
    this.style,
    this.armed = false,
    this.repeat = false,
    this.height = 36,
    this.width,
  });

  final String label;
  final VoidCallback onPressed;
  final String? semanticsLabel;
  final TextStyle? style;
  final bool armed;
  final bool repeat;
  final double height;
  final double? width;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  /// How long a thumb rests before a repeatable key starts repeating.
  static const _repeatHold = Duration(milliseconds: 380);

  /// What a held arrow sends per tick.
  static const _repeatInterval = Duration(milliseconds: 70);

  Timer? _hold;
  Timer? _repeat;
  var _pressed = false;
  var _buzzed = false;

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _onDown() {
    _stopTimers();
    _buzzed = false;
    setState(() => _pressed = true);
    if (!widget.repeat) return;
    _hold = Timer(_repeatHold, () {
      _fire();
      _repeat = Timer.periodic(_repeatInterval, (_) => _fire());
    });
  }

  void _onUp() {
    // A lift while the hold timer is still waiting is a tap: it sends the key
    // once. After the hold has fired, the gesture was a repeat and its bytes
    // are already sent.
    final tapped = _hold?.isActive ?? true;
    _stopTimers();
    if (mounted) setState(() {});
    if (tapped) _fire();
  }

  void _onCancel() {
    _stopTimers();
    if (mounted) setState(() {});
  }

  void _stopTimers() {
    _hold?.cancel();
    _repeat?.cancel();
    _hold = null;
    _repeat = null;
    _pressed = false;
  }

  void _fire() {
    // One buzz per gesture: a held arrow repeating twelve times must not turn
    // the deck into a rattle.
    if (!_buzzed) {
      HapticFeedback.selectionClick();
      _buzzed = true;
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Solid, not translucent: the deck sits on a pane sheet in both themes and
    // a key has to read as a key at phone size. Pressed steps one tone deeper,
    // armed takes the accent container, so the three states are all tone.
    final fill = widget.armed
        ? scheme.primaryContainer
        : _pressed
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerHigh;
    final labelColor = widget.armed
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Semantics(
      button: true,
      label: widget.semanticsLabel ?? widget.label,
      hint: widget.repeat ? 'terminalKeyHoldHint'.tr() : null,
      onTap: widget.onPressed,
      child: ExcludeFocus(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onDown(),
          onTapUp: (_) => _onUp(),
          onTapCancel: _onCancel,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            height: widget.height,
            width: widget.width,
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: MaidKitSpace.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: const BorderRadius.all(
                Radius.circular(MaidKitRadius.chip),
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              style: (widget.style ?? theme.textTheme.labelMedium)?.copyWith(
                fontFamily: MaidKitFonts.mono,
                fontWeight: widget.armed ? FontWeight.w600 : FontWeight.w500,
                color: labelColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raise-or-release key for the mobile soft keyboard.
///
/// The pane body sits inside a [Scaffold], which strips the bottom view insets
/// from the media query it hands down, so `MediaQuery.viewInsetsOf` reads zero
/// while the keyboard is up — the key would only ever show it. The platform
/// view still reports the real inset, and its metrics callback is what redraws
/// this key when the keyboard comes or goes.
class KeyboardKey extends StatefulWidget {
  const KeyboardKey({required this.terminal, super.key});

  final TerminalSessionAdapter terminal;

  @override
  State<KeyboardKey> createState() => _KeyboardKeyState();
}

class _KeyboardKeyState extends State<KeyboardKey> with WidgetsBindingObserver {
  static const _width = 44.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = View.of(context).viewInsets.bottom > 0;

    return Semantics(
      button: true,
      label: visible
          ? 'terminalKeyboardHide'.tr()
          : 'terminalKeyboardShow'.tr(),
      onTap: _press,
      child: ExcludeFocus(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _press,
          child: Container(
            width: _width,
            height: TerminalKeyBar._capHeight,
            alignment: Alignment.center,
            // The keyboard key is drawn as one of the caps: same height, same
            // fill, same radius, so the deck reads as one piece of hardware
            // rather than a row of keys with a toggle bolted on.
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.all(
                Radius.circular(MaidKitRadius.chip),
              ),
            ),
            // The icon shows what the key does next, not the IME's state: a
            // keyboard icon raises it, a hidden one puts it away.
            child: Icon(
              visible ? Symbols.keyboard_hide : Symbols.keyboard,
              size: 22,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  void _press() {
    HapticFeedback.selectionClick();
    // Putting the keyboard away means releasing the terminal, not only closing
    // the IME: the renderer raises it again on focus gain, so a hide that kept
    // focus would leave the user unable to get it back by tapping the
    // terminal.
    if (View.of(context).viewInsets.bottom > 0) {
      widget.terminal.unfocus();
    } else {
      widget.terminal.showKeyboard();
    }
  }
}
