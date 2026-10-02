import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';
import 'package:maid_kit/servers/server_models.dart';

void main() {
  group('serverHealthFromWire', () {
    test(
      'keeps a zero score, which is a critical reading and not an absent one',
      () {
        final health = serverHealthFromWire(0, 'critical');

        expect(health, isNotNull);
        expect(health!.score, 0);
        expect(health.status, ServerHealthStatus.critical);
      },
    );

    test('refuses a half-reported or out-of-range reading', () {
      // Health is all-or-nothing: without both halves no surface can name a
      // band, and a bare score would read as a live number.
      expect(serverHealthFromWire(84, null), isNull);
      expect(serverHealthFromWire(null, 'healthy'), isNull);
      // `unknown` is what the cloud reports for a pre-health sample.
      expect(serverHealthFromWire(84, 'unknown'), isNull);
      expect(serverHealthFromWire(140, 'healthy'), isNull);
      expect(serverHealthFromWire(-1, 'healthy'), isNull);
    });
  });

  group('parseMaidCafeServerStats health', () {
    test('reads the score that rides the metric payload', () {
      final stats = parseMaidCafeServerStats(const {
        'uptime_seconds': 10,
        'health_score': 84,
        'health_status': 'degraded',
      });

      expect(stats!.health!.score, 84);
      expect(stats.health!.status, ServerHealthStatus.degraded);
    });

    test('reports no health for a daemon older than the health feature', () {
      final stats = parseMaidCafeServerStats(const {'uptime_seconds': 10});

      expect(stats, isNotNull);
      expect(stats!.health, isNull);
    });
  });

  group('parseMaidCafeHealthReport', () {
    test('reads the score, every dimension and the skipped ones', () {
      final report = parseMaidCafeHealthReport(const {
        'score': 84,
        'status': 'degraded',
        'evaluated_at': '2026-08-15T12:00:00Z',
        'host_id': 'host-1',
        'checks': [
          {
            'name': 'cpu',
            'status': 'ok',
            'score': 100,
            'value': 12.3,
            'unit': 'percent',
            'warn': 75,
            'crit': 95,
          },
          {
            'name': 'disk',
            'status': 'warning',
            'score': 33.3,
            'value': 90,
            'unit': 'percent',
            'detail': '/var',
            'warn': 80,
            'crit': 95,
            'message': 'Disk usage /var at 90.0% (warn 80.0%, crit 95.0%)',
          },
          {
            'name': 'swap',
            'status': 'ok',
            'score': 100,
            'value': 0,
            'unit': 'percent',
            'warn': 50,
            'crit': 90,
            'skipped': true,
          },
        ],
        'issues': ['Disk usage /var at 90.0% (warn 80.0%, crit 95.0%)'],
      });

      expect(report, isNotNull);
      expect(report!.health.score, 84);
      expect(report.health.status, ServerHealthStatus.degraded);
      expect(report.hostId, 'host-1');
      expect(report.evaluatedAt, DateTime.utc(2026, 8, 15, 12));
      expect(report.checks, hasLength(3));
      expect(report.checks[0].name, 'cpu');
      expect(report.checks[0].status, MaidCafeHealthCheckStatus.ok);
      expect(report.checks[1].detail, '/var');
      expect(report.checks[1].status, MaidCafeHealthCheckStatus.warning);
      expect(report.checks[1].crit, 95);
      expect(report.checks[2].skipped, isTrue);
      // Only a dimension that crossed a threshold is an issue, and a skipped
      // one never is — that is what keeps the summary line honest.
      expect(report.issues, hasLength(1));
      expect(report.issues.single.name, 'disk');
    });

    test('returns null when the body carries no usable score', () {
      expect(parseMaidCafeHealthReport(const {}), isNull);
      expect(parseMaidCafeHealthReport(const {'score': 84}), isNull);
      expect(
        parseMaidCafeHealthReport(const {'score': 84, 'status': 'unknown'}),
        isNull,
      );
    });

    test('drops dimensions it cannot read instead of the whole report', () {
      final report = parseMaidCafeHealthReport(const {
        'score': 90,
        'status': 'healthy',
        'checks': [
          {'name': 'cpu'},
          {'status': 'ok', 'value': 1},
          'not a check',
          {
            'name': 'memory',
            'status': 'ok',
            'score': 100,
            'value': 40,
            'unit': 'percent',
            'warn': 80,
            'crit': 95,
          },
        ],
      });

      expect(report!.checks, hasLength(1));
      expect(report.checks.single.name, 'memory');
    });
  });

  group('formatMaidCafeHealthValue', () {
    test('renders each unit the way the daemon measures it', () {
      expect(formatMaidCafeHealthValue('percent', 12.34), '12.3%');
      expect(formatMaidCafeHealthValue('ratio', 0.085), '8.5%');
      expect(formatMaidCafeHealthValue('per_core', 0.4213), '0.42');
      expect(
        formatMaidCafeHealthValue('bytes', (512 << 20).toDouble()),
        '512.0 MiB',
      );
      expect(
        formatMaidCafeHealthValue('bytes', (2 << 30).toDouble()),
        '2.0 GiB',
      );
      expect(formatMaidCafeHealthValue('bytes', 900), '900 B');
      expect(formatMaidCafeHealthValue('unknown_unit', 3.25), '3.3');
    });
  });
}
