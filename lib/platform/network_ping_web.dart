/// Web stand-ins for `package:dart_ping`.
///
/// A browser cannot spawn `ping` and has no FFI native engine, so this file
/// keeps the names the app uses and throws [UnsupportedError] instead of
/// probing. The event types stay usable so callers can still type and branch on
/// them without a platform check; callers must gate runtime use on `kIsWeb`.
library;

/// Union of everything a ping run emits.
sealed class PingEvent {
  const PingEvent();
}

/// Each successful probe response.
final class PingResponse extends PingEvent {
  const PingResponse({this.seq, this.ttl, this.time, this.ip});

  /// Transmission sequence position identifier.
  final int? seq;

  /// Time-to-live.
  final int? ttl;

  /// Time it took for the packet to make a round trip.
  final Duration? time;

  /// IP address of the target.
  final String? ip;
}

/// Category of a probe failure.
enum ErrorType {
  timeToLiveExceeded('Time To Live Exceeded'),
  requestTimedOut('Request Timed Out'),
  unknownHost('Unknown Host'),
  unknown('Unknown Error'),
  noReply('No Reply'),
  noRoute('No Route');

  const ErrorType(this.message);

  /// Human-readable category name.
  final String message;
}

/// The probe/run error variant of [PingEvent].
final class PingError extends PingEvent {
  const PingError(this.error, {this.message, this.seq, this.ip});

  /// The category of the failure.
  final ErrorType error;

  /// Optional detail for the failure.
  final String? message;

  /// Probe sequence id, when the error names a probe.
  final int? seq;

  /// Hop IP, when present.
  final String? ip;
}

/// Ping instance used to launch a probe.
///
/// Unsupported on web: constructing one reports the unsupported platform.
final class Ping {
  factory Ping(String host, {int? count, int interval = 1, int timeout = 2}) =>
      throw UnsupportedError('Ping is unavailable on web');

  /// Stream of [PingEvent]s produced by the probe.
  Stream<PingEvent> get stream =>
      throw UnsupportedError('Ping.stream is unavailable on web');
}
