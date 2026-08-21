// dart format off
part of 'sprite_face.dart';

Map<int, SpriteGlyph> buildBuiltinSpriteRegistry() {
  return <int, SpriteGlyph>{
    ..._boxDrawing(),
    ..._blockElements(),
    ..._braille(),
    ..._geometricShapes(),
    ..._powerline(),
    ..._branchDrawing(),
    ..._legacyComputing(),
    ..._legacyComputingSupplement(),
  };
}

const _boxLineData = [
  68, 136, 17, 34, -1, -1, -1, -1,
  -1, -1, -1, -1, 20, 24, 36, 40,
  80, 144, 96, 160, 5, 9, 6, 10,
  65, 129, 66, 130, 21, 25, 22, 37,
  38, 26, 41, 42, 81, 145, 82, 97,
  98, 146, 161, 162, 84, 148, 88, 152,
  100, 164, 104, 168, 69, 133, 73, 137,
  70, 134, 74, 138, 85, 149, 89, 153,
  86, 101, 102, 150, 90, 165, 105, 154,
  169, 166, 106, 170, -1, -1, -1, -1,
  204, 51, 28, 52, 60, 208, 112, 240,
  13, 7, 15, 193, 67, 195, 29, 55,
  63, 209, 115, 243, 220, 116, 252, 205,
  71, 207, 221, 119, 255, -1, -1, -1,
  -1, -1, -1, -1, 64, 1, 4, 16,
  128, 2, 8, 32, 72, 33, 132, 18,
];

const _boxSpecialCases = <int, SpriteGlyph>{
  0x2504: DashLine(horizontal: true, count: 3),
  0x2505: DashLine(horizontal: true, count: 3, heavy: true),
  0x2506: DashLine(horizontal: false, count: 3),
  0x2507: DashLine(horizontal: false, count: 3, heavy: true),
  0x2508: DashLine(horizontal: true, count: 4),
  0x2509: DashLine(horizontal: true, count: 4, heavy: true),
  0x250A: DashLine(horizontal: false, count: 4),
  0x250B: DashLine(horizontal: false, count: 4, heavy: true),
  0x254C: DashLine(horizontal: true, count: 2),
  0x254D: DashLine(horizontal: true, count: 2, heavy: true),
  0x254E: DashLine(horizontal: false, count: 2),
  0x254F: DashLine(horizontal: false, count: 2, heavy: true),
  0x256D: BoxArc(3),
  0x256E: BoxArc(2),
  0x256F: BoxArc(0),
  0x2570: BoxArc(1),
  0x2571: DiagonalLine(topLeftToBottomRight: false),
  0x2572: DiagonalLine(topLeftToBottomRight: true),
  0x2573: Composite([
    DiagonalLine(topLeftToBottomRight: false),
    DiagonalLine(topLeftToBottomRight: true),
  ]),
};

Map<int, SpriteGlyph> _boxDrawing() {
  final map = <int, SpriteGlyph>{};
  for (var i = 0; i < _boxLineData.length; i++) {
    final cp = 0x2500 + i;
    final value = _boxLineData[i];
    if (value >= 0) {
      map[cp] = BoxLines(
        up: value & 0x03,
        right: (value >> 2) & 0x03,
        down: (value >> 4) & 0x03,
        left: (value >> 6) & 0x03,
      );
    } else {
      final special = _boxSpecialCases[cp];
      if (special != null) map[cp] = special;
    }
  }
  return map;
}

