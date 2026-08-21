import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:libghostty/libghostty.dart';

var _installed = false;

/// Installs flterm's default PNG decoder for Kitty graphics on first
/// call. Idempotent so every [TerminalController] can call it on
/// construction regardless of how many others already exist.
void installDefaultKittyPngDecoder() {
  if (_installed) return;
  _installed = true;
  LibGhostty.setPngDecoder(_decodePng);
}

DecodedImage? _decodePng(Uint8List bytes) {
  final decoded = img.decodePng(bytes);
  if (decoded == null) return null;
  final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
  return (
    width: rgba.width,
    height: rgba.height,
    rgba: Uint8List.fromList(rgba.toUint8List()),
  );
}
