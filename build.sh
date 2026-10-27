#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
APP="../OmnikeyHelper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
SDK="$(xcrun --show-sdk-path)"
for ARCH in arm64 x86_64; do
 xcrun clang -arch "$ARCH" -mmacosx-version-min=12.0 -isysroot "$SDK" -c USB.c -o "build/USB-$ARCH.o"
 xcrun clang -arch "$ARCH" -mmacosx-version-min=12.0 -isysroot "$SDK" -c Authorize.c -o "build/Authorize-$ARCH.o"
 xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos12.0" -sdk "$SDK" -import-objc-header Reader.h Core.swift main.swift "build/USB-$ARCH.o" "build/Authorize-$ARCH.o" -framework Security -framework AppKit -framework IOKit -o "build/OmnikeyHelper-$ARCH"
 xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos12.0" -sdk "$SDK" -import-objc-header Reader.h Core.swift NativeConfigure.swift "build/USB-$ARCH.o" -framework IOKit -o "build/Configure-$ARCH"
done
lipo -create build/OmnikeyHelper-arm64 build/OmnikeyHelper-x86_64 -output "$APP/Contents/MacOS/OmnikeyHelper"
cp Info.plist "$APP/Contents/Info.plist"

cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

lipo -create build/Configure-arm64 build/Configure-x86_64 -output "$APP/Contents/Helpers/OmnikeyHelper-Configure"