Map<int, SpriteGlyph> _blockElements() {
  return const {
    0x2580: FractionalBlock(0, 0, 1, 0.5),
    0x2581: FractionalBlock(0, 0.875, 1, 1),
    0x2582: FractionalBlock(0, 0.75, 1, 1),
    0x2583: FractionalBlock(0, 0.625, 1, 1),
    0x2584: FractionalBlock(0, 0.5, 1, 1),
    0x2585: FractionalBlock(0, 0.375, 1, 1),
    0x2586: FractionalBlock(0, 0.25, 1, 1),
    0x2587: FractionalBlock(0, 0.125, 1, 1),
    0x2588: FractionalBlock(0, 0, 1, 1),
    0x2589: FractionalBlock(0, 0, 0.875, 1),
    0x258A: FractionalBlock(0, 0, 0.75, 1),
    0x258B: FractionalBlock(0, 0, 0.625, 1),
    0x258C: FractionalBlock(0, 0, 0.5, 1),
    0x258D: FractionalBlock(0, 0, 0.375, 1),
    0x258E: FractionalBlock(0, 0, 0.25, 1),
    0x258F: FractionalBlock(0, 0, 0.125, 1),
    0x2590: FractionalBlock(0.5, 0, 1, 1),
    0x2591: FractionalBlock(0, 0, 1, 1, alpha: 0.25),
    0x2592: FractionalBlock(0, 0, 1, 1, alpha: 0.5),
    0x2593: FractionalBlock(0, 0, 1, 1, alpha: 0.75),
    0x2594: FractionalBlock(0, 0, 1, 0.125),
    0x2595: FractionalBlock(0.875, 0, 1, 1),
    0x2596: GridFill(2, 2, 0x04),
    0x2597: GridFill(2, 2, 0x08),
    0x2598: GridFill(2, 2, 0x01),
    0x2599: GridFill(2, 2, 0x0D),
    0x259A: GridFill(2, 2, 0x09),
    0x259B: GridFill(2, 2, 0x07),
    0x259C: GridFill(2, 2, 0x0B),
    0x259D: GridFill(2, 2, 0x02),
    0x259E: GridFill(2, 2, 0x06),
    0x259F: GridFill(2, 2, 0x0E),
  };
}

Map<int, SpriteGlyph> _braille() {
  return {for (var i = 0; i < 256; i++) 0x2800 + i: BraillePattern(i)};
}

Map<int, SpriteGlyph> _geometricShapes() {
  return const {
    0x25E2: FilledPolygon([(0, 1), (1, 1), (1, 0)]),
    0x25E3: FilledPolygon([(0, 0), (0, 1), (1, 1)]),
    0x25E4: FilledPolygon([(0, 0), (0, 1), (1, 0)]),
    0x25E5: FilledPolygon([(0, 0), (1, 1), (1, 0)]),
    0x25F8: StrokedPolygon([(0, 0), (0, 1), (1, 0)]),
    0x25F9: StrokedPolygon([(0, 0), (1, 1), (1, 0)]),
    0x25FA: StrokedPolygon([(0, 0), (0, 1), (1, 1)]),
    0x25FF: StrokedPolygon([(0, 1), (1, 1), (1, 0)]),
  };
}

Map<int, SpriteGlyph> _powerline() {
  return const {
    0xE0B0: FilledPolygon([(0, 0), (1, 0.5), (0, 1)]),
    0xE0B1: StrokedPolygon([(0, 0), (1, 0.5), (0, 1)], closed: false),
    0xE0B2: FilledPolygon([(1, 0), (0, 0.5), (1, 1)]),
    0xE0B3: StrokedPolygon([(1, 0), (0, 0.5), (1, 1)], closed: false),
    0xE0B4: PowerlineSemicircle(right: true, filled: true),
    0xE0B5: PowerlineSemicircle(right: true, filled: false),
    0xE0B6: PowerlineSemicircle(right: false, filled: true),
    0xE0B7: PowerlineSemicircle(right: false, filled: false),
    0xE0B8: FilledPolygon([(0, 0), (1, 1), (0, 1)]),
    0xE0B9: DiagonalLine(topLeftToBottomRight: true),
    0xE0BA: FilledPolygon([(1, 0), (1, 1), (0, 1)]),
    0xE0BB: DiagonalLine(topLeftToBottomRight: false),
    0xE0BC: FilledPolygon([(0, 0), (1, 0), (0, 1)]),
    0xE0BD: DiagonalLine(topLeftToBottomRight: false),
    0xE0BE: FilledPolygon([(0, 0), (1, 0), (1, 1)]),
    0xE0BF: DiagonalLine(topLeftToBottomRight: true),
    0xE0D2: PowerlineFlame(right: true),
    0xE0D4: PowerlineFlame(right: false),
  };
}

const _branchNodeData = [
  0x10, 0x00, 0x12, 0x02, 0x18, 0x08, 0x1A, 0x0A,
  0x14, 0x04, 0x11, 0x01, 0x15, 0x05, 0x16, 0x06,
  0x1C, 0x0C, 0x13, 0x03, 0x19, 0x09, 0x17, 0x07,
  0x1D, 0x0D, 0x1E, 0x0E, 0x1B, 0x0B, 0x1F, 0x0F,
];

