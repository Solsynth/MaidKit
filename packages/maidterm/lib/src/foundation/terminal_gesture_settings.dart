import 'package:flutter/foundation.dart';
import 'package:libghostty/libghostty.dart' show SelectionGestureBehaviors;

/// A modifier key used to trigger gesture behaviors.
///
/// Used by [TerminalGestureSettings.blockSelectionModifier] to choose
/// which held key switches from normal to block selection during drag.
enum GestureModifier { alt, control, meta, shift }

/// How triple-click line selection determines the end column.
///
/// Configures the trailing edge behavior when the gesture detector
/// resolves a line selection via [TerminalGestureSettings.lineSelectMode].
enum LineSelectMode {
  /// Selection ends at the last non-empty cell, trimming trailing blanks.
  content,

  /// Selection extends to the full row width regardless of content.
  full,
}

/// Controls which terminal selection affordances are enabled and how press
/// gestures behave.
///
/// Passed to [TerminalView.gestureSettings]. Only affects selection
/// behavior: mouse tracking (for terminal programs) and focus gestures
/// work regardless of these settings.
///
/// ```dart
/// TerminalView(
///   controller: controller,
///   gestureSettings: TerminalGestureSettings(
///     selectionBehaviors: SelectionGestureBehaviors(
///       singleClick: .cell,
///       doubleClick: .line,
///       tripleClick: .word,
///     ),
///     blockSelectionModifier: .meta,
///     wordBoundaries: '/.',
///     dragSelection: false,
///   ),
/// )
/// ```
@immutable
final class TerminalGestureSettings {
  /// Whether mouse drag can extend terminal selection.
  ///
  /// Defaults to true. When false, drag gestures still request focus and mouse
  /// tracking still works, but they do not apply text selection.
  final bool dragSelection;

  /// Whether touch long press can start terminal selection.
  ///
  /// Defaults to true. When false, long press gestures still request focus, but
  /// they do not apply text selection.
  final bool longPressSelection;

  /// Whether the select-all keyboard shortcut can select terminal contents.
  ///
  /// Defaults to true. This only controls the shortcut; calling
  /// [TerminalController.selectAll] still selects programmatically.
  final bool selectAllShortcut;

  /// How triple-click line selection determines the end column.
  ///
  /// [LineSelectMode.content] (default) trims trailing empty cells.
  /// [LineSelectMode.full] always selects the full row width, which
  /// is useful when pasting output where trailing whitespace matters.
  final LineSelectMode lineSelectMode;

  /// Modifier key that switches drag selection to block (rectangular) mode.
  ///
  /// Defaults to [GestureModifier.alt], matching most desktop terminals.
  /// Set to null to disable modifier-based block selection.
  ///
  /// Avoid [GestureModifier.shift]: Shift is used to bypass terminal
  /// mouse tracking, and the two behaviors would conflict.
  final GestureModifier? blockSelectionModifier;

  /// Selection shape used for long-press gestures on touch devices.
  ///
  /// Defaults to [TerminalSelectionShape.normal] for linear text selection.
  /// Set to [TerminalSelectionShape.rectangle] to start a rectangular
  /// selection on long press.
  final TerminalSelectionShape longPressSelectionShape;

  /// Selection behavior table for press gestures.
  ///
  /// Defaults to standard terminal behavior: single-click cell selection,
  /// double-click word selection, and triple-click line selection.
  final SelectionGestureBehaviors selectionBehaviors;

  /// Characters that split words during word selection.
  ///
  /// Used when resolving double-click word selection and word-granular drags.
  /// Each Unicode scalar value in the string is treated as one word-boundary
  /// codepoint. When null, the terminal's default word boundaries are used.
  /// Passing an empty string explicitly makes every non-empty run selectable
  /// as one word.
  final String? wordBoundaries;

  const TerminalGestureSettings({
    this.dragSelection = true,
    this.selectAllShortcut = true,
    this.longPressSelection = true,
    this.lineSelectMode = .content,
    this.blockSelectionModifier = .alt,
    this.selectionBehaviors = .standard,
    this.longPressSelectionShape = .normal,
    this.wordBoundaries,
  });

  @override
  int get hashCode => Object.hash(
    selectionBehaviors.singleClick,
    selectionBehaviors.doubleClick,
    selectionBehaviors.tripleClick,
    blockSelectionModifier,
    longPressSelectionShape,
    lineSelectMode,
    dragSelection,
    longPressSelection,
    selectAllShortcut,
    wordBoundaries,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalGestureSettings &&
          selectionBehaviors.singleClick ==
              other.selectionBehaviors.singleClick &&
          selectionBehaviors.doubleClick ==
              other.selectionBehaviors.doubleClick &&
          selectionBehaviors.tripleClick ==
              other.selectionBehaviors.tripleClick &&
          blockSelectionModifier == other.blockSelectionModifier &&
          longPressSelectionShape == other.longPressSelectionShape &&
          lineSelectMode == other.lineSelectMode &&
          dragSelection == other.dragSelection &&
          longPressSelection == other.longPressSelection &&
          selectAllShortcut == other.selectAllShortcut &&
          wordBoundaries == other.wordBoundaries;
}

/// Selection shape used for gestures that start without a keyboard modifier.
enum TerminalSelectionShape {
  /// Selects contiguous terminal text.
  normal,

  /// Selects a rectangular cell block.
  rectangle,
}
