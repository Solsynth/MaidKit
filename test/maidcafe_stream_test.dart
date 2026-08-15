import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

List<int> _bytes(String text) => utf8.encode(text);

Future<List<MaidCafeStreamEvent>> _frames(String text) =>
    parseMaidCafeSseFrames(Stream.value(_bytes(text))).toList();

void main() {
  group('parseMaidCafeSseFrames', () {
    test('parses hello and metric frames from bytes', () async {
      final events = await _frames(
        'event: hello\ndata: {"stream":"v1","version":"0.1.0"}\n\n'
        'event: metric\ndata: {"cpu_percent":1.2,"sent_at":"2026-08-15T00:00:00Z"}\n\n',
      );
      expect(events, hasLength(2));
      expect(events[0].type, MaidCafeStreamEventType.hello);
      expect(events[0].data['stream'], 'v1');
      expect(events[1].type, MaidCafeStreamEventType.metric);
      expect(events[1].data['cpu_percent'], 1.2);
      expect(events[1].data['sent_at'], '2026-08-15T00:00:00Z');
    });

    test(
      'ignores comment lines and joins multi-line data with newlines',
      () async {
        final events = await _frames(
          ': ping\n\n'
          'event: processes\n'
          'data: {"processes":[\n'
          'data: {"pid":1,"user":"root"},\n'
          'data: {"pid":2,"user":"nobody"}]\n'
          'data: }\n\n',
        );
        expect(events, hasLength(1));
        expect(events[0].type, MaidCafeStreamEventType.processes);
        final processes = events[0].data['processes'] as List;
        expect(processes, hasLength(2));
        expect(processes[1]['pid'], 2);
      },
    );

    test('skips frames with unknown event names', () async {
      final events = await _frames(
        'event: unknown\ndata: {"anything":true}\n\n'
        'event: metric\ndata: {"cpu_percent":3.0}\n\n',
      );
      expect(events, hasLength(1));
      expect(events[0].type, MaidCafeStreamEventType.metric);
    });

    test('skips frames with malformed JSON or no event name', () async {
      final events = await _frames(
        'event: metric\ndata: {not json}\n\n'
        'data: {"cpu_percent":1.0}\n\n'
        'event: metric\n\n'
        ': comment only\n\n',
      );
      expect(events, isEmpty);
    });

    test('strips a single leading space after data:', () async {
      final events = await _frames(
        'event: metric\ndata: {"cpu_percent": 7.5}\n\n',
      );
      expect(events, hasLength(1));
      expect(events[0].data['cpu_percent'], 7.5);
    });
  });

  group('parseMaidCafeContainers', () {
    test('maps runtimes incl. compose_project', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {
            'runtime': 'podman',
            'available': true,
            'error': null,
            'containers': [
              {
                'id': 'abc123',
                'name': 'web',
                'image': 'nginx:1.25',
                'state': 'running',
                'status': 'Up 2 hours',
                'compose_project': 'myapp',
              },
            ],
          },
        ],
      });
      expect(snapshot.hasRuntimes, isTrue);
      final runtime = snapshot.runtimes.single;
      expect(runtime.runtime, 'podman');
      expect(runtime.available, isTrue);
      expect(runtime.error, isNull);
      expect(runtime.containers, hasLength(1));
      final container = runtime.containers.single;
      expect(container.id, 'abc123');
      expect(container.name, 'web');
      expect(container.image, 'nginx:1.25');
      expect(container.state, 'running');
      expect(container.status, 'Up 2 hours');
      expect(container.composeProject, 'myapp');
    });

    test('skips malformed entries and reports an empty runtimes list', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {'available': true, 'containers': []},
          {
            'runtime': 'docker',
            'containers': [
              {'name': 'no-id'},
              {'id': 'x', 'name': 42},
              'not a map',
              null,
            ],
          },
        ],
      });
      expect(snapshot.hasRuntimes, isTrue);
      expect(snapshot.runtimes.single.runtime, 'docker');
      expect(snapshot.runtimes.single.containers, isEmpty);
    });

    test('reports no runtimes when the daemon found no runtime', () {
      final snapshot = parseMaidCafeContainers({'runtimes': []});
      expect(snapshot.hasRuntimes, isFalse);
      expect(snapshot.runtimes, isEmpty);
    });

    test('keeps per-runtime errors and defaults missing scalars', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {
            'runtime': 'docker',
            'available': 'yes',
            'error': 'list containers: boom',
            'containers': [
              {'id': 'id1', 'name': 'n1'},
            ],
          },
        ],
      });
      final runtime = snapshot.runtimes.single;
      expect(runtime.available, isTrue);
      expect(runtime.error, 'list containers: boom');
      final container = runtime.containers.single;
      expect(container.image, '');
      expect(container.state, '');
      expect(container.status, '');
      expect(container.composeProject, isNull);
    });
  });

  group('parseMaidCafeProcesses', () {
    test('maps a valid payload with tolerant numeric conversion', () {
      final snapshot = parseMaidCafeProcesses({
        'processes': [
          {
            'pid': 123,
            'user': 'root',
            'cpu_percent': 1.2,
            'memory_percent': 0,
            'rss_kb': 12345,
            'command': 'nginx: worker process',
          },
        ],
      });
      final process = snapshot.processes.single;
      expect(process.pid, 123);
      expect(process.user, 'root');
      expect(process.cpuPercent, 1.2);
      expect(process.memoryPercent, 0.0);
      expect(process.rssKb, 12345);
      expect(process.command, 'nginx: worker process');
    });

    test('skips entries missing pid or user', () {
      final snapshot = parseMaidCafeProcesses({
        'processes': [
          {'user': 'root', 'cpu_percent': 1.0},
          {'pid': 2, 'cpu_percent': 1.0},
          {'pid': 'three', 'user': 'root'},
          {'pid': 4, 'user': 'root', 'cpu_percent': 'fast'},
        ],
      });
      expect(snapshot.processes, hasLength(1));
      expect(snapshot.processes.single.pid, 4);
      expect(snapshot.processes.single.cpuPercent, 0.0);
    });

    test('handles non-list payloads gracefully', () {
      final snapshot = parseMaidCafeProcesses({'processes': 'nope'});
      expect(snapshot.processes, isEmpty);
    });
  });

  group('parseMaidCafeSystemd', () {
    test('maps a valid payload incl. unit_file_state', () {
      final snapshot = parseMaidCafeSystemd({
        'available': true,
        'error': null,
        'units': [
          {
            'name': 'nginx.service',
            'load_state': 'loaded',
            'active_state': 'active',
            'sub_state': 'running',
            'description': 'A high performance web server',
            'unit_file_state': 'enabled',
          },
        ],
      });
      expect(snapshot.available, isTrue);
      expect(snapshot.error, isNull);
      final unit = snapshot.units.single;
      expect(unit.name, 'nginx.service');
      expect(unit.loadState, 'loaded');
      expect(unit.activeState, 'active');
      expect(unit.subState, 'running');
      expect(unit.description, 'A high performance web server');
      expect(unit.unitFileState, 'enabled');
    });

    test('defaults unit_file_state and skips malformed units', () {
      final snapshot = parseMaidCafeSystemd({
        'available': false,
        'error': 'systemctl not found',
        'units': [
          {'active_state': 'active'},
          {'name': 42},
          {'name': 'valid.service'},
        ],
      });
      expect(snapshot.available, isFalse);
      expect(snapshot.error, 'systemctl not found');
      expect(snapshot.units, hasLength(1));
      final unit = snapshot.units.single;
      expect(unit.name, 'valid.service');
      expect(unit.unitFileState, '');
      expect(unit.loadState, '');
      expect(unit.activeState, '');
    });
  });
}