Map<int, SpriteGlyph> _branchDrawing() {
  final map = <int, SpriteGlyph>{
    0xF5D0: const BoxLines(right: 1, left: 1),
    0xF5D1: const BoxLines(up: 1, down: 1),
    0xF5D2: const FadingLine(1),
    0xF5D3: const FadingLine(3),
    0xF5D4: const FadingLine(0),
    0xF5D5: const FadingLine(2),
    0xF5D6: const BoxArc(3),
    0xF5D7: const BoxArc(2),
    0xF5D8: const BoxArc(1),
    0xF5D9: const BoxArc(0),
    0xF5DA: const Composite([BoxLines(up: 1, down: 1), BoxArc(1)]),
    0xF5DB: const Composite([BoxLines(up: 1, down: 1), BoxArc(3)]),
    0xF5DC: const Composite([BoxArc(1), BoxArc(3)]),
    0xF5DD: const Composite([BoxLines(up: 1, down: 1), BoxArc(0)]),
    0xF5DE: const Composite([BoxLines(up: 1, down: 1), BoxArc(2)]),
    0xF5DF: const Composite([BoxArc(0), BoxArc(2)]),
    0xF5E0: const Composite([BoxArc(2), BoxLines(right: 1, left: 1)]),
    0xF5E1: const Composite([BoxArc(3), BoxLines(right: 1, left: 1)]),
    0xF5E2: const Composite([BoxArc(3), BoxArc(2)]),
    0xF5E3: const Composite([BoxArc(0), BoxLines(right: 1, left: 1)]),
    0xF5E4: const Composite([BoxArc(1), BoxLines(right: 1, left: 1)]),
    0xF5E5: const Composite([BoxArc(1), BoxArc(0)]),
    0xF5E6: const Composite([BoxLines(up: 1, down: 1), BoxArc(0), BoxArc(1)]),
    0xF5E7: const Composite([BoxLines(up: 1, down: 1), BoxArc(2), BoxArc(3)]),
    0xF5E8: const Composite(
        [BoxLines(right: 1, left: 1), BoxArc(2), BoxArc(0)]),
    0xF5E9: const Composite(
        [BoxLines(right: 1, left: 1), BoxArc(1), BoxArc(3)]),
    0xF5EA: const Composite([BoxLines(up: 1, down: 1), BoxArc(0), BoxArc(3)]),
    0xF5EB: const Composite([BoxLines(up: 1, down: 1), BoxArc(1), BoxArc(2)]),
    0xF5EC: const Composite(
        [BoxLines(right: 1, left: 1), BoxArc(0), BoxArc(3)]),
    0xF5ED: const Composite(
        [BoxLines(right: 1, left: 1), BoxArc(1), BoxArc(2)]),
  };

  for (var i = 0; i < _branchNodeData.length; i++) {
    final value = _branchNodeData[i];
    map[0xF5EE + i] = BranchNode(
      up: value & 0x01 != 0,
      right: value & 0x02 != 0,
      down: value & 0x04 != 0,
      left: value & 0x08 != 0,
      filled: value & 0x10 != 0,
    );
  }

  return map;
}

const _smoothMosaicData = [
  0x01c, 0x02c, 0x01a, 0x02a, 0x019, 0x32a, 0x12a, 0x32c,
  0x12c, 0x328, 0x0ac, 0x070, 0x068, 0x0b0, 0x0a8, 0x130,
  0x2a9, 0x0a9, 0x269, 0x069, 0x229, 0x06a,
];

const _vx = [
  0.0, 0.0, 0.0, 0.0, 0.5,
  1.0, 1.0, 1.0, 1.0, 0.5,
];

const _vy = [
  0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0, 1.0,
  1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0, 0.0,
];

List<(double, double)> _decodeSmoothVertices(int mask) {
  final vertices = <(double, double)>[];
  for (var bit = 0; bit < 10; bit++) {
    if (mask & (1 << bit) != 0) {
      vertices.add((_vx[bit], _vy[bit]));
    }
  }
  return vertices;
}

