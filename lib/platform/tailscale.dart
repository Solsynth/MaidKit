/// Picks the embedded-Tailscale implementation for the platform being compiled.
///
/// `package:tailscale` is reached through `dart:ffi` and a native-assets build,
/// so it cannot exist in a `dart2js` build. `dart.library.js_interop` is
/// available exactly on the web targets, so the selection happens at compile
/// time: a web build links [tailscale_web] (which reports "unsupported" and
/// throws instead of touching the native runtime), a native build links
/// [tailscale_native] (the real package). Callers import this file and gate
/// runtime use on `tailscaleRuntimeSupported`.
library;

export 'tailscale_native.dart'
    if (dart.library.js_interop) 'tailscale_web.dart';
