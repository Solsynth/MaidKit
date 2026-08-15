import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

/// A session stub that only tracks close() — the registry never uses the
/// transport members of a session it hands out.
class _FakeSession implements MaidCafeStreamSession {
  _FakeSession(this.id);

  final int id;
  bool closed = false;

  @override
  String? get apiSecret => null;

  @override
  bool get isClosed => closed;

  @override
  String? get version => null;

  @override
  Future<Map<String, dynamic>> health() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> metrics() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> containers() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> images() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> processes() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> systemd() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> metricsHistory({
    int limit = 60,
    DateTime? from,
    DateTime? to,
    DateTime? before,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> invokeAction(String name, {Object? body}) =>
      throw UnimplementedError();

  @override
  Future<List<MaidCafeAuditEntry>> audit({int limit = 50}) =>
      throw UnimplementedError();

  @override
  Stream<MaidCafeStreamEvent> openStream({
    Set<MaidCafeStreamEventType> events = maidCafeStreamAllEvents,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('MaidCafeSessionEntry', () {
    test(
      'opens once and serves the same session to concurrent callers',
      () async {
        final entry = MaidCafeSessionEntry();
        var opens = 0;
        Future<MaidCafeStreamSession> open(int? port) async {
          opens++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return _FakeSession(opens);
        }

        final results = await Future.wait([
          entry.resolve(open),
          entry.resolve(open),
          entry.resolve(open),
        ]);
        expect(opens, 1, reason: 'single-flight open');
        expect(results, everyElement(same(results.first)));
      },
    );

    test('returns the cached session without reopening', () async {
      final entry = MaidCafeSessionEntry();
      var opens = 0;
      final first = await entry.resolve((_) async => _FakeSession(++opens));
      final second = await entry.resolve((_) async => _FakeSession(++opens));
      expect(first, same(second));
      expect(opens, 1);
    });

    test('caches failures and only reopens when forced', () async {
      final entry = MaidCafeSessionEntry();
      var opens = 0;
      Future<MaidCafeStreamSession> open(int? port) async {
        opens++;
        if (opens == 1) throw StateError('daemon absent');
        return _FakeSession(opens);
      }

      expect(await entry.resolve(open), isNull);
      expect(await entry.resolve(open), isNull, reason: 'cached failure');
      expect(opens, 1);

      final forced = await entry.resolve(open, force: true);
      expect(forced, isNotNull);
      expect(opens, 2);
    });

    test('closeSession closes the live session and reopens fresh', () async {
      final entry = MaidCafeSessionEntry();
      var opens = 0;
      final first =
          (await entry.resolve((_) async => _FakeSession(++opens)))!
              as _FakeSession;

      entry.closeSession();
      expect(first.closed, isTrue);

      final second =
          (await entry.resolve((_) async => _FakeSession(++opens)))!
              as _FakeSession;
      expect(second.id, 2);
      expect(second.closed, isFalse);
    });

    test(
      'closeSession shuts down a still-pending open (orphan guard)',
      () async {
        final entry = MaidCafeSessionEntry();
        _FakeSession? opened;
        final pending = entry.resolve((_) async {
          final session = _FakeSession(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          opened = session;
          return session;
        });

        entry.closeSession();
        final result = await pending;
        expect(result, isNotNull);
        // The orphan-guard close races the open completion; eventually the
        // session must end up closed.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(opened!.closed, isTrue);
      },
    );
  });
}
