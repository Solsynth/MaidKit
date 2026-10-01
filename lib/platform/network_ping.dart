/// Picks the network-ping implementation for the platform being compiled.
///
/// `package:dart_ping` launches an OS `ping` process and, on iOS, an FFI-backed
/// native engine, so it cannot exist in a `dart2js` build.
/// `dart.library.js_interop` is available exactly on the web targets, so the
/// selection happens at compile time: a web build links [network_ping_web]
/// (which throws instead of probing), a native build links
/// [network_ping_native]. Callers gate runtime use on `kIsWeb`.
library;

export 'network_ping_native.dart'
    if (dart.library.js_interop) 'network_ping_web.dart';
