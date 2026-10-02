# Terminal emulator adapters

## Purpose

MaidKit attaches one terminal emulator to each session and renders it behind a
single renderer-neutral contract. Transport code (`SshConnectionManager`,
`SerialConnectionManager`, `MaidCafeTerminalConnectionManager`) only forwards
bytes and reacts to input and resize events, so it never imports a concrete
emulator package. The contract itself is
`lib/servers/terminal_session_adapter.dart`.

## Backends

| Platform | File | Engine |
| --- | --- | --- |
| Android, iOS, macOS, Windows, Linux | `lib/servers/maidterm_session_adapter.dart` | MaidTerm over libghostty (native library) |
| Web | `lib/servers/xterm3_session_adapter.dart` | `xterm3` (pure Dart emulator) |

libghostty is reached over `dart:ffi` and built by a native-assets hook, so it
cannot exist in a `dart2js` build; xterm3's emulator core has no platform
dependency at all. Both backends implement `TerminalSessionAdapter` and are
interchangeable from the caller's point of view.

## Selecting a backend

`lib/servers/terminal_renderer_backend.dart` is the only place that knows which
renderer a build gets:

```dart
export 'maidterm_session_adapter.dart'
    if (dart.library.js_interop) 'xterm3_session_adapter.dart';
```

`dart.library.js_interop` is available exactly on the web targets, so the
choice is made at compile time: a web build never links MaidTerm, and a native
build never links xterm3. Both files declare `TerminalRendererFactory` with the
same constructor, which is why the export can switch between them.

`terminalSessionAdapterFactoryProvider` in `lib/servers/server_providers.dart`
is the single construction point for production code; tests override the
provider instead of the renderer.

## Contract

`TerminalSessionAdapter` covers everything a session needs from a renderer:

- `outgoingBytes` / `write` — the byte streams shared with the transport.
- `resizeEvents` — column/row plus physical-pixel viewport size for PTY
  resizing.
- `taskRunning` / `taskActivity` — shell activity for tab indicators, driven by
  `TerminalActivityTracker` (OSC 133/633, OSC 9;4, then a conservative
  prompt-detection fallback).
- `currentDirectory` — the OSC 7 working directory.
- `find` / `findJump` / `findClear` — terminal find, hosted by
  `TerminalFindHost`.
- `bufferRows` / `dumpHistory` / `replayHistory` — scrollback capture and
  restore for session persistence.
- `sudoAutofillReady` / `bindSudoAutofill` — the reason the terminal currently
  wants the saved password, surfaced as a hint at the cursor.
- `buildView` — the renderer widget, including read-only log surfaces.

Renderer-neutral inputs (`terminal_color_scheme.dart`,
`terminal_keyword_highlight.dart`, `terminal_adapter_preferences.dart`) are
translated inside each backend, so preferences apply to both.

## Renderer-specific behaviour

- **Cursor animation** is a renderer setting for MaidTerm and DEC mode 12 for
  xterm3; the web backend applies the preference with the same escape a remote
  program would use.
- **Keyword and link tinting** uses MaidTerm's link rules natively. xterm3 has
  no equivalent, so the web backend computes matches for the rows on screen and
  paints them with `TerminalController` highlights, coalesced to one pass per
  250 ms and capped at 400 matches.
- **Desktop notifications** from OSC 9/777 are shown natively. A browser build
  has no notification plugin wired up, so the web backend ignores the request.
- **PTY pixel metrics** are reported to the transport by both backends, but in
  a browser only the MaidCafe-over-WebSocket transport and the no-op serial
  transport can consume them; SSH needs raw sockets and cannot run on web.
- **Soft-keyboard re-raising** is a ghostty-backend concern on Android: the
  platform dismisses the IME (its hide key, the back gesture) without moving
  focus, so MaidTerm's `KeyboardState` stays `showing` and its focus-driven
  re-show never fires again. The backend reveals the keyboard on tap-like
  touches — raw pointer events, so MaidTerm's own tap recognizer keeps winning
  the arena — and `showKeyboard` drops through `hidden` whenever the platform
  reports no IME height. Other platforms move focus instead and need nothing
  extra.

## Adding or replacing a backend

1. Implement `TerminalSessionAdapter` in a new `lib/servers/<renderer>_session_adapter.dart`
   together with a `TerminalRendererFactory`.
2. Point `terminal_renderer_backend.dart` at the new file for the platform it
   serves.
3. Keep the renderer package out of every other file, so the platform split
   stays in one place.

## Verification

```sh
dart format lib test
flutter analyze
flutter test
```

The web backend also has to compile for `dart2js`. A full `flutter build web`
still stops on the parts of the app that have not been ported yet (`dart:io`
imports, desktop-only plugins), so the renderer path is checked on its own:

```sh
flutter build web --release -t tool/web_renderer_probe.dart
```

The probe imports `terminal_renderer_backend.dart` and nothing else, which
proves the conditional export selects the xterm3 backend for web and that the
shared contract compiles without MaidTerm.
