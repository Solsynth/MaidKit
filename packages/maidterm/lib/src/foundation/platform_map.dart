import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:libghostty/libghostty.dart' show Key;

/// Maps Flutter [LogicalKeyboardKey]s to libghostty keys for input events
/// that carry no physical key. Soft keyboards on Android synthesize
/// backspace/enter/arrow events through the IME, and the engine reports them
/// with [PhysicalKeyboardKey.none], so the physical-key map alone drops them.
final Map<LogicalKeyboardKey, Key> _logicalKeyMap = {
  LogicalKeyboardKey.backspace: Key.backspace,
  LogicalKeyboardKey.delete: Key.delete,
  LogicalKeyboardKey.enter: Key.enter,
  LogicalKeyboardKey.tab: Key.tab,
  LogicalKeyboardKey.space: Key.space,
  LogicalKeyboardKey.escape: Key.escape,
  LogicalKeyboardKey.arrowUp: Key.arrowUp,
  LogicalKeyboardKey.arrowDown: Key.arrowDown,
  LogicalKeyboardKey.arrowLeft: Key.arrowLeft,
  LogicalKeyboardKey.arrowRight: Key.arrowRight,
  LogicalKeyboardKey.home: Key.home,
  LogicalKeyboardKey.end: Key.end,
  LogicalKeyboardKey.pageUp: Key.pageUp,
  LogicalKeyboardKey.pageDown: Key.pageDown,
  LogicalKeyboardKey.insert: Key.insert,
};

final Map<int, Key> _codepointToKey = {
  0x20: Key.space,
  0x21: Key.digit1,
  0x22: Key.quote,
  0x23: Key.digit3,
  0x24: Key.digit4,
  0x25: Key.digit5,
  0x26: Key.digit7,
  0x27: Key.quote,
  0x28: Key.digit9,
  0x29: Key.digit0,
  0x2a: Key.digit8,
  0x2b: Key.equal,
  0x2c: Key.comma,
  0x2d: Key.minus,
  0x2e: Key.period,
  0x2f: Key.slash,
  for (var i = 0; i < 26; i++) 0x61 + i: Key.values[Key.a.index + i],
  for (var i = 0; i < 26; i++) 0x41 + i: Key.values[Key.a.index + i],
  for (var i = 0; i < 10; i++) 0x30 + i: Key.values[Key.digit0.index + i],
  0x3a: Key.semicolon,
  0x3b: Key.semicolon,
  0x3c: Key.comma,
  0x3d: Key.equal,
  0x3e: Key.period,
  0x3f: Key.slash,
  0x40: Key.digit2,
  0x5b: Key.bracketLeft,
  0x5c: Key.backslash,
  0x5d: Key.bracketRight,
  0x5e: Key.digit6,
  0x5f: Key.minus,
  0x60: Key.backquote,
  0x7b: Key.bracketLeft,
  0x7c: Key.backslash,
  0x7d: Key.bracketRight,
  0x7e: Key.backquote,
};

