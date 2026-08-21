import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart';
import 'package:meta/meta.dart';

import '../foundation.dart';
import '../links/link_snapshot.dart';
import 'atlas/atlas_config.dart';
import 'paint_state.dart';
import 'terminal_render_cache.dart';
import 'terminal_render_pipeline.dart';

/// Renders a terminal screen with cell backgrounds, styled text, cursors,
/// and selection overlays.
///
/// This is the core rendering widget used internally by [TerminalView].
/// It owns a [TerminalRenderBox] that orchestrates layout (grid sizing,
/// terminal resize), frame sync, and a paint stack.
///
/// Sizing is determined by the parent constraints and cell metrics: the
/// widget computes how many columns and rows fit, then sizes itself to
/// exactly that grid. When the grid dimensions change, the terminal is
/// resized and [onResize] fires.
///
/// ```dart
/// TerminalRenderer(
///   terminal: myTerminal,
///   theme: TerminalTheme.dark(),
///   metrics: measureCellMetrics(fontFamily: 'monospace', fontSize: 14),
///   offset: ViewportOffset.zero(),
///   renderObserver: controller,
/// )
/// ```
@internal
class TerminalRenderer extends LeafRenderObjectWidget {
  /// The terminal whose screen is rendered.
  final Terminal terminal;

  /// Visual style applied to the terminal.
  ///
  /// When changed, theme colors are pushed to the terminal (foreground,
  /// background, palette, cursor color), the glyph atlas is updated if
  /// font properties changed, and a full repaint is scheduled.
  final TerminalTheme theme;

  /// Cell pixel dimensions used for grid sizing and coordinate conversion.
  ///
  /// When changed, the glyph atlas is cleared and layout is recalculated.
  /// A grid dimension change triggers terminal resize and [onResize].
  final CellMetrics metrics;

  /// Scroll offset provided by a [Scrollable] ancestor.
  ///
  /// At `pixels == 0`, the oldest scrollback row is visible.
  /// At `pixels == maxScrollExtent`, the live screen is visible.
  final ViewportOffset offset;

  /// Observable focus state.
  ///
  /// Listened to by the render box. Changes trigger a repaint to update
  /// cursor appearance (filled vs hollow).
  final TerminalRenderObserver renderObserver;

  /// Whether the cursor blink is currently in the visible phase.
  ///
  /// When false, the cursor and blinking text (SGR 5) are hidden.
  /// Toggled by a timer in [TerminalView].
  final bool blinkVisible;

  /// IME preedit text to draw at the cursor before it is committed.
  final String preeditText;

  /// Visible link styling state prepared by the view layer.
  final LinkSnapshot linkSnapshot;

  /// Called when the terminal grid dimensions change during layout.
  ///
  /// Fires after the terminal has been resized. Use this to notify the
  /// backend (PTY, SSH) of the new dimensions.
  final OnResize? onResize;

  /// Internal render cache used to share compatible atlas state.
  final TerminalRenderCache renderCache;

  const TerminalRenderer({
    super.key,
    required this.terminal,
    required this.theme,
    required this.metrics,
    required this.offset,
    required this.renderObserver,
    required this.renderCache,
    this.blinkVisible = true,
    this.preeditText = '',
    this.linkSnapshot = .empty,
    this.onResize,
  });

  @override
  TerminalRenderBox createRenderObject(BuildContext context) {
    return TerminalRenderBox(
      theme: theme,
      offset: offset,
      metrics: metrics,
      terminal: terminal,
      renderCache: renderCache,
      onResize: onResize,
      blinkVisible: blinkVisible,
      preeditText: preeditText,
      linkSnapshot: linkSnapshot,
      renderObserver: renderObserver,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Terminal>('terminal', terminal))
      ..add(DiagnosticsProperty<TerminalTheme>('theme', theme))
      ..add(DiagnosticsProperty<CellMetrics>('metrics', metrics))
      ..add(DiagnosticsProperty<ViewportOffset>('offset', offset))
      ..add(
        FlagProperty(
          'blinkVisible',
          value: blinkVisible,
          ifTrue: 'blink visible',
        ),
      )
      ..add(StringProperty('preeditText', preeditText, defaultValue: ''));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    TerminalRenderBox renderObject,
  ) {
    renderObject
      ..terminal = terminal
      ..theme = theme
      ..renderCache = renderCache
      ..offset = offset
      ..metrics = metrics
      ..onResize = onResize
      ..renderObserver = renderObserver
      ..blinkVisible = blinkVisible
      ..preeditText = preeditText
      ..linkSnapshot = linkSnapshot;
  }
}

