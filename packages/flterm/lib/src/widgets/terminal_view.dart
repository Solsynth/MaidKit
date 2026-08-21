import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../foundation.dart';
import '../links/link_settings.dart';
import '../rendering.dart';
import '../rendering/terminal_render_cache.dart';
import 'link_interaction.dart';
import 'terminal_controller.dart';
import 'terminal_gesture_detector.dart';
import 'terminal_scope.dart';
import 'terminal_scroll_controller.dart';
import 'terminal_shortcut_scope.dart';
import 'terminal_view_binding.dart';

/// Displays a terminal and handles user interaction.
///
/// Pair with a [TerminalController] to create a working terminal. The
/// controller owns the terminal state; the view handles rendering,
/// scrolling, gestures, focus, and keyboard shortcuts.
///
/// Fills the available space and computes the grid dimensions (columns
/// and rows) from the font metrics and pixel area.
///
/// ```dart
/// final controller = TerminalController()
///   ..onOutput = (bytes) => pty.write(bytes);
///
/// TerminalView(
///   controller: controller,
///   theme: TerminalTheme.dark(),
///   autofocus: true,
/// );
/// ```
class TerminalView extends StatefulWidget {
  /// The controller that owns the terminal instance.
  ///
  /// Can be swapped at runtime; the view detaches from the old controller
  /// and attaches to the new one.
  final TerminalController controller;

  /// Visual style. Defaults to [TerminalTheme.dark()].
  ///
  /// Changing the font family or size recalculates cell metrics and
  /// may resize the grid.
  final TerminalTheme? theme;

  /// Focus node for this terminal. Created internally when null.
  ///
  /// Supply your own to manage focus externally (e.g. for tab switching
  /// or split pane navigation).
  final FocusNode? focusNode;

  /// Whether to request focus when first inserted into the tree.
  final bool autofocus;

  /// Whether to show the soft keyboard when focus is gained.
  ///
  /// The keyboard can still be shown programmatically via
  /// [TerminalController.showKeyboard] regardless of this setting.
  final bool showKeyboard;

  /// When to auto-hide the mouse cursor.
  final MouseAutoHide mouseAutoHide;

  /// Controls which selection gestures are enabled and how they behave.
  final TerminalGestureSettings gestureSettings;

  /// Controls terminal link detection, styling, and activation callbacks.
  final LinkSettings linkSettings;

  /// Padding around the terminal grid.
  ///
  /// Filled with the theme background color. The grid is sized from
  /// the remaining space after padding. Defaults to 8px on all sides.
  final EdgeInsets padding;

  /// Scroll physics for scrollback navigation.
  ///
  /// Disabled automatically when the terminal program requests mouse
  /// tracking, so gestures are forwarded as mouse events instead.
  final ScrollPhysics? scrollPhysics;

  /// Scroll controller for programmatic scrollback access.
  ///
  /// Created internally when null.
  final TerminalScrollController? scrollController;

  ///
  /// Defaults: Cmd+C/V/A/K on macOS, Ctrl+Shift+C/V/A/K on Linux,
  /// Ctrl+C/V/A/K on Windows.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Callback checked before terminal shortcuts and input handling.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// Raw TTF/OTF font file bytes for exact metric extraction.
  ///
  /// When provided, takes priority over automatic font resolution. The
  /// font's `post` and `OS/2` tables are parsed to get exact underline
  /// and strikethrough thickness and position values.
  ///
  /// When null (the default), the widget automatically resolves font
  /// data by searching asset bundles and system font directories via
  /// [FontDataResolver]. If auto-resolution also fails, heuristic
  /// fallbacks are used.
  final Uint8List? fontData;

  const TerminalView({
    super.key,
    required this.controller,
    this.theme,
    this.fontData,
    this.focusNode,
    this.shortcuts,
    this.onKeyEvent,
    this.scrollPhysics,
    this.scrollController,
    this.autofocus = false,
    this.showKeyboard = true,
    this.padding = const .all(8),
    this.mouseAutoHide = .onInput,
    this.linkSettings = const LinkSettings(),
    this.gestureSettings = const TerminalGestureSettings(),
  });

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  late FocusNode _focusNode;
  late TerminalTheme _theme;
  late CellMetrics _metrics;
  late TerminalViewBinding _binding;
  late TerminalScrollController _scrollController;
  final _links = LinkInteraction();
  final _rendererKey = GlobalKey();

