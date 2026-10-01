import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// Usable area (the frame minus menu bar and dock / taskbar) of every attached
/// display, in the same logical-pixel space as the window bounds reported by
/// `window_manager`: the origin is the top-left corner of the primary display,
/// so a display arranged left of or above it has negative coordinates.
///
/// `dart:ui`'s [Display] does not expose a display's position, so the platform
/// plugin is the only source of the layout. Returns an empty list when the
/// platform cannot answer; callers then keep the saved geometry rather than
/// replacing it with a guess.
Future<List<Rect>> loadDisplayWorkAreas() async {
  // The browser has no screen_retriever implementation; the plugin call
  // throws there. There is also no native window to place on the web.
  if (kIsWeb) return const [];
  final List<Display> displays;
  try {
    displays = await ScreenRetriever.instance.getAllDisplays();
  } catch (_) {
    return const [];
  }

  final areas = <Rect>[];
  for (final display in displays) {
    final position = display.visiblePosition;
    if (position == null) continue;
    areas.add(position & (display.visibleSize ?? display.size));
  }
  return areas;
}

/// Frame a saved window has to be moved to because it no longer touches any
/// display, or `null` when the saved frame can be left where it is.
///
/// A crash or force-kill after a resize can leave the saved bounds pointing at
/// a display that is no longer attached. The window keeps the size the user
/// last chose — clamped into the display it moves to, and never below
/// [minimumSize] — because falling back to the minimum size throws the layout
/// away. It is centered on the display nearest to where it was saved.
Rect? recoveryFrameFor({
  required Rect saved,
  required List<Rect> displays,
  required Size minimumSize,
}) {
  if (displays.isEmpty) return null;
  if (displays.any(saved.overlaps)) return null;

  final display = _nearestDisplay(saved, displays);
  final width = _clampSize(saved.width, minimumSize.width, display.width);
  final height = _clampSize(saved.height, minimumSize.height, display.height);
  return Rect.fromLTWH(
    display.left + (display.width - width) / 2,
    display.top + (display.height - height) / 2,
    width,
    height,
  );
}

Rect _nearestDisplay(Rect saved, List<Rect> displays) {
  var nearest = displays.first;
  var nearestDistance = double.infinity;
  for (final display in displays) {
    final distance = (display.center - saved.center).distance;
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = display;
    }
  }
  return nearest;
}

/// Clamps [value] into `[minimum, maximum]`. A display smaller than the
/// minimum window size wins so the window still fits on screen.
double _clampSize(double value, double minimum, double maximum) =>
    maximum <= minimum ? maximum : value.clamp(minimum, maximum);
