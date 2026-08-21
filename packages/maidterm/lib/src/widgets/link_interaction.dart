import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show Offset;
import 'package:libghostty/libghostty.dart' show Mods, Position, Terminal;

import '../foundation.dart';
import '../links/activation_policy.dart';
import '../links/link_resolver.dart';
import '../links/link_settings.dart';
import '../links/link_snapshot.dart';

/// Immutable inputs needed to resolve links for one terminal viewport.
@internal
@immutable
final class LinkContext {
  final Terminal terminal;
  final int rows;
  final int cols;
  final String? cwd;

  const LinkContext({
    required this.terminal,
    required this.rows,
    required this.cols,
    required this.cwd,
  });

  @override
  int get hashCode => Object.hash(identityHashCode(terminal), rows, cols, cwd);

  bool get hasViewport => rows > 0 && cols > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkContext &&
          identical(terminal, other.terminal) &&
          rows == other.rows &&
          cols == other.cols &&
          cwd == other.cwd;
}

/// Coordinates link hover, press, callbacks, and render snapshots.
@internal
final class LinkInteraction {
  final LinkResolver _resolver;

  LinkContext? _context;
  var _settings = const LinkSettings();
  var _idleStyle = const HyperlinkStyle();
  LinkSnapshot? _idleSnapshot;
  LinkSnapshot? _snapshot;

  Offset? _lastHoverPosition;
  Position? _lastHoverCell;
  CellRange? _highlighted;
  _LinkPressCandidate? _pressCandidate;

  LinkInteraction({LinkResolver? resolver})
    : _resolver = resolver ?? LinkResolver();

  CellRange? get highlighted => _highlighted;

  /// Whether idle (always-visible) link styling is active.
  ///
  /// Snapshot invalidation only needs to reach the renderer when this is
  /// true; hover-only link setups repaint from hover state alone.
  bool get hasIdleStyling => _needsIdleSnapshot();

  /// Clears hover and press state without invalidating detected links.
  void cancel() => _clearInteraction();

  void cancelHover() {
    _lastHoverPosition = null;
    _clearHoverHit();
  }