  Uint8List? _resolvedFontData;
  var _ownsFocusNode = false;
  var _ownsScrollController = false;
  var _mouseCursorHidden = false;
  var _lastAlternatePixels = 0.0;
  var _visibleCols = 0;
  var _visibleRows = 0;
  var _devicePixelRatio = 1.0;
  Timer? _blinkTimer;
  var _blinkVisible = true;

  /// Global rectangle occupied by the active terminal cursor cell.
  Rect? get globalCursorRect {
    final renderObject = _rendererKey.currentContext?.findRenderObject();
    if (renderObject is! TerminalRenderBox) return null;
    final caret = renderObject.textInputCaretRect;
    final topLeft = renderObject.localToGlobal(caret.topLeft);
    final bottomRight = renderObject.localToGlobal(caret.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  TerminalController get _controller => widget.controller;

  Brightness get _themeBrightness {
    return _theme.background.computeLuminance() > 0.5 ? .light : .dark;
  }

  @override
  Widget build(BuildContext context) {
    final cache = terminalScopeRenderCacheOf(context);
    if (cache != null) return _build(context, cache);

    return TerminalScope(
      child: Builder(
        builder: (context) =>
            _build(context, terminalScopeRenderCacheOf(context)!),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (_devicePixelRatio == devicePixelRatio) return;

    _devicePixelRatio = devicePixelRatio;
    _metrics = _measureMetrics();
    _links.cancel();
    _syncLinkInteraction();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _binding.detach();
      _binding = _asBinding(_controller);
      _binding.brightness = _themeBrightness;
      _binding.attach(_focusNode, _scrollController);
      _controller.addListener(_onControllerChanged);
      _links.invalidateContent();
    }

    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
      _binding.attach(_focusNode, _scrollController);
    }

    if (widget.scrollController != oldWidget.scrollController) {
      _scrollController.removeListener(_onScrollChanged);
      if (_ownsScrollController) _scrollController.dispose();
      _scrollController = widget.scrollController ?? TerminalScrollController();
      _ownsScrollController = widget.scrollController == null;
      _scrollController.activeScreen = _controller.activeScreen;
      _scrollController.addListener(_onScrollChanged);
      _binding.attach(_focusNode, _scrollController);
    }

    if (widget.theme != oldWidget.theme) {
      final oldTheme = _theme;
      _theme = widget.theme ?? TerminalTheme.dark();

      // Only recalculate metrics when font properties change.
      // Color-only theme changes must not trigger metric recalculation,
      // which would clear the atlas and cause decoration flicker.
      if (_theme.fontSize != oldTheme.fontSize ||
          _theme.fontWeight != oldTheme.fontWeight ||
          _theme.fontFamily != oldTheme.fontFamily ||
          _theme.fontFamilyFallback != oldTheme.fontFamilyFallback) {
        _metrics = _measureMetrics();
        _links.cancel();
      }

      _binding.brightness = _themeBrightness;
      if (_theme.cursor.blinkInterval != oldTheme.cursor.blinkInterval) {
        _syncBlink();
      }
      if (_theme.fontFamily != oldTheme.fontFamily && widget.fontData == null) {
        _resolvedFontData = null;
        unawaited(_resolveFontData(_theme.fontFamily));
      }
    }

    _syncLinkInteraction();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _binding.detach();
    if (_ownsFocusNode) _focusNode.dispose();
    _scrollController.removeListener(_onScrollChanged);
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _binding = _asBinding(_controller);

    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;

    _theme = widget.theme ?? TerminalTheme.dark();
    _devicePixelRatio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    _metrics = _measureMetrics();

    if (widget.fontData == null) {
      unawaited(_resolveFontData(_theme.fontFamily));
    }

    _scrollController = widget.scrollController ?? TerminalScrollController();
    _ownsScrollController = widget.scrollController == null;
    _scrollController.addListener(_onScrollChanged);

    _binding.brightness = _themeBrightness;
    _binding.attach(_focusNode, _scrollController);
    _controller.addListener(_onControllerChanged);
    _syncLinkInteraction();
  }

  Widget _build(BuildContext context, TerminalRenderCache cache) {
    return GestureDetector(
      behavior: .translucent,
      onTap: _controller.requestFocus,
      child: ColoredBox(
        // Backdrop tinted by backgroundOpacity. The repaint boundary
        // TerminalRenderBox skips its own grid fill below 1.0 and
        // relies on this as the sole tint source, so default background
        // cells show through to whatever sits behind the widget without
        // composing twice across the two layers.
        color: _theme.background.withValues(alpha: _theme.backgroundOpacity),
        child: Padding(
          padding: widget.padding,
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: TerminalShortcutScope(
              onPaste: _handlePaste,
              controller: _controller,
              shortcuts: widget.shortcuts,
              enableSelectAll: widget.gestureSettings.selectAllShortcut,
              child: MouseRegion(
                onHover: _handleMouseHover,
                onExit: _handleMouseExit,
                cursor: _effectiveMouseCursor(),
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: widget.autofocus,
                  onFocusChange: _handleFocusChange,
                  child: TerminalGestureDetector(
                    links: _links,
                    metrics: _metrics,
                    binding: _binding,
                    visibleRows: _visibleRows,
                    settings: widget.gestureSettings,
                    scrollController: _scrollController,
                    onLinkActivate: widget.linkSettings.onActivate,
                    child: Scrollable(
                      controller: _scrollController,
                      physics: widget.scrollPhysics,
                      viewportBuilder: (_, offset) => TerminalRenderer(
                        key: _rendererKey,
                        theme: _theme,
                        offset: offset,
                        metrics: _metrics,
                        renderObserver: _controller,
                        terminal: _binding.terminal,
                        renderCache: cache,
                        preeditText: _binding.preeditText,
                        blinkVisible: _blinkVisible,
                        linkSnapshot: _links.snapshot(),
                        onResize: _handleResize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _effectiveMouseCursor() {
    if (_mouseCursorHidden) return SystemMouseCursors.none;
    if (_links.highlighted != null) return SystemMouseCursors.click;
    if (_controller.mouseTracking != .none) return SystemMouseCursors.basic;
    return SystemMouseCursors.text;
  }

  void _handleFocusChange(bool focused) {
    if (focused &&
        widget.showKeyboard &&
        _controller.keyboardState != .disabled) {
      _controller.showKeyboard();
      _updateTextInputGeometry();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final override = widget.onKeyEvent?.call(node, event);
    if (override != null && override != KeyEventResult.ignored) {
      return override;
    }
    _updateTextInputGeometry();
    final result = _binding.handleKeyEvent(event);

    if (result == .handled || result == .skipRemainingHandlers) {
      _updateTextInputGeometry();
      _syncBlink();
      if (widget.mouseAutoHide == .onInput && !_mouseCursorHidden) {
        setState(() => _mouseCursorHidden = true);
      }
    }

    _syncHoveredLink();
    return result;
  }

  void _handleMouseExit(PointerExitEvent event) {
    final previous = _links.highlighted;
    _links.cancelHover();
    if (previous != null) setState(() {});
  }

  void _handleMouseHover(PointerHoverEvent event) {
    final previous = _links.highlighted;
    _links.handleHover(
      localPosition: event.localPosition,
      metrics: _metrics,
      virtualMods: _binding.virtualMods,
    );
    if (_mouseCursorHidden || _links.highlighted != previous) {
      setState(() => _mouseCursorHidden = false);
    }
  }

  void _syncHoveredLink() {
    final previous = _links.highlighted;
    _links.refreshHover(metrics: _metrics, virtualMods: _binding.virtualMods);
    if (_links.highlighted == previous) return;
    setState(() {});
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    _controller.paste(data.text!);
  }

  void _handleResize(int cols, int rows) {
    _visibleCols = cols;
    _visibleRows = rows;
    _binding.handleResize(
      cols: cols,
      rows: rows,
      metrics: _metrics,
      padding: .zero,
      devicePixelRatio: _devicePixelRatio,
    );
    _syncLinkInteraction();
  }

  CellMetrics _measureMetrics({Uint8List? fontData}) {
    return measureCellMetrics(
      fontSize: _theme.fontSize,
      fontWeight: _theme.fontWeight,
      fontFamily: _theme.fontFamily,
      fontFamilyFallback: _theme.fontFamilyFallback,
      fontData: fontData ?? widget.fontData ?? _resolvedFontData,
      devicePixelRatio: _devicePixelRatio,
    );
  }

  void _onControllerChanged() {
    _links.invalidateContent();
    _syncLinkInteraction();
    _scrollController.activeScreen = _controller.activeScreen;
    if (_controller.activeScreen == .alternate &&
        _scrollController.hasClients) {
      // Base the first wheel conversion on the position we enter the
      // alternate screen at, so a scrollback position from the primary
      // screen doesn't burst arrows on the first tick.
      _lastAlternatePixels = _scrollController.position.pixels;
    }
    _updateTextInputGeometry();
    setState(_syncBlink);
  }

  void _syncLinkInteraction() {
    final cwd = _controller.pwd;
    final context = LinkContext(
      terminal: _binding.terminal,
      rows: _visibleRows,
      cols: _visibleCols,
      cwd: cwd.isEmpty ? null : cwd,
    );

    _links.update(
      context: context,
      settings: widget.linkSettings,
      idleStyle: _theme.hyperlink.idle,
    );
  }

  void _onScrollChanged() {
    _syncBlink();
    if (!_scrollController.hasClients) return;
    final cellHeight = _metrics.cellHeight;
    if (cellHeight <= 0) return;
    final pixels = _scrollController.position.pixels;
    final delta = pixels - _lastAlternatePixels;
    final lines = (delta / cellHeight).truncate();
    if (lines == 0) return;
    _lastAlternatePixels += lines * cellHeight;
    _binding.handleScroll(lines);
    _links.invalidateContent();
    _syncLinkInteraction();
    // Idle link styling (always-on rules, OSC 8/text with idle style) is
    // resolved per visible viewport. The snapshot is invalidated above, but
    // the renderer only picks up the new snapshot on a rebuild, which output
    // alone used to trigger. Scrolled-in rows stayed unstyled until the next
    // unrelated state change.
    if (_links.hasIdleStyling) setState(() {});
    _updateTextInputGeometry();
  }

  void _updateTextInputGeometry() {
    final renderObject = _rendererKey.currentContext?.findRenderObject();
    if (renderObject is! TerminalRenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }

    _binding.updateTextInputGeometry(
      editableSize: renderObject.size,
      transform: renderObject.getTransformTo(null),
      caretRect: renderObject.textInputCaretRect,
      composingRect: renderObject.textInputComposingRect,
    );
  }

  /// Asynchronously resolves font data and recomputes metrics when found.
  Future<void> _resolveFontData(String fontFamily) async {
    if (!mounted || _theme.fontFamily != fontFamily) return;
    final data = await FontDataResolver.resolve(fontFamily);
    if (data == null) return;

    _resolvedFontData = data;
    _metrics = _measureMetrics(fontData: data);
    _links.cancel();
    setState(() {});
  }

  void _syncBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (_binding.cursorBlinks) {
      _blinkTimer = Timer.periodic(_theme.cursor.blinkInterval, (_) {
        if (mounted) setState(() => _blinkVisible = !_blinkVisible);
      });
    }
    if (!_blinkVisible) setState(() => _blinkVisible = true);
  }

  static TerminalViewBinding _asBinding(TerminalController controller) {
    assert(
      controller is TerminalViewBinding,
      'TerminalController must implement TerminalViewBinding. '
      'Use the TerminalController() factory constructor.',
    );
    return controller as TerminalViewBinding;
  }
}
