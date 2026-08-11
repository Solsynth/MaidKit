#!/bin/sh

set -eu

: "${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"
cd "$CI_PRIMARY_REPOSITORY_PATH"

FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"

echo "=== Installing Flutter SDK ==="
if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_ROOT"
fi
export PATH="$FLUTTER_ROOT/bin:$PATH"
flutter --version

echo "=== Installing Go ==="
# tailscale's native-assets hook compiles its embedded runtime during the Xcode
# archive and requires Go 1.26+ (or Go 1.25+ with automatic toolchain setup).
if ! command -v go >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install go
fi

echo "=== Fetching Flutter dependencies ==="
flutter precache --ios
flutter pub get

PLUGIN_PACKAGE="$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ ! -f "$PLUGIN_PACKAGE" ]; then
  echo "Flutter did not generate the Swift plugin package: $PLUGIN_PACKAGE" >&2
  exit 1
fi

echo "=== Installing CocoaPods ==="
# Disable Homebrew auto-updates to save CI time.
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

# Install iOS pods without refreshing the global specs repository. All pod
# versions are pinned by Podfile.lock and the Flutter plugins are local paths.
echo "=== Running Pod Install ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

echo "=== Verifying generated Flutter package ==="
if [ ! -f "$PLUGIN_PACKAGE" ]; then
  echo "Pod installation removed the generated Swift plugin package: $PLUGIN_PACKAGE" >&2
  exit 1
fi

echo "=== Script finished successfully ==="
exit 0
