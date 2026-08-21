import 'dart:ui';

import 'package:libghostty/libghostty.dart';

import '../links/link_snapshot.dart';
import 'atlas/atlas.dart';
import 'atlas/sprite_buffer.dart';
import 'paint_state.dart';
import 'terminal_frame_builder.dart';
import 'terminal_painter_stack.dart';

/// Owns the frame buffers, frame builder, and paint stack for one render box.
///
/// [TerminalRenderBox] owns widget/render-object lifecycle. This class owns
/// the terminal frame pipeline that must be rebound together when the atlas or
/// grid changes.
final class TerminalRenderPipeline {
  final TerminalPaintState _state;
  final SpriteBuffer _sprites;
  late final TerminalPainterStack _painters;
  late TerminalFrameBuilder _frameBuilder;
  var _needsTerminalSync = false;

  TerminalRenderPipeline({
    required Atlas atlas,
    required TerminalPaintState state,
    required void Function() onImageReady,
  }) : _state = state,
       _sprites = SpriteBuffer() {
    _frameBuilder = TerminalFrameBuilder(atlas, _sprites, _state);
    _painters = TerminalPainterStack(
      atlas: atlas,
      state: state,
      sprites: _sprites,
      onImageReady: onImageReady,
    );
  }

  void bindAtlas(Atlas atlas) {
    final previousBuilder = _frameBuilder;
    _frameBuilder = TerminalFrameBuilder(atlas, _sprites, _state);
    if (_state.rows > 0 && _state.cols > 0) {
      _frameBuilder.configure(_state.rows, _state.cols);
      _frameBuilder.markAllRowsDirty();
    }
    _painters.bindAtlas(atlas);
    previousBuilder.dispose();
    _needsTerminalSync = true;
  }

  void configureGrid(int rows, int cols) => _frameBuilder.configure(rows, cols);

  void dispose() {
    _painters.dispose();
    _frameBuilder.dispose();
    _sprites.dispose();
    _state.preeditActive = false;
  }

  void markAllRowsDirty() => _frameBuilder.markAllRowsDirty();

  void markRowsDirty(int from, int toExclusive) {
    _frameBuilder.markRowsDirty(from, toExclusive);
  }

  void paint(Canvas canvas) => _painters.paint(canvas);

  void refreshCursorGlyph() => _frameBuilder.refreshCursorGlyph();

  /// Syncs terminal cells and render-only preedit state into paint buffers.
  ///
  /// [preeditText] does not enter libghostty state. The frame builder overlays
  /// it on terminal-cell boundaries at the current cursor position.
  void sync(
    Terminal terminal, {
    required bool terminalDirty,
    String preeditText = '',
    LinkSnapshot linkSnapshot = .empty,
  }) {
    final syncTerminal = terminalDirty || _needsTerminalSync;
    _needsTerminalSync = false;
    _frameBuilder.sync(
      terminal,
      terminalDirty: syncTerminal,
      preeditText: preeditText,
      linkSnapshot: linkSnapshot,
    );
    _painters.sync(terminal);
  }
}