Map<int, SpriteGlyph> _legacyComputing() {
  final map = <int, SpriteGlyph>{};

  for (var i = 0; i < 0x3C; i++) {
    final pattern = i + (i ~/ 0x14) + 1;
    map[0x1FB00 + i] = GridFill(2, 3, pattern);
  }

  for (var i = 0; i < 22; i++) {
    final vertices = _decodeSmoothVertices(_smoothMosaicData[i]);
    map[0x1FB3C + i] = FilledPolygon(vertices);
    map[0x1FB3C + 22 + i] = FilledPolygon(vertices, inverted: true);
  }

  map[0x1FB68] =
  const FilledPolygon([(0, 0), (1, 0), (0.5, 0.5)], inverted: true);
  map[0x1FB69] =
  const FilledPolygon([(1, 0), (1, 1), (0.5, 0.5)], inverted: true);
  map[0x1FB6A] =
  const FilledPolygon([(0, 1), (1, 1), (0.5, 0.5)], inverted: true);
  map[0x1FB6B] =
  const FilledPolygon([(0, 0), (0, 1), (0.5, 0.5)], inverted: true);
  map[0x1FB6C] = const FilledPolygon([(0, 0), (0, 1), (0.5, 0.5)]);
  map[0x1FB6D] = const FilledPolygon([(0, 0), (1, 0), (0.5, 0.5)]);
  map[0x1FB6E] = const FilledPolygon([(1, 0), (1, 1), (0.5, 0.5)]);
  map[0x1FB6F] = const FilledPolygon([(0, 1), (1, 1), (0.5, 0.5)]);

  map[0x1FB70] = const FractionalBlock(0.125, 0, 0.25, 1);
  map[0x1FB71] = const FractionalBlock(0.25, 0, 0.375, 1);
  map[0x1FB72] = const FractionalBlock(0.375, 0, 0.5, 1);
  map[0x1FB73] = const FractionalBlock(0.5, 0, 0.625, 1);
  map[0x1FB74] = const FractionalBlock(0.625, 0, 0.75, 1);
  map[0x1FB75] = const FractionalBlock(0.75, 0, 0.875, 1);

  map[0x1FB76] = const FractionalBlock(0, 0.125, 1, 0.25);
  map[0x1FB77] = const FractionalBlock(0, 0.25, 1, 0.375);
  map[0x1FB78] = const FractionalBlock(0, 0.375, 1, 0.5);
  map[0x1FB79] = const FractionalBlock(0, 0.5, 1, 0.625);
  map[0x1FB7A] = const FractionalBlock(0, 0.625, 1, 0.75);
  map[0x1FB7B] = const FractionalBlock(0, 0.75, 1, 0.875);

  map[0x1FB7C] = const Composite([
    FractionalBlock(0, 0, 0.125, 1),
    FractionalBlock(0, 0.875, 1, 1),
  ]);
  map[0x1FB7D] = const Composite([
    FractionalBlock(0, 0, 0.125, 1),
    FractionalBlock(0, 0, 1, 0.125),
  ]);
  map[0x1FB7E] = const Composite([
    FractionalBlock(0.875, 0, 1, 1),
    FractionalBlock(0, 0, 1, 0.125),
  ]);
  map[0x1FB7F] = const Composite([
    FractionalBlock(0.875, 0, 1, 1),
    FractionalBlock(0, 0.875, 1, 1),
  ]);
  map[0x1FB80] = const Composite([
    FractionalBlock(0, 0, 1, 0.125),
    FractionalBlock(0, 0.875, 1, 1),
  ]);
  map[0x1FB81] = const Composite([
    FractionalBlock(0, 0, 1, 0.125),
    FractionalBlock(0, 0.25, 1, 0.375),
    FractionalBlock(0, 0.5, 1, 0.625),
    FractionalBlock(0, 0.875, 1, 1),
  ]);
  map[0x1FB82] = const FractionalBlock(0, 0, 1, 0.25);
  map[0x1FB83] = const FractionalBlock(0, 0, 1, 0.375);
  map[0x1FB84] = const FractionalBlock(0, 0, 1, 0.625);
  map[0x1FB85] = const FractionalBlock(0, 0, 1, 0.75);
  map[0x1FB86] = const FractionalBlock(0, 0, 1, 0.875);
  map[0x1FB87] = const FractionalBlock(0.75, 0, 1, 1);
  map[0x1FB88] = const FractionalBlock(0.625, 0, 1, 1);
  map[0x1FB89] = const FractionalBlock(0.375, 0, 1, 1);
  map[0x1FB8A] = const FractionalBlock(0.25, 0, 1, 1);
  map[0x1FB8B] = const FractionalBlock(0.125, 0, 1, 1);
  map[0x1FB8C] = const FractionalBlock(0, 0, 0.5, 1, alpha: 0.5);
  map[0x1FB8D] = const FractionalBlock(0.5, 0, 1, 1, alpha: 0.5);
  map[0x1FB8E] = const FractionalBlock(0, 0, 1, 0.5, alpha: 0.5);
  map[0x1FB8F] = const FractionalBlock(0, 0.5, 1, 1, alpha: 0.5);
  map[0x1FB90] = const FractionalBlock(0, 0, 1, 1, alpha: 0.5);
  map[0x1FB91] = const Composite([
    FractionalBlock(0, 0, 1, 1, alpha: 0.5),
    FractionalBlock(0, 0, 1, 0.5),
  ]);
  map[0x1FB92] = const Composite([
    FractionalBlock(0, 0, 1, 1, alpha: 0.5),
    FractionalBlock(0, 0.5, 1, 1),
  ]);
  map[0x1FB93] = const Composite([]);
  map[0x1FB94] = const Composite([
    FractionalBlock(0, 0, 1, 1, alpha: 0.5),
    FractionalBlock(0.5, 0, 1, 1),
  ]);
  map[0x1FB95] = const Checkerboard();
  map[0x1FB96] = const Checkerboard(inverted: true);
  map[0x1FB97] = const StripeFill();
  map[0x1FB98] = const DiagonalFill(topLeftToBottomRight: true);
  map[0x1FB99] = const DiagonalFill(topLeftToBottomRight: false);
  map[0x1FB9A] = const Composite([
    FilledPolygon([(0, 0), (1, 0), (0.5, 0.5)]),
    FilledPolygon([(0, 1), (1, 1), (0.5, 0.5)]),
  ]);
  map[0x1FB9B] = const Composite([
    FilledPolygon([(0, 0), (0, 1), (0.5, 0.5)]),
    FilledPolygon([(1, 0), (1, 1), (0.5, 0.5)]),
  ]);
  map[0x1FB9C] = const FilledPolygon([(0, 0), (0, 1), (1, 0)], alpha: 0.5);
  map[0x1FB9D] = const FilledPolygon([(0, 0), (1, 0), (1, 1)], alpha: 0.5);
  map[0x1FB9E] = const FilledPolygon([(1, 0), (1, 1), (0, 1)], alpha: 0.5);
  map[0x1FB9F] = const FilledPolygon([(0, 0), (0, 1), (1, 1)], alpha: 0.5);

  map[0x1FBA0] = const CornerDiagonalLines(tl: true);
  map[0x1FBA1] = const CornerDiagonalLines(tr: true);
  map[0x1FBA2] = const CornerDiagonalLines(bl: true);
  map[0x1FBA3] = const CornerDiagonalLines(br: true);
  map[0x1FBA4] = const CornerDiagonalLines(tl: true, bl: true);
  map[0x1FBA5] = const CornerDiagonalLines(tr: true, br: true);
  map[0x1FBA6] = const CornerDiagonalLines(bl: true, br: true);
  map[0x1FBA7] = const CornerDiagonalLines(tl: true, tr: true);
  map[0x1FBA8] = const CornerDiagonalLines(tl: true, br: true);
  map[0x1FBA9] = const CornerDiagonalLines(tr: true, bl: true);
  map[0x1FBAA] = const CornerDiagonalLines(tr: true, bl: true, br: true);
  map[0x1FBAB] = const CornerDiagonalLines(tl: true, bl: true, br: true);
  map[0x1FBAC] = const CornerDiagonalLines(tl: true, tr: true, br: true);
  map[0x1FBAD] = const CornerDiagonalLines(tl: true, tr: true, bl: true);
  map[0x1FBAE] = const CornerDiagonalLines(
    tl: true,
    tr: true,
    bl: true,
    br: true,
  );

  map[0x1FBAF] = const BoxLines(up: 2, down: 2, left: 1, right: 1);
  map[0x1FBBD] = const KnockoutComposite([
    DiagonalLine(topLeftToBottomRight: false),
    DiagonalLine(topLeftToBottomRight: true),
  ]);
  map[0x1FBBE] = const KnockoutComposite([
    CornerDiagonalLines(br: true),
  ]);
  map[0x1FBBF] = const KnockoutComposite([
    CornerDiagonalLines(tl: true, tr: true, bl: true, br: true),
  ]);
  map[0x1FBCE] = const FractionalBlock(0, 0, 2.0 / 3.0, 1);
  map[0x1FBCF] = const FractionalBlock(0, 0, 1.0 / 3.0, 1);

  map[0x1FBD0] = const StrokedPolygon([(1, 0.5), (0, 1)], closed: false);
  map[0x1FBD1] = const StrokedPolygon([(1, 0), (0, 0.5)], closed: false);
  map[0x1FBD2] = const StrokedPolygon([(0, 0), (1, 0.5)], closed: false);
  map[0x1FBD3] = const StrokedPolygon([(0, 0.5), (1, 1)], closed: false);
  map[0x1FBD4] = const StrokedPolygon([(0, 0), (0.5, 1)], closed: false);
  map[0x1FBD5] = const StrokedPolygon([(0.5, 0), (1, 1)], closed: false);
  map[0x1FBD6] = const StrokedPolygon([(1, 0), (0.5, 1)], closed: false);
  map[0x1FBD7] = const StrokedPolygon([(0.5, 0), (0, 1)], closed: false);
  map[0x1FBD8] = const Composite([
    StrokedPolygon([(0, 0), (0.5, 0.5)], closed: false),
    StrokedPolygon([(0.5, 0.5), (1, 0)], closed: false),
  ]);
  map[0x1FBD9] = const Composite([
    StrokedPolygon([(1, 0), (0.5, 0.5)], closed: false),
    StrokedPolygon([(0.5, 0.5), (1, 1)], closed: false),
  ]);
  map[0x1FBDA] = const Composite([
    StrokedPolygon([(0, 1), (0.5, 0.5)], closed: false),
    StrokedPolygon([(0.5, 0.5), (1, 1)], closed: false),
  ]);
  map[0x1FBDB] = const Composite([
    StrokedPolygon([(0, 0), (0.5, 0.5)], closed: false),
    StrokedPolygon([(0.5, 0.5), (0, 1)], closed: false),
  ]);
  map[0x1FBDC] = const Composite([
    StrokedPolygon([(0, 0), (0.5, 1)], closed: false),
    StrokedPolygon([(0.5, 1), (1, 0)], closed: false),
  ]);
  map[0x1FBDD] = const Composite([
    StrokedPolygon([(1, 0), (0, 0.5)], closed: false),
    StrokedPolygon([(0, 0.5), (1, 1)], closed: false),
  ]);
  map[0x1FBDE] = const Composite([
    StrokedPolygon([(0, 1), (0.5, 0)], closed: false),
    StrokedPolygon([(0.5, 0), (1, 1)], closed: false),
  ]);
  map[0x1FBDF] = const Composite([
    StrokedPolygon([(0, 0), (1, 0.5)], closed: false),
    StrokedPolygon([(1, 0.5), (0, 1)], closed: false),
  ]);

  map[0x1FBE0] = const Circle(0.5, 0, 0.5, filled: false);
  map[0x1FBE1] = const Circle(1, 0.5, 0.5, filled: false);
  map[0x1FBE2] = const Circle(0.5, 1, 0.5, filled: false);
  map[0x1FBE3] = const Circle(0, 0.5, 0.5, filled: false);
  map[0x1FBE4] = const FractionalBlock(0.25, 0, 0.75, 0.5);
  map[0x1FBE5] = const FractionalBlock(0.25, 0.5, 0.75, 1);
  map[0x1FBE6] = const FractionalBlock(0, 0.25, 0.5, 0.75);
  map[0x1FBE7] = const FractionalBlock(0.5, 0.25, 1, 0.75);
  map[0x1FBE8] = const Circle(0.5, 0, 0.5, filled: true);
  map[0x1FBE9] = const Circle(1, 0.5, 0.5, filled: true);
  map[0x1FBEA] = const Circle(0.5, 1, 0.5, filled: true);
  map[0x1FBEB] = const Circle(0, 0.5, 0.5, filled: true);
  map[0x1FBEC] = const Circle(1, 0, 0.5, filled: true);
  map[0x1FBED] = const Circle(0, 1, 0.5, filled: true);
  map[0x1FBEE] = const Circle(1, 1, 0.5, filled: true);
  map[0x1FBEF] = const Circle(0, 0, 0.5, filled: true);

  return map;
}

