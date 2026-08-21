import 'package:flutter/foundation.dart' show internal;
import 'package:libghostty/libghostty.dart' show Position, Terminal;

import '../foundation/cell_range.dart';
import 'link_match.dart';
import 'link_settings.dart';
import 'link_snapshot.dart';
import 'osc8_link_detector.dart';
import 'terminal_logical_line.dart';
import 'text_link_detector.dart';

/// Resolves links from the visible terminal viewport.
///
/// Hit testing scans only the logical line under the pointer. Snapshot building
/// scans every visible logical line so the renderer can style idle links.
@internal
final class LinkResolver {
  final _osc8Detector = Osc8LinkDetector();
  final _textDetector = TextLinkDetector();

  /// Builds the visible link set used for idle and highlighted styling.
  LinkSnapshot buildSnapshot(
    Terminal terminal,
    LinkSettings settings, {
    required int rows,
    required int cols,
    CellRange? highlighted,
  }) {
    if (settings.types.isEmpty) return .empty;

    final lines = TerminalLogicalLine.visible(terminal, rows: rows, cols: cols);
    return LinkSnapshot(
      _matches(lines, settings, cwd: null),
      highlighted: highlighted,
    );
  }

  /// Returns the top link at [position], if one exists.
  ActivatedLink? linkAt(
    Terminal terminal,
    Position position,
    LinkSettings settings, {
    required int rows,
    required int cols,
    required String? cwd,
  }) {
    if (settings.types.isEmpty) return null;

    final line = TerminalLogicalLine.atPosition(
      terminal,
      position,
      rows: rows,
      cols: cols,
    );
    if (line == null) return null;

    final matches = _matches([line], settings, cwd: cwd);
    for (final match in matches) {
      if (match.contains(position)) return match.link;
    }
    return null;
  }

  List<LinkMatch> _matches(
    List<TerminalLogicalLine> lines,
    LinkSettings settings, {
    required String? cwd,
  }) {
    final matches = <LinkMatch>[];
    final types = settings.types;
    final osc8Enabled = types.contains(LinkType.osc8);
    final textEnabled = types.contains(LinkType.text);
    final customEnabled = types.contains(LinkType.custom);

    if (osc8Enabled) matches.addAll(_osc8Detector.matches(lines));

    if (textEnabled) {
      matches.addAll(_textDetector.builtInMatches(lines, cwd: cwd));
    }
    if (customEnabled) {
      for (var i = 0; i < settings.rules.length; i++) {
        matches.addAll(
          _textDetector.customMatches(lines, settings.rules[i], i),
        );
      }
    }
    return LinkMatch.resolveOverlaps(matches);
  }
}
