/// Native side of the network-ping facade.
///
/// `package:dart_ping` shells out to the platform's `ping` binary and, on iOS,
/// reaches the native engine through `dart:ffi`; `network_ping.dart` swaps this
/// file for `network_ping_web.dart` in `dart2js` builds.
library;

export 'package:dart_ping/dart_ping.dart'
    show ErrorType, Ping, PingError, PingEvent, PingResponse;
