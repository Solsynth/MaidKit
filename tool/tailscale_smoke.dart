import 'dart:io';

import 'package:tailscale/tailscale.dart';

/// One-off smoke check for the embedded Tailscale runtime on this machine.
/// Verifies the native library loads, the worker starts, and the documented
/// auth-less first-run failure surfaces. Does not join a real tailnet.
Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('tailscale-smoke');
  try {
    Tailscale.init(
      stateDir: dir.path,
      logLevel: TailscaleLogLevel.info,
      appId: 'dev.solsynth.maid',
    );
    stdout.writeln('init ok');

    final status = await Tailscale.instance
        .status()
        .timeout(const Duration(seconds: 25));
    stdout.writeln('status: state=${status.state.name} ips=${status.tailscaleIPs}');

    try {
      await Tailscale.instance.up().timeout(const Duration(seconds: 25));
      stdout.writeln('up: unexpectedly succeeded');
    } on TailscaleUpException catch (error) {
      stdout.writeln('up without auth key: ${error.runtimeType} (expected)');
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
  // The embedded worker isolate keeps the process alive; terminate explicitly.
  exit(0);
}