/// Render object orchestrating terminal layout, state sync, and painting.
///
/// Three phases per frame:
///
/// 1. **Layout**: computes grid size from constraints and [CellMetrics],
///    configures the glyph atlas for the current DPR, resizes the terminal
///    if the grid changed, and updates scroll extents.
///
/// 2. **Sync** (start of paint): snapshots terminal cells, resolves colors
///    (including OSC 10/11 overrides, bold-is-bright, inverse, faint),
///    builds frame data for text/backgrounds/decorations, resolves
///    the cursor cell glyph, and collects Kitty graphics placements.
///
/// 3. **Paint**: delegates to a paint stack that owns painter instances,
///    Kitty image snapshots, and z-order.
///
/// Created and managed by [TerminalRenderer]. Not intended for direct use.
@internal
class TerminalRenderBox extends RenderBox {
  Terminal _terminal;
  ViewportOffset _offset;
  TerminalRenderObserver _renderObserver;
  OnResize? _onResize;
  TerminalRenderCache _renderCache;
  late TerminalAtlasHandle _atlasHandle;
  late final Ticker _cursorMotionTicker;
  var _performingLayout = false;
  var _needsFrameSync = false;
  var _stickToBottom = true;
  var _lastScrollbackRows = 0;
  var _lastActiveScreen = TerminalScreen.primary;
  var _preeditText = '';
  Offset? _cursorMotionTarget;
  Offset? _cursorMotionFrom;
  DateTime? _cursorMotionStartedAt;
  LinkSnapshot _linkSnapshot;

  final TerminalPaintState _paintState;
  late final TerminalRenderPipeline _pipeline;

  TerminalRenderBox({
    required this._terminal,
    required TerminalTheme theme,
    required CellMetrics metrics,
    required this._offset,
    required this._renderObserver,
    required this._renderCache,
    bool blinkVisible = true,
    this._linkSnapshot = .empty,
    this._preeditText = '',
    this._onResize,
  }) : _paintState = TerminalPaintState(theme, metrics)
         ..blinkVisible = blinkVisible
         ..cursorFocused = _renderObserver.hasFocus {
    _atlasHandle = _renderCache.acquireAtlas(
      .fromTheme(
        theme: theme,
        metrics: metrics,
        devicePixelRatio: _currentDevicePixelRatio,
      ),
    );
    final atlas = _atlasHandle.atlas;
    _pipeline = TerminalRenderPipeline(
      atlas: atlas,
      state: _paintState,
      onImageReady: markNeedsPaint,
    );
    _cursorMotionTicker = Ticker(_onCursorMotionTick);

    _lastActiveScreen = _terminal.activeScreen;

    _applyTerminalThemeColors();
  }

  bool get blinkVisible => _paintState.blinkVisible;

  set blinkVisible(bool value) {
    if (_paintState.blinkVisible == value) return;
    _paintState.blinkVisible = value;
    _pipeline.markAllRowsDirty();
    _pipeline.refreshCursorGlyph();
    markNeedsPaint();
  }

  set preeditText(String value) {
    if (_preeditText == value) return;
    _preeditText = value;
    markNeedsPaint();
  }