final Map<PhysicalKeyboardKey, Key> _keyMap = {
  PhysicalKeyboardKey.backquote: Key.backquote,
  PhysicalKeyboardKey.backslash: Key.backslash,
  PhysicalKeyboardKey.bracketLeft: Key.bracketLeft,
  PhysicalKeyboardKey.bracketRight: Key.bracketRight,
  PhysicalKeyboardKey.comma: Key.comma,
  PhysicalKeyboardKey.equal: Key.equal,
  PhysicalKeyboardKey.minus: Key.minus,
  PhysicalKeyboardKey.period: Key.period,
  PhysicalKeyboardKey.quote: Key.quote,
  PhysicalKeyboardKey.semicolon: Key.semicolon,
  PhysicalKeyboardKey.slash: Key.slash,
  PhysicalKeyboardKey.intlBackslash: Key.intlBackslash,
  PhysicalKeyboardKey.intlRo: Key.intlRo,
  PhysicalKeyboardKey.intlYen: Key.intlYen,

  PhysicalKeyboardKey.digit0: Key.digit0,
  PhysicalKeyboardKey.digit1: Key.digit1,
  PhysicalKeyboardKey.digit2: Key.digit2,
  PhysicalKeyboardKey.digit3: Key.digit3,
  PhysicalKeyboardKey.digit4: Key.digit4,
  PhysicalKeyboardKey.digit5: Key.digit5,
  PhysicalKeyboardKey.digit6: Key.digit6,
  PhysicalKeyboardKey.digit7: Key.digit7,
  PhysicalKeyboardKey.digit8: Key.digit8,
  PhysicalKeyboardKey.digit9: Key.digit9,

  PhysicalKeyboardKey.keyA: Key.a,
  PhysicalKeyboardKey.keyB: Key.b,
  PhysicalKeyboardKey.keyC: Key.c,
  PhysicalKeyboardKey.keyD: Key.d,
  PhysicalKeyboardKey.keyE: Key.e,
  PhysicalKeyboardKey.keyF: Key.f,
  PhysicalKeyboardKey.keyG: Key.g,
  PhysicalKeyboardKey.keyH: Key.h,
  PhysicalKeyboardKey.keyI: Key.i,
  PhysicalKeyboardKey.keyJ: Key.j,
  PhysicalKeyboardKey.keyK: Key.k,
  PhysicalKeyboardKey.keyL: Key.l,
  PhysicalKeyboardKey.keyM: Key.m,
  PhysicalKeyboardKey.keyN: Key.n,
  PhysicalKeyboardKey.keyO: Key.o,
  PhysicalKeyboardKey.keyP: Key.p,
  PhysicalKeyboardKey.keyQ: Key.q,
  PhysicalKeyboardKey.keyR: Key.r,
  PhysicalKeyboardKey.keyS: Key.s,
  PhysicalKeyboardKey.keyT: Key.t,
  PhysicalKeyboardKey.keyU: Key.u,
  PhysicalKeyboardKey.keyV: Key.v,
  PhysicalKeyboardKey.keyW: Key.w,
  PhysicalKeyboardKey.keyX: Key.x,
  PhysicalKeyboardKey.keyY: Key.y,
  PhysicalKeyboardKey.keyZ: Key.z,

  PhysicalKeyboardKey.altLeft: Key.altLeft,
  PhysicalKeyboardKey.altRight: Key.altRight,
  PhysicalKeyboardKey.controlLeft: Key.controlLeft,
  PhysicalKeyboardKey.controlRight: Key.controlRight,
  PhysicalKeyboardKey.metaLeft: Key.metaLeft,
  PhysicalKeyboardKey.metaRight: Key.metaRight,
  PhysicalKeyboardKey.shiftLeft: Key.shiftLeft,
  PhysicalKeyboardKey.shiftRight: Key.shiftRight,
  PhysicalKeyboardKey.capsLock: Key.capsLock,
  PhysicalKeyboardKey.numLock: Key.numLock,

  PhysicalKeyboardKey.backspace: Key.backspace,
  PhysicalKeyboardKey.enter: Key.enter,
  PhysicalKeyboardKey.space: Key.space,
  PhysicalKeyboardKey.tab: Key.tab,

  PhysicalKeyboardKey.arrowDown: Key.arrowDown,
  PhysicalKeyboardKey.arrowLeft: Key.arrowLeft,
  PhysicalKeyboardKey.arrowRight: Key.arrowRight,
  PhysicalKeyboardKey.arrowUp: Key.arrowUp,
  PhysicalKeyboardKey.delete: Key.delete,
  PhysicalKeyboardKey.end: Key.end,
  PhysicalKeyboardKey.home: Key.home,
  PhysicalKeyboardKey.insert: Key.insert,
  PhysicalKeyboardKey.pageDown: Key.pageDown,
  PhysicalKeyboardKey.pageUp: Key.pageUp,

  PhysicalKeyboardKey.escape: Key.escape,
  PhysicalKeyboardKey.f1: Key.f1,
  PhysicalKeyboardKey.f2: Key.f2,
  PhysicalKeyboardKey.f3: Key.f3,
  PhysicalKeyboardKey.f4: Key.f4,
  PhysicalKeyboardKey.f5: Key.f5,
  PhysicalKeyboardKey.f6: Key.f6,
  PhysicalKeyboardKey.f7: Key.f7,
  PhysicalKeyboardKey.f8: Key.f8,
  PhysicalKeyboardKey.f9: Key.f9,
  PhysicalKeyboardKey.f10: Key.f10,
  PhysicalKeyboardKey.f11: Key.f11,
  PhysicalKeyboardKey.f12: Key.f12,
  PhysicalKeyboardKey.f13: Key.f13,
  PhysicalKeyboardKey.f14: Key.f14,
  PhysicalKeyboardKey.f15: Key.f15,
  PhysicalKeyboardKey.f16: Key.f16,
  PhysicalKeyboardKey.f17: Key.f17,
  PhysicalKeyboardKey.f18: Key.f18,
  PhysicalKeyboardKey.f19: Key.f19,
  PhysicalKeyboardKey.f20: Key.f20,
  PhysicalKeyboardKey.f21: Key.f21,
  PhysicalKeyboardKey.f22: Key.f22,
  PhysicalKeyboardKey.f23: Key.f23,
  PhysicalKeyboardKey.f24: Key.f24,

  PhysicalKeyboardKey.numpad0: Key.numpad0,
  PhysicalKeyboardKey.numpad1: Key.numpad1,
  PhysicalKeyboardKey.numpad2: Key.numpad2,
  PhysicalKeyboardKey.numpad3: Key.numpad3,
  PhysicalKeyboardKey.numpad4: Key.numpad4,
  PhysicalKeyboardKey.numpad5: Key.numpad5,
  PhysicalKeyboardKey.numpad6: Key.numpad6,
  PhysicalKeyboardKey.numpad7: Key.numpad7,
  PhysicalKeyboardKey.numpad8: Key.numpad8,
  PhysicalKeyboardKey.numpad9: Key.numpad9,
  PhysicalKeyboardKey.numpadAdd: Key.numpadAdd,
  PhysicalKeyboardKey.numpadDecimal: Key.numpadDecimal,
  PhysicalKeyboardKey.numpadDivide: Key.numpadDivide,
  PhysicalKeyboardKey.numpadEnter: Key.numpadEnter,
  PhysicalKeyboardKey.numpadEqual: Key.numpadEqual,
  PhysicalKeyboardKey.numpadMultiply: Key.numpadMultiply,
  PhysicalKeyboardKey.numpadSubtract: Key.numpadSubtract,
  PhysicalKeyboardKey.numpadComma: Key.numpadComma,
  PhysicalKeyboardKey.numpadParenLeft: Key.numpadParenLeft,
  PhysicalKeyboardKey.numpadParenRight: Key.numpadParenRight,

  PhysicalKeyboardKey.contextMenu: Key.contextMenu,
  PhysicalKeyboardKey.printScreen: Key.printScreen,
  PhysicalKeyboardKey.scrollLock: Key.scrollLock,
  PhysicalKeyboardKey.pause: Key.pause,
  PhysicalKeyboardKey.fn: Key.fn,

  PhysicalKeyboardKey.convert: Key.convert,
  PhysicalKeyboardKey.nonConvert: Key.nonConvert,
  PhysicalKeyboardKey.kanaMode: Key.kanaMode,

  PhysicalKeyboardKey.audioVolumeDown: Key.audioVolumeDown,
  PhysicalKeyboardKey.audioVolumeMute: Key.audioVolumeMute,
  PhysicalKeyboardKey.audioVolumeUp: Key.audioVolumeUp,
};

