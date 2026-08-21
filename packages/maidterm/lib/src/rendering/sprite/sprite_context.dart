part of 'sprite_face.dart';

final class SpriteContext {
  final path = Path();
  final fill = Paint()..color = const Color(0xFFFFFFFF);
  final stroke = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = .stroke;

  double heavyThickness(Rect cell) => thickness(cell) * 2;

  void reset() {
    resetForGlyph(
      fillColor: const Color(0xFFFFFFFF),
      strokeColor: const Color(0xFFFFFFFF),
    );
  }

  void resetForGlyph({
    required Color fillColor,
    required Color strokeColor,
    BlendMode fillBlendMode = BlendMode.srcOver,
    BlendMode strokeBlendMode = BlendMode.srcOver,
  }) {
    path
      ..reset()
      ..fillType = .nonZero;
    fill
      ..color = fillColor
      ..blendMode = fillBlendMode
      ..style = .fill
      ..isAntiAlias = true
      ..strokeWidth = 0.0
      ..strokeCap = .butt
      ..strokeJoin = .miter;
    stroke
      ..color = strokeColor
      ..blendMode = strokeBlendMode
      ..style = .stroke
      ..isAntiAlias = true
      ..strokeWidth = 0.0
      ..strokeCap = .butt
      ..strokeJoin = .miter;
  }

  double thickness(Rect cell) {
    return math.max(1.0, (cell.width / 8).roundToDouble());
  }
}
