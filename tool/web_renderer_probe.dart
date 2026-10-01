// Compile probe for the web terminal renderer.
//
// A full `flutter build web` still stops on the parts of MaidKit that have not
// been ported (dart:io usage, desktop-only plugins), so this entry point builds
// only the renderer path. It imports the backend selector and nothing else:
// if `dart.library.js_interop` picks xterm3 correctly, and the shared adapter
// contract stays free of native-only libraries, this compiles.
//
//   flutter build web --release -t tool/web_renderer_probe.dart
//
// It is not a user-facing entry point and has no runtime behaviour to verify.
import 'package:flutter/material.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_renderer_backend.dart';

void main() {
  final adapter = const TerminalRendererFactory(
    cursorAnimationEnabled: true,
    colorScheme: TerminalColorSchemes.defaultScheme,
  ).create();
  runApp(MaterialApp(home: Scaffold(body: adapter.buildView())));
}