const _octantData = [
  0x04, 0x06, 0x07, 0x08, 0x09, 0x0b, 0x0c, 0x0d,
  0x0e, 0x10, 0x11, 0x12, 0x13, 0x15, 0x16, 0x17,
  0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
  0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
  0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30,
  0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
  0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x41, 0x42,
  0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a,
  0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x51, 0x52, 0x53,
  0x54, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c, 0x5d,
  0x5e, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
  0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e,
  0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76,
  0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e,
  0x7f, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
  0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
  0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
  0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
  0xa1, 0xa2, 0xa3, 0xa4, 0xa6, 0xa7, 0xa8, 0xa9,
  0xab, 0xac, 0xad, 0xae, 0xb0, 0xb1, 0xb2, 0xb3,
  0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb,
  0xbc, 0xbd, 0xbe, 0xbf, 0xc1, 0xc2, 0xc3, 0xc4,
  0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc,
  0xcd, 0xce, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3, 0xd4,
  0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xdc,
  0xdd, 0xde, 0xdf, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4,
  0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec,
  0xed, 0xee, 0xef, 0xf1, 0xf2, 0xf3, 0xf4, 0xf6,
  0xf7, 0xf8, 0xf9, 0xfb, 0xfd, 0xfe,
];

int _rectPattern4x4(int left, int right, int top, int bottom) {
  var pattern = 0;
  for (var row = top; row < bottom; row++) {
    for (var col = left; col < right; col++) {
      pattern |= 1 << (row * 4 + col);
    }
  }
  return pattern;
}

