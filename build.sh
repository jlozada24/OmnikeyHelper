#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
APP="../OmnikeyHelper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
for ARCH in arm64 x86_64; do
 xcrun clang -arch "$ARCH" -mmacosx-version-min=12.0 -isysroot "$SDK" -c Reader.c -o "build/Reader-$ARCH.o"
 xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos12.0" -sdk "$SDK" -import-objc-header Reader.h Core.swift main.swift "build/Reader-$ARCH.o" -framework AppKit -framework IOKit -framework PCSC -o "build/OmnikeyHelper-$ARCH"
done
lipo -create build/OmnikeyHelper-arm64 build/OmnikeyHelper-x86_64 -output "$APP/Contents/MacOS/OmnikeyHelper"
cp Info.plist "$APP/Contents/Info.plist"

cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
