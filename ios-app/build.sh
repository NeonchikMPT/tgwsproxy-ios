#!/bin/bash
# build_ipa.sh — Builds TgWsProxy IPA from Swift sources WITHOUT Xcode
# Requirements: macOS with Swift toolchain, or a CI runner with same.
# Usage: bash build_ipa.sh
#
# This script:
# 1. Compiles all Swift sources with swiftc targeting arm64-apple-ios16.1
# 2. Assembles .app bundle with proper structure
# 3. Creates .ipa (zip of Payload/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/Payload/TgWsProxy.app"
IPA_PATH="$SCRIPT_DIR/TgWsProxy.ipa"

BUNDLE_ID="com.tgwsproxy.app"
MIN_IOS="16.1"
TARGET="arm64-apple-ios${MIN_IOS}"

SOURCES_DIR="$SCRIPT_DIR/TgWsProxy/Sources"
RESOURCES_DIR="$SCRIPT_DIR/TgWsProxy/Resources"

echo "=== TgWsProxy IPA Builder ==="
echo "Target: $TARGET"
echo ""

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR"

# Find iOS SDK
if xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    echo "Using SDK: $SDK"
else
    echo "ERROR: iPhone SDK not found. Install Xcode command line tools."
    echo "Alternatively, set SDK=/path/to/iPhoneOS.sdk"
    exit 1
fi

# Collect Swift sources (main app only, not LiveActivity for now)
SWIFT_FILES=(
    "$SOURCES_DIR/TgWsProxyApp.swift"
    "$SOURCES_DIR/ContentView.swift"
    "$SOURCES_DIR/SettingsView.swift"
    "$SOURCES_DIR/ProxyConfig.swift"
    "$SOURCES_DIR/ProxyManager.swift"
    "$SOURCES_DIR/Crypto.swift"
    "$SOURCES_DIR/RawWebSocket.swift"
    "$SOURCES_DIR/MTProtoHandshake.swift"
    "$SOURCES_DIR/MTProtoProxyServer.swift"
    "$SOURCES_DIR/LiveActivityManager.swift"
)

echo "Compiling ${#SWIFT_FILES[@]} Swift files..."

swiftc \
    -target "$TARGET" \
    -sdk "$SDK" \
    -O \
    -whole-module-optimization \
    -module-name TgWsProxy \
    -emit-executable \
    -o "$APP_DIR/TgWsProxy" \
    -framework Foundation \
    -framework SwiftUI \
    -framework UIKit \
    -framework Network \
    -framework ActivityKit \
    -framework WidgetKit \
    -import-objc-header /dev/null \
    "${SWIFT_FILES[@]}"

echo "Compilation successful."

# Strip debug symbols to reduce size
strip -x "$APP_DIR/TgWsProxy" 2>/dev/null || true

# Copy Info.plist
cp "$RESOURCES_DIR/Info.plist" "$APP_DIR/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/PkgInfo"

# Create minimal Assets.car placeholder (app icon not strictly required)
# The app will work without an icon on the home screen

# Create embedded.mobileprovision placeholder
# You need to provide your own provisioning profile
if [ -f "$SCRIPT_DIR/embedded.mobileprovision" ]; then
    cp "$SCRIPT_DIR/embedded.mobileprovision" "$APP_DIR/embedded.mobileprovision"
    echo "Copied provisioning profile."
else
    echo "WARNING: No embedded.mobileprovision found."
    echo "Place your provisioning profile at: $SCRIPT_DIR/embedded.mobileprovision"
    echo "The IPA will need to be signed before installation."
fi

# Create IPA
echo ""
echo "Creating IPA..."
cd "$BUILD_DIR"
zip -r -q "$IPA_PATH" Payload/
cd "$SCRIPT_DIR"

echo ""
echo "=== Build Complete ==="
echo "IPA: $IPA_PATH"
echo ""
echo "To install:"
echo "1. Sign the IPA with your developer certificate:"
echo "   codesign --force --sign 'Apple Development: YOUR_ID' --entitlements TgWsProxy/Resources/TgWsProxy.entitlements Payload/TgWsProxy.app"
echo "   OR use a tool like ios-app-signer, AltStore, or Sideloadly"
echo ""
echo "2. Install via:"
echo "   - ideviceinstaller -i TgWsProxy.ipa"
echo "   - OR drag into Apple Configurator 2"  
echo "   - OR use Sideloadly/AltStore"
echo ""
echo "After installing, configure Telegram Desktop/iOS to use MTProto proxy:"
echo "  Server: 127.0.0.1  Port: 1443  Secret: (shown in app)"
