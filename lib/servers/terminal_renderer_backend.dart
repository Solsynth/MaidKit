/// Picks the terminal renderer for the platform being compiled.
///
/// MaidKit renders terminals with MaidTerm's libghostty backend on native
/// platforms and with xterm3 in browsers: libghostty is reached through
/// `dart:ffi` and a native-assets build, so it cannot exist in a `dart2js`
/// build, while xterm3's emulator core is pure Dart and can run anywhere.
///
/// `dart.library.js_interop` is available exactly on the web targets, so the
/// selection happens at compile time — a web build never links MaidTerm, and a
/// native build never links xterm3. Callers import this file and use
/// [TerminalRendererFactory] without caring which renderer is behind it.
library;

export 'maidterm_session_adapter.dart'
    if (dart.library.js_interop) 'xterm3_session_adapter.dart';
