import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/window_placement.dart';

/// Work areas of the machine that reported the shrink: a 1512x982 built-in
/// display with a 1253x985 Sidecar display arranged to its left, so windows on
/// the Sidecar have negative coordinates.
const _builtIn = Rect.fromLTWH(0, 33, 1512, 949);
const _sidecar = Rect.fromLTWH(-1253, 0, 1253, 985);
const _minimumSize = Size(390, 520);

const _screenRetrieverChannel = MethodChannel(
  'dev.leanflutter.plugins/screen_retriever',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recoveryFrameFor', () {
    test(
      'keeps a saved frame sitting on a display left of the primary one',
      () {
        expect(
          recoveryFrameFor(
            saved: const Rect.fromLTWH(-1253, 0, 1253, 985),
            displays: const [_builtIn, _sidecar],
            minimumSize: _minimumSize,
          ),
          isNull,
        );
      },
    );

    test('keeps a saved frame that only partly overlaps a display', () {
      expect(
        recoveryFrameFor(
          saved: const Rect.fromLTWH(1300, 700, 900, 700),
          displays: const [_builtIn, _sidecar],
          minimumSize: _minimumSize,
        ),
        isNull,
      );
    });

    test('moves a frame left on a detached display, keeping its size', () {
      // A display that used to sit right of the built-in one is gone.
      expect(
        recoveryFrameFor(
          saved: const Rect.fromLTWH(2000, 100, 1200, 800),
          displays: const [_builtIn, _sidecar],
          minimumSize: _minimumSize,
        ),
        const Rect.fromLTWH(156, 107.5, 1200, 800),
      );
    });

    test('clamps a saved frame that is larger than the remaining display', () {
      final frame = recoveryFrameFor(
        saved: const Rect.fromLTWH(3000, 0, 4000, 3000),
        displays: const [_builtIn, _sidecar],
        minimumSize: _minimumSize,
      );

      expect(frame, _builtIn);
    });

    test('never shrinks a recovered frame below the minimum size', () {
      expect(
        recoveryFrameFor(
          saved: const Rect.fromLTWH(5000, 5000, 100, 100),
          displays: const [_builtIn, _sidecar],
          minimumSize: _minimumSize,
        ),
        const Rect.fromLTWH(561, 247.5, 390, 520),
      );
    });

    test('fits the frame into a display smaller than the minimum size', () {
      expect(
        recoveryFrameFor(
          saved: const Rect.fromLTWH(5000, 5000, 100, 100),
          displays: const [Rect.fromLTWH(0, 0, 300, 400)],
          minimumSize: _minimumSize,
        ),
        const Rect.fromLTWH(0, 0, 300, 400),
      );
    });

    test(
      'leaves the saved frame alone when the platform reports no displays',
      () {
        expect(
          recoveryFrameFor(
            saved: const Rect.fromLTWH(9000, 9000, 800, 600),
            displays: const [],
            minimumSize: _minimumSize,
          ),
          isNull,
        );
      },
    );
  });

  group('loadDisplayWorkAreas', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_screenRetrieverChannel, null);
    });

    test('reads the work area of every attached display', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_screenRetrieverChannel, (call) async {
            expect(call.method, 'getAllDisplays');
            return {
              'displays': [
                {
                  'id': '1',
                  'name': 'Built-in Retina Display',
                  'size': {'width': 1512.0, 'height': 982.0},
                  'visiblePosition': {'dx': 0.0, 'dy': 33.0},
                  'visibleSize': {'width': 1512.0, 'height': 949.0},
                },
                {
                  'id': '2',
                  'name': 'Sidecar Display',
                  'size': {'width': 1253.0, 'height': 985.0},
                  'visiblePosition': {'dx': -1253.0, 'dy': 0.0},
                  'visibleSize': {'width': 1253.0, 'height': 985.0},
                },
              ],
            };
          });

      expect(await loadDisplayWorkAreas(), const [_builtIn, _sidecar]);
    });

    test(
      'falls back to the display size when no visible size is given',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_screenRetrieverChannel, (call) async {
              return {
                'displays': [
                  {
                    'id': '1',
                    'name': 'Built-in Retina Display',
                    'size': {'width': 1512.0, 'height': 982.0},
                    'visiblePosition': {'dx': 0.0, 'dy': 33.0},
                  },
                ],
              };
            });

        expect(await loadDisplayWorkAreas(), const [
          Rect.fromLTWH(0, 33, 1512, 982),
        ]);
      },
    );

    test('reports no work areas when the platform call fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_screenRetrieverChannel, (call) async {
            throw PlatformException(code: 'unavailable');
          });

      expect(await loadDisplayWorkAreas(), isEmpty);
    });
  });
}
