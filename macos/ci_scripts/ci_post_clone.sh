#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory is macos/ci_scripts/. Move to the repository root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "=== Installing Flutter SDK ==="
# Clone the stable Flutter SDK from Git into the home folder.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

echo "=== Installing Go ==="
# tailscale's native-assets hook compiles its embedded runtime during the Xcode
# archive and requires Go 1.26+ (or Go 1.25+ with automatic toolchain setup).
HOMEBREW_NO_AUTO_UPDATE=1 brew install go

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