Map<int, SpriteGlyph> _legacyComputingSupplement() {
  final map = <int, SpriteGlyph>{};

  map[0x1CC1B] = const BoxSpur(y: .center, side: .right, half: .top);
  map[0x1CC1C] = const BoxSpur(y: .center, side: .right, half: .bottom);
  map[0x1CC1D] = const BoxSpur(y: .top, side: .left, half: .top);
  map[0x1CC1E] = const BoxSpur(y: .bottom, side: .left, half: .bottom);

  for (var cp = 0x1CC21; cp <= 0x1CC2F; cp++) {
    final pattern = cp - 0x1CC20;
    map[cp] = GridFill(2, 2, pattern, separated: true);
  }

  map[0x1CC30] = const CirclePiece(0, 0, 2, 2, 0);
  map[0x1CC31] = const CirclePiece(1, 0, 2, 2, 0);
  map[0x1CC32] = const CirclePiece(2, 0, 2, 2, 1);
  map[0x1CC33] = const CirclePiece(3, 0, 2, 2, 1);
  map[0x1CC34] = const CirclePiece(0, 1, 2, 2, 0);
  map[0x1CC35] = const CirclePiece(0, 0, 1, 1, 0);
  map[0x1CC36] = const CirclePiece(1, 0, 1, 1, 1);
  map[0x1CC37] = const CirclePiece(3, 1, 2, 2, 1);
  map[0x1CC38] = const CirclePiece(0, 2, 2, 2, 2);
  map[0x1CC39] = const CirclePiece(0, 1, 1, 1, 2);
  map[0x1CC3A] = const CirclePiece(1, 1, 1, 1, 3);
  map[0x1CC3B] = const CirclePiece(3, 2, 2, 2, 3);
  map[0x1CC3C] = const CirclePiece(0, 3, 2, 2, 2);
  map[0x1CC3D] = const CirclePiece(1, 3, 2, 2, 2);
  map[0x1CC3E] = const CirclePiece(2, 3, 2, 2, 3);
  map[0x1CC3F] = const CirclePiece(3, 3, 2, 2, 3);

  for (var cp = 0x1CD00; cp <= 0x1CDE5; cp++) {
    map[cp] = GridFill(2, 4, _octantData[cp - 0x1CD00]);
  }

  map[0x1CE00] = const Composite([
    Circle(0, 0.5, 0.5, filled: false),
    Circle(1, 0.5, 0.5, filled: false),
  ]);
  map[0x1CE01] = const Composite([
    Circle(0.5, 0, 0.5, filled: false),
    Circle(0.5, 1, 0.5, filled: false),
  ]);
  map[0x1CE0B] = const Composite([
    CirclePiece(0, 0, 1, 0.5, 0),
    CirclePiece(0, 0, 1, 0.5, 2),
  ]);
  map[0x1CE0C] = const Composite([
    CirclePiece(1, 0, 1, 0.5, 1),
    CirclePiece(1, 0, 1, 0.5, 3),
  ]);

  for (var i = 0; i < 0x3F; i++) {
    final pattern = i + 1;
    map[0x1CE51 + i] = GridFill(2, 3, pattern, separated: true);
  }

  map[0x1CE16] = const BoxStub(top: true, right: true);
  map[0x1CE17] = const BoxStub(top: false, right: true);
  map[0x1CE18] = const BoxStub(top: true, right: false);
  map[0x1CE19] = const BoxStub(top: false, right: false);

  map[0x1CE90] = GridFill(4, 4, _rectPattern4x4(0, 1, 0, 1));
  map[0x1CE91] = GridFill(4, 4, _rectPattern4x4(1, 2, 0, 1));
  map[0x1CE92] = GridFill(4, 4, _rectPattern4x4(2, 3, 0, 1));
  map[0x1CE93] = GridFill(4, 4, _rectPattern4x4(3, 4, 0, 1));
  map[0x1CE94] = GridFill(4, 4, _rectPattern4x4(0, 1, 1, 2));
  map[0x1CE95] = GridFill(4, 4, _rectPattern4x4(1, 2, 1, 2));
  map[0x1CE96] = GridFill(4, 4, _rectPattern4x4(2, 3, 1, 2));
  map[0x1CE97] = GridFill(4, 4, _rectPattern4x4(3, 4, 1, 2));
  map[0x1CE98] = GridFill(4, 4, _rectPattern4x4(0, 1, 2, 3));
  map[0x1CE99] = GridFill(4, 4, _rectPattern4x4(1, 2, 2, 3));
  map[0x1CE9A] = GridFill(4, 4, _rectPattern4x4(2, 3, 2, 3));
  map[0x1CE9B] = GridFill(4, 4, _rectPattern4x4(3, 4, 2, 3));
  map[0x1CE9C] = GridFill(4, 4, _rectPattern4x4(0, 1, 3, 4));
  map[0x1CE9D] = GridFill(4, 4, _rectPattern4x4(1, 2, 3, 4));
  map[0x1CE9E] = GridFill(4, 4, _rectPattern4x4(2, 3, 3, 4));
  map[0x1CE9F] = GridFill(4, 4, _rectPattern4x4(3, 4, 3, 4));

  map[0x1CEA0] = GridFill(4, 4, _rectPattern4x4(2, 4, 3, 4));
  map[0x1CEA1] = GridFill(4, 4, _rectPattern4x4(1, 4, 3, 4));
  map[0x1CEA2] = GridFill(4, 4, _rectPattern4x4(0, 3, 3, 4));
  map[0x1CEA3] = GridFill(4, 4, _rectPattern4x4(0, 2, 3, 4));
  map[0x1CEA4] = GridFill(4, 4, _rectPattern4x4(0, 1, 2, 4));
  map[0x1CEA5] = GridFill(4, 4, _rectPattern4x4(0, 1, 1, 4));
  map[0x1CEA6] = GridFill(4, 4, _rectPattern4x4(0, 1, 0, 3));
  map[0x1CEA7] = GridFill(4, 4, _rectPattern4x4(0, 1, 0, 2));
  map[0x1CEA8] = GridFill(4, 4, _rectPattern4x4(0, 2, 0, 1));
  map[0x1CEA9] = GridFill(4, 4, _rectPattern4x4(0, 3, 0, 1));
  map[0x1CEAA] = GridFill(4, 4, _rectPattern4x4(1, 4, 0, 1));
  map[0x1CEAB] = GridFill(4, 4, _rectPattern4x4(2, 4, 0, 1));
  map[0x1CEAC] = GridFill(4, 4, _rectPattern4x4(3, 4, 0, 2));
  map[0x1CEAD] = GridFill(4, 4, _rectPattern4x4(3, 4, 0, 3));
  map[0x1CEAE] = GridFill(4, 4, _rectPattern4x4(3, 4, 1, 4));
  map[0x1CEAF] = GridFill(4, 4, _rectPattern4x4(3, 4, 2, 4));

  return map;
}
