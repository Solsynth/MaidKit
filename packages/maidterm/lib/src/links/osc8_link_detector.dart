import 'package:flutter/foundation.dart' show internal;

import 'link_match.dart';
import 'link_settings.dart';
import 'terminal_logical_line.dart';

/// Detects OSC 8 links from cell metadata.
///
/// Adjacent visible cells with the same non-null URI become one link.
/// A URI change splits the range, matching how terminal cells carry OSC 8
/// state independently from visible text.
@internal
final class Osc8LinkDetector {
  /// Returns OSC 8 runs from retained visible cells.
  ///
  /// Each logical line carries one URI entry per retained cell. Adjacent cells
  /// with the same URI are grouped into one link, and null URI cells split the
  /// current run.
  Iterable<LinkMatch> matches(List<TerminalLogicalLine> lines) sync* {
    for (final line in lines) {
      String? uri;
      var startIndex = -1;
      for (var i = 0; i < line.cells.length; i++) {
        final nextUri = line.uris[i];
        if (nextUri == uri) continue;

        if (uri != null && startIndex >= 0) {
          yield _matchFromCells(line, startIndex, i - 1, uri: uri);
        }
        uri = nextUri;
        startIndex = nextUri == null ? -1 : i;
      }
      if (uri != null && startIndex >= 0) {
        yield _matchFromCells(
          line,
          startIndex,
          line.cells.length - 1,
          uri: uri,
        );
      }
    }
  }

  LinkMatch _matchFromCells(
    TerminalLogicalLine line,
    int start,
    int end, {
    required String uri,
  }) {
    return LinkMatch(
      hoverOnly: false,
      priority: 1 << 30,
      sourceOrder: -2,
      link: ActivatedLink(
        type: .osc8,
        uri: Uri.tryParse(uri),
        text: line.textForCellRange(start, end),
        range: line.rangeForCellRange(start, end),
      ),
    );
  }
}
