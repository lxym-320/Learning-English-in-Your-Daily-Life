#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Context Lens.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$ROOT/.module-cache"
swiftc "$ROOT"/*.swift -sdk "$SDK_PATH" -module-cache-path "$ROOT/.module-cache" -target "$ARCH-apple-macos14.0" -o "$APP/Contents/MacOS/Context Lens" -framework SwiftUI -framework AppKit -framework ApplicationServices -parse-as-library
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "$APP"
