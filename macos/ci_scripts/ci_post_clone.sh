#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory is macos/ci_scripts/. Move to the repository root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Xcode Cloud's default PATH omits Homebrew's prefix, so `brew`, `go`, and
# `pod` would otherwise be unresolvable on Apple Silicon (/opt/homebrew) and
# Intel (/usr/local) runners.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Pin the SDK instead of tracking the stable channel: newer stable releases ship
# Dart 3.14, and liquid_glass_renderer 1.0.0-dev.2 (via island_ui_foundation)
# only allows Dart >=3.13.0 <3.14.0, which makes `flutter pub get` unsolvable.
# Keep this in sync with .github/workflows/*.yml until liquid_glass_renderer
# ships a Dart 3.14-compatible release.
FLUTTER_VERSION="3.47.9"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter-$FLUTTER_VERSION}"

echo "=== Installing Flutter SDK $FLUTTER_VERSION ==="
# The versioned install path keeps a cached SDK from a different release out of
# the build.
if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$FLUTTER_ROOT"
fi
export PATH="$PATH:$FLUTTER_ROOT/bin"
flutter --version

echo "=== Installing Go ==="
# tailscale's native-assets hook compiles its embedded runtime during the Xcode
# archive and requires Go 1.26+ (or Go 1.25+ with automatic toolchain setup).
HOMEBREW_NO_AUTO_UPDATE=1 brew install go
# Fail fast on stale runner taps that would install an outdated toolchain.
go version

# Pre-cache macOS artifacts and fetch dependencies
flutter precache --macos
flutter pub get

echo "=== Installing CocoaPods ==="
# Disable Homebrew auto-updates to save CI time.
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

echo "=== Running Pod Install ==="
cd macos
pod install --repo-update

# Return to the root and generate macOS build configurations.
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter build macos --config-only

echo "=== Script finished successfully ==="
exit 0