final Map<Key, int> _keyToCodepoint = {
  Key.backquote: 0x60,
  Key.backslash: 0x5c,
  Key.bracketLeft: 0x5b,
  Key.bracketRight: 0x5d,
  Key.comma: 0x2c,
  for (var i = 0; i < 26; i++) Key.values[Key.a.index + i]: 0x61 + i,
  for (var i = 0; i < 10; i++) Key.values[Key.digit0.index + i]: 0x30 + i,
  Key.equal: 0x3d,
  Key.minus: 0x2d,
  Key.period: 0x2e,
  Key.quote: 0x27,
  Key.semicolon: 0x3b,
  Key.slash: 0x2f,
};

/// Maps a Unicode [codepoint] to the corresponding libghostty [Key].
///
/// Covers ASCII letters, digits, space, and US-layout punctuation. Shifted
/// characters map to the same physical key as their unshifted pair.
Key? keyFromCodepoint(int codepoint) => _codepointToKey[codepoint];

/// Maps a Flutter [PhysicalKeyboardKey] to the corresponding libghostty [Key].
///
/// Covers the full US keyboard layout including function keys (F1-F24),
/// numpad, navigation keys, modifier keys, and international keys.
/// Returns [Key.unidentified] for unmapped physical keys.
Key keyFromPhysical(PhysicalKeyboardKey physical) {
  return _keyMap[physical] ?? .unidentified;
}

/// Maps a Flutter [LogicalKeyboardKey] to the corresponding libghostty [Key].
///
/// Used for input events synthesized by soft keyboards and IMEs, which
/// Android reports without a physical key. Returns `null` for logical keys
/// with no terminal counterpart.
Key? keyFromLogical(LogicalKeyboardKey logical) => _logicalKeyMap[logical];

/// Returns the lowercase ASCII codepoint for [key], or 0 for non-character
/// keys. Punctuation keys report their US-layout unshifted codepoint.
///
/// Used by the key encoder to determine the unshifted codepoint that
/// libghostty expects for keyboard input encoding.
int unshiftedCodepointForKey(Key key) => _keyToCodepoint[key] ?? 0;