  set linkSnapshot(LinkSnapshot value) {
    if (_linkSnapshot == value) return;
    final previous = _linkSnapshot;
    _linkSnapshot = value;
    if (identical(previous.matches, value.matches)) {
      _markLinkRowsDirty(previous.highlighted);
      _markLinkRowsDirty(value.highlighted);
    } else {
      _markLinkSnapshotRowsDirty(previous);
      _markLinkSnapshotRowsDirty(value);
    }
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  /// Current terminal input caret rect in this render box's local coordinates.
  Rect get textInputCaretRect {
    final metrics = _paintState.metrics;
    final rows = _paintState.rows;
    final cols = _paintState.cols;
    if (rows <= 0 || cols <= 0) {
      return Offset.zero & Size(metrics.cellWidth, metrics.cellHeight);
    }

    final cursor = _paintState.cursor;
    final row = cursor.position.row.clamp(0, rows - 1);
    final rawCol = cursor.wideTail && cursor.position.col > 0
        ? cursor.position.col - 1
        : cursor.position.col;
    final col = rawCol.clamp(0, cols - 1);
    return metrics.cellRect(Position(row: row, col: col), .zero);
  }

  /// Current terminal composing rect in this render box's local coordinates.
  Rect get textInputComposingRect => textInputCaretRect;

  void _markLinkRowsDirty(CellRange? range) {
    if (range == null) return;
    final rows = _paintState.rows;
    if (rows <= 0) return;

    var start = range.start.row;
    var end = range.end.row + 1;
    if (start < 0) start = 0;
    if (end > rows) end = rows;
    if (start >= end) return;

    _pipeline.markRowsDirty(start, end);
  }

  void _markLinkSnapshotRowsDirty(LinkSnapshot snapshot) {
    _markLinkRowsDirty(snapshot.highlighted);
    for (final match in snapshot.matches) {
      _markLinkRowsDirty(match.link.range);
    }
  }

  set metrics(CellMetrics value) {
    if (_paintState.metrics == value) return;
    _paintState.metrics = value;
    markNeedsLayout();
  }

  set offset(ViewportOffset value) {
    if (_offset == value) return;
    if (attached) _offset.removeListener(_onScroll);
    _offset = value;
    if (attached) _offset.addListener(_onScroll);
    markNeedsLayout();
  }

  set onResize(OnResize? value) => _onResize = value;

  set renderObserver(TerminalRenderObserver value) {
    if (_renderObserver == value) return;
    if (attached) _renderObserver.removeListener(_onRenderObserverChanged);
    _renderObserver = value;
    if (attached) _renderObserver.addListener(_onRenderObserverChanged);
    _onRenderObserverChanged();
  }

  set renderCache(TerminalRenderCache value) {
    if (identical(value, _renderCache)) return;

    _renderCache = value;
    final atlasChanged = _acquireAtlasForCurrentConfig(force: true);
    if (atlasChanged) _markFrameDirty();
  }

  set terminal(Terminal value) {
    if (_terminal == value) return;
    if (attached) _terminal.removeListener(_onTerminalChanged);
    _terminal = value;
    if (attached) _terminal.addListener(_onTerminalChanged);
    _applyTerminalThemeColors();
    _needsFrameSync = true;
    markNeedsLayout();
  }

  TerminalTheme get theme => _paintState.theme;

  /// Updates the theme, clearing the atlas only if font properties changed.
  ///
  /// Color-only changes (palette, foreground, background) use markNeedsPaint
  /// which repaints with the existing atlas. Font changes (size, weight,
  /// family) use markNeedsLayout which reconfigures the atlas, re-measures
  /// the grid, and pre-seeds glyphs.
  set theme(TerminalTheme value) {
    if (_paintState.theme == value) return;
    final oldTheme = _paintState.theme;
    final fontChanged =
        oldTheme.fontSize != value.fontSize ||
        oldTheme.fontWeight != value.fontWeight ||
        oldTheme.fontFamily != value.fontFamily ||
        !_listEquals(oldTheme.fontFamilyFallback, value.fontFamilyFallback);
    _paintState.updateTheme(value);
    _applyTerminalThemeColors();
    _pipeline.markAllRowsDirty();
    _needsFrameSync = true;

    if (fontChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(_onScroll);
    _renderObserver.addListener(_onRenderObserverChanged);
    _terminal.addListener(_onTerminalChanged);
    markNeedsLayout();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('cols', _paintState.cols))
      ..add(IntProperty('rows', _paintState.rows))
      ..add(DiagnosticsProperty<TerminalTheme>('theme', _paintState.theme))
      ..add(DiagnosticsProperty<CellMetrics>('metrics', _paintState.metrics))
      ..add(
        FlagProperty(
          'blinkVisible',
          value: _paintState.blinkVisible,
          ifTrue: 'cursor visible',
        ),
      )
      ..add(
        DiagnosticsProperty<TerminalRenderObserver?>(
          'renderObserver',
          _renderObserver,
        ),
      );
  }

  @override
  void detach() {
    _cursorMotionTicker.stop();
    _offset.removeListener(_onScroll);
    _renderObserver.removeListener(_onRenderObserverChanged);
    _terminal.removeListener(_onTerminalChanged);
    super.detach();
  }

  @override
  void dispose() {
    _cursorMotionTicker.dispose();
    _paintState.rows = 0;
    _paintState.cols = 0;
    _pipeline.dispose();
    _atlasHandle.release();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    _syncFrameState();

    final canvas = context.canvas;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _pipeline.paint(canvas);
    canvas.restore();
  }

  @override
  void performLayout() {
    _performingLayout = true;

    final maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final maxH = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
    final (newCols, newRows) = _paintState.metrics.gridSize(maxW, maxH);

    size = constraints.constrain(
      Size(
        newCols * _paintState.metrics.cellWidth,
        newRows * _paintState.metrics.cellHeight,
      ),
    );

    final dpr = _currentDevicePixelRatio;
    final atlasReconfigured = _acquireAtlasForCurrentConfig(dpr: dpr);

    final gridChanged =
        newCols != _paintState.cols || newRows != _paintState.rows;
    if (gridChanged) {
      _paintState.cols = newCols;
      _paintState.rows = newRows;
      _paintState.devicePixelRatio = dpr;
      if (newCols > 0 && newRows > 0) {
        _pipeline.configureGrid(newRows, newCols);
        // Cell size is reported in physical pixels so size-report
        // escapes and Kitty graphics geometry match a native terminal
        // at the same DPI.
        _terminal.resize(
          cols: newCols,
          rows: newRows,
          cellWidthPx: (_paintState.metrics.cellWidth * dpr).round(),
          cellHeightPx: (_paintState.metrics.cellHeight * dpr).round(),
        );
        _onResize?.call(
          newCols,
          newRows,
          (newCols * _paintState.metrics.cellWidth * dpr).round(),
          (newRows * _paintState.metrics.cellHeight * dpr).round(),
        );
      }
    } else if (_paintState.devicePixelRatio != dpr) {
      _paintState.devicePixelRatio = dpr;
    }

    _syncScrollLayout();

    // Grid changes invalidate every row's sprite slot layout. Atlas
    // rebinding invalidates atlas references inside the pipeline.
    if (gridChanged) _pipeline.markAllRowsDirty();

    if (gridChanged || atlasReconfigured) _markFrameDirty();

    _performingLayout = false;
  }

  void _applyTerminalThemeColors() {
    _terminal.foreground = _paintState.theme.foreground.toRgbColor();
    _terminal.background = _paintState.theme.background.toRgbColor();
    // Sentinel cursor colors (cellForeground/cellBackground) can't be
    // reported as a single RGB, so we only push a fixed color down to
    // libghostty; the flterm cursor painter resolves sentinels locally.
    _terminal.cursorColor = _paintState.theme.cursor.color?.fixedColor
        ?.toRgbColor();
    _terminal.palette = [
      for (var i = 0; i < 256; i++) _paintState.theme.palette[i].toRgbColor(),
    ];
  }

  bool _acquireAtlasForCurrentConfig({double? dpr, bool force = false}) {
    final config = AtlasConfig.fromTheme(
      theme: _paintState.theme,
      metrics: _paintState.metrics,
      devicePixelRatio: dpr ?? _currentDevicePixelRatio,
    );
    if (!force && config == _atlasHandle.config) return false;

    final previousHandle = _atlasHandle;
    _atlasHandle = _renderCache.acquireAtlas(config);
    _pipeline.bindAtlas(_atlasHandle.atlas);
    previousHandle.release();
    return true;
  }

  double get _currentDevicePixelRatio {
    return WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .devicePixelRatio;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _markFrameDirty() {
    _needsFrameSync = true;
    markNeedsPaint();
  }

  void _onRenderObserverChanged() {
    _paintState.cursorFocused = _renderObserver.hasFocus;
    _pipeline.refreshCursorGlyph();
    markNeedsPaint();
  }

  void _onScroll() {
    if (_performingLayout) return;
    if (_paintState.rows == 0 || _paintState.metrics.cellHeight <= 0) return;

    final scrollbar = _terminal.scrollbar;
    final scrollbackLen = scrollbar.total - scrollbar.visible;
    if (scrollbackLen <= 0) return;

    final cellHeight = _paintState.metrics.cellHeight;
    final maxExtent = scrollbackLen * cellHeight;
    final pixels = _offset.pixels.clamp(0.0, maxExtent);

    _stickToBottom = maxExtent <= 0 || pixels >= maxExtent - cellHeight;

    final targetOffset = (pixels / cellHeight).floor();
    final delta = targetOffset - scrollbar.offset;

    if (delta == 0) return;

    _terminal.scrollViewport(delta);
    _markFrameDirty();
  }

  // Handles terminal change notifications.
  //
  // When scrollback length changes, a layout pass is needed because scroll
  // extents must be recalculated. For normal output (same scrollback
  // length), only a repaint is needed.
  void _onTerminalChanged() {
    if (_paintState.rows == 0 || _performingLayout) return;

    // The alternate screen has no scrollback, so scrollbackRows alone won't
    // change on screen switches. Layout must still rerun to apply the
    // alternate-screen content dimensions to the scroll position (which the
    // position turns into infinite extents so wheel gestures can be converted
    // to cursor/mouse input instead of being clamped dead at 0..0).
    final screenChanged = _terminal.activeScreen != _lastActiveScreen;
    if (screenChanged) {
      _lastActiveScreen = _terminal.activeScreen;
    }

    if (screenChanged || _terminal.scrollbackRows != _lastScrollbackRows) {
      _needsFrameSync = true;
      markNeedsLayout();
      return;
    }

    _markFrameDirty();
  }

  // Maintains scroll position and content dimensions.
  //
  // "Stick to bottom" keeps the viewport pinned to the latest output,
  // which is the normal mode when the user hasn't scrolled up. Once the
  // user scrolls away from the bottom, new output no longer forces the
  // viewport down. Stick-to-bottom re-engages when the user scrolls
  // back to within one cell of the bottom edge.
  void _syncScrollLayout() {
    _offset.applyViewportDimension(size.height);

    if (_terminal.activeScreen == .alternate) {
      _offset.applyContentDimensions(0, 0);
      _lastScrollbackRows = 0;
      _stickToBottom = true;
      return;
    }

    final scrollbar = _terminal.scrollbar;
    final scrollbackLen = scrollbar.total - scrollbar.visible;
    final cellHeight = _paintState.metrics.cellHeight;
    final maxExtent = scrollbackLen * cellHeight;

    // Detect if the terminal was scrolled to bottom externally.
    if (!_stickToBottom &&
        scrollbackLen > 0 &&
        scrollbar.offset >= scrollbackLen) {
      _stickToBottom = true;
    }

    if (_stickToBottom && maxExtent > 0) {
      final correction = maxExtent - _offset.pixels;
      if (correction.abs() > 0.01) _offset.correctBy(correction);
      if (scrollbar.offset < scrollbackLen) _terminal.scrollToBottom();
    }
    _offset.applyContentDimensions(0, maxExtent);
    _lastScrollbackRows = scrollbackLen;
    _stickToBottom = maxExtent <= 0 || _offset.pixels >= maxExtent - cellHeight;
  }

  // Syncs terminal state into paint-ready frame buffers.
  void _syncFrameState() {
    if (_paintState.rows == 0) return;

    final terminalDirty = _needsFrameSync;
    _needsFrameSync = false;
    _pipeline.sync(
      _terminal,
      terminalDirty: terminalDirty,
      preeditText: _preeditText,
      linkSnapshot: _linkSnapshot,
    );
    _syncCursorMotion();
  }

  void _syncCursorMotion() {
    final cursor = _paintState.cursor;
    final target = Offset(
      cursor.position.col.toDouble(),
      cursor.position.row.toDouble(),
    );
    final duration = _paintState.theme.cursorMotionDuration;
    final previousTarget = _cursorMotionTarget;
    if (duration == Duration.zero || previousTarget == null) {
      _cursorMotionTicker.stop();
      _cursorMotionTarget = target;
      _paintState.cursorVisualPosition = target;
      return;
    }
    if (target == previousTarget) return;

    // Cursor jumps caused by screen switches, paging, or remote programs are
    // intentionally immediate; easing them would make the caret look lost.
    final distance = (target - _paintState.cursorVisualPosition).distance;
    if (distance > 8) {
      _cursorMotionTicker.stop();
      _cursorMotionTarget = target;
      _paintState.cursorVisualPosition = target;
      return;
    }

    _cursorMotionFrom = _paintState.cursorVisualPosition;
    _cursorMotionTarget = target;
    _cursorMotionStartedAt = DateTime.now();
    if (!_cursorMotionTicker.isActive) _cursorMotionTicker.start();
  }

  void _onCursorMotionTick(Duration _) {
    final from = _cursorMotionFrom;
    final target = _cursorMotionTarget;
    final startedAt = _cursorMotionStartedAt;
    if (from == null || target == null || startedAt == null) {
      _cursorMotionTicker.stop();
      return;
    }
    final duration = _paintState.theme.cursorMotionDuration;
    final progress =
        (DateTime.now().difference(startedAt).inMicroseconds /
                duration.inMicroseconds)
            .clamp(0.0, 1.0);
    _paintState.cursorVisualPosition = Offset.lerp(
      from,
      target,
      Curves.easeOutCubic.transform(progress),
    )!;
    if (progress >= 1.0) _cursorMotionTicker.stop();
    markNeedsPaint();
  }
}

extension on Color {
  RgbColor toRgbColor() => RgbColor(
    (r * 255.0).round().clamp(0, 255),
    (g * 255.0).round().clamp(0, 255),
    (b * 255.0).round().clamp(0, 255),
  );
}
