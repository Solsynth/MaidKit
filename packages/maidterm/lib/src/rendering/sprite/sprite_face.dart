library;

import 'dart:math' as math;
import 'dart:ui';

part 'parts/box_arc.dart';
part 'parts/box_lines.dart';
part 'parts/box_spur.dart';
part 'parts/box_stub.dart';
part 'parts/braille_pattern.dart';
part 'parts/branch_node.dart';
part 'parts/checkerboard.dart';
part 'parts/circle.dart';
part 'parts/circle_piece.dart';
part 'parts/composite.dart';
part 'parts/corner_diagonal_lines.dart';
part 'parts/dash_line.dart';
part 'parts/diagonal_fill.dart';
part 'parts/diagonal_line.dart';
part 'parts/fading_line.dart';
part 'parts/filled_polygon.dart';
part 'parts/fractional_block.dart';
part 'parts/grid_fill.dart';
part 'parts/knockout_composite.dart';
part 'parts/powerline_flame.dart';
part 'parts/powerline_semicircle.dart';
part 'parts/stripe_fill.dart';
part 'parts/stroked_polygon.dart';
part 'drawing.dart';
part 'registry.dart';
part 'sprite_context.dart';
part 'sprite_glyph.dart';

final class SpriteFace {
  final Map<int, SpriteGlyph> _registry;

  SpriteFace({Map<int, SpriteGlyph>? registry})
    : _registry = registry ?? buildBuiltinSpriteRegistry();

  Iterable<int> get supportedCodepoints => _registry.keys;

  SpriteGlyph? glyphFor(int codepoint) => _registry[codepoint];

  bool hasCodepoint(int codepoint) => _registry.containsKey(codepoint);
}