  CellRange? handleHover({
    required Offset localPosition,
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    _lastHoverPosition = localPosition;
    return _hoverAt(localPosition, metrics: metrics, virtualMods: virtualMods);
  }

  bool handlePress({
    required Offset localPosition,
    required CellMetrics metrics,
    required PointerDeviceKind pointerKind,
    required Mods virtualMods,
  }) {
    _pressCandidate = null;
    if (!_canActivate(pointerKind, virtualMods)) return false;

    final cell = metrics.cellAt(localPosition);
    final link = _linkAt(cell);
    if (link == null) return false;

    _pressCandidate = _LinkPressCandidate(cell, link);
    return true;
  }

  ActivatedLink? handleRelease({
    required Offset localPosition,
    required CellMetrics metrics,
  }) {
    final candidate = _pressCandidate;
    _pressCandidate = null;
    if (candidate == null) return null;

    final cell = metrics.cellAt(localPosition);
    return cell == candidate.cell ? candidate.link : null;
  }

  void invalidateContent() {
    _idleSnapshot = null;
    _snapshot = null;
    cancelHover();
  }

  CellRange? refreshHover({
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    final position = _lastHoverPosition;
    if (position == null) return _highlighted;
    return _hoverAt(position, metrics: metrics, virtualMods: virtualMods);
  }

  /// Returns the current renderer snapshot, rebuilding it when needed.
  LinkSnapshot snapshot() {
    final cached = _snapshot;
    if (cached != null) return cached;

    final context = _context;
    final snapshot = context == null || !context.hasViewport
        ? LinkSnapshot.empty
        : _buildSnapshot(context);
    _snapshot = snapshot;
    return snapshot;
  }

  void update({
    required LinkContext context,
    required LinkSettings settings,
    required HyperlinkStyle idleStyle,
  }) {
    final previousSettings = _settings;
    final contextChanged = _context != context;
    final matchSettingsChanged = !_sameMatchSettings(
      previousSettings,
      settings,
    );
    final gestureSettingsChanged = !_sameGestureSettings(
      previousSettings,
      settings,
    );
    final idleStyleChanged = _idleStyle != idleStyle;

    _context = context;
    _settings = settings;
    _idleStyle = idleStyle;

    if (contextChanged || matchSettingsChanged) {
      _idleSnapshot = null;
      _snapshot = null;
      _clearInteraction();
      return;
    }

    if (idleStyleChanged) {
      _idleSnapshot = null;
      _snapshot = null;
    }
    if (gestureSettingsChanged) _clearInteraction();
  }

  LinkSnapshot _buildSnapshot(LinkContext context) {
    if (_settings.types.isEmpty) return .empty;
    if (_needsIdleSnapshot()) {
      return _idleSnapshotFor(context).withHighlighted(_highlighted);
    }
    final range = _highlighted;
    return range == null ? .empty : .highlighted(range);
  }

  bool _canActivate(PointerDeviceKind pointerKind, Mods virtualMods) {
    return canActivateLink(
      settings: _settings,
      virtualMods: virtualMods,
      pointerKind: pointerKind,
    );
  }

  void _cancelPress() => _pressCandidate = null;

  void _clearHoverHit() {
    _lastHoverCell = null;
    if (_highlighted == null) return;
    _highlighted = null;
    _snapshot = null;
  }

  void _clearInteraction() {
    _cancelPress();
    cancelHover();
  }

  bool _hasIdleVisualEffect() {
    return _idleStyle.underline != .none ||
        _idleStyle.underlineColor != null ||
        _idleStyle.textColor != null;
  }

  ActivatedLink? _linkAt(Position cell) {
    final context = _context;
    if (context == null || !context.hasViewport) return null;
    if (cell.row < 0 ||
        cell.row >= context.rows ||
        cell.col < 0 ||
        cell.col >= context.cols) {
      return null;
    }
    return _resolver.linkAt(
      context.terminal,
      cell,
      _settings,
      rows: context.rows,
      cols: context.cols,
      cwd: context.cwd,
    );
  }

  CellRange? _hoverAt(
    Offset localPosition, {
    required CellMetrics metrics,
    required Mods virtualMods,
  }) {
    if (!_canActivate(.mouse, virtualMods)) {
      _clearHoverHit();
      return null;
    }

    final cell = metrics.cellAt(localPosition);
    if (cell == _lastHoverCell) return _highlighted;

    final link = _linkAt(cell);
    _lastHoverCell = cell;
    final nextRange = link?.range;
    if (nextRange == _highlighted) return _highlighted;

    _highlighted = nextRange;
    _snapshot = null;
    return _highlighted;
  }

  LinkSnapshot _idleSnapshotFor(LinkContext context) {
    final cached = _idleSnapshot;
    if (cached != null) return cached;

    final snapshot = _resolver.buildSnapshot(
      context.terminal,
      _settings,
      rows: context.rows,
      cols: context.cols,
    );
    _idleSnapshot = snapshot;
    return snapshot;
  }

  bool _needsIdleSnapshot() {
    if (!_hasIdleVisualEffect()) return false;
    final Set<LinkType> types = _settings.types;
    if (types.contains(LinkType.osc8) || types.contains(LinkType.text)) {
      return true;
    }
    if (!types.contains(LinkType.custom)) return false;
    return _settings.rules.any((rule) => rule.highlightMode == .always);
  }

  bool _sameGestureSettings(LinkSettings a, LinkSettings b) {
    return a.modifier == b.modifier &&
        (a.onActivate != null) == (b.onActivate != null);
  }

  bool _sameMatchSettings(LinkSettings a, LinkSettings b) {
    return setEquals(a.types, b.types) && listEquals(a.rules, b.rules);
  }
}

final class _LinkPressCandidate {
  final Position cell;
  final ActivatedLink link;

  const _LinkPressCandidate(this.cell, this.link);
}
