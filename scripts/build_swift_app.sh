#!/usr/bin/env bash
set -euo pipefail

# Build signed macOS .app for Detto (Swift)
# Usage:
#   ./scripts/build_swift_app.sh
#
# For CI / explicit identity:
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./scripts/build_swift_app.sh
#
# For notarization:
#   APPLE_ID="name@example.com"
#   APPLE_TEAM_ID="TEAMID123"
#   APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
SWIFT_DIR="$ROOT_DIR/Detto"
APP_NAME="Detto"
BUNDLE_ID="io.gremble.detto"

echo "=== Building $APP_NAME (Swift) ==="

# Build release binary
cd "$SWIFT_DIR"
swift build -c release 2>&1
BINARY_PATH=".build/release/Detto"

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Build failed: binary not found at $BINARY_PATH"
  exit 1
fi

echo "Binary built: $BINARY_PATH"

# Create .app bundle
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy binary
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/Detto"

# Make the SwiftPM-built executable behave like a normal app bundle by
# teaching dyld to search the app's embedded Frameworks directory.
APP_BINARY="$APP_DIR/Contents/MacOS/Detto"
if ! otool -l "$APP_BINARY" | grep -Fq "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  echo "Added app Frameworks rpath to executable"
fi

# Copy Info.plist
cp "$SWIFT_DIR/Sources/Detto/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy app icon
ICON_PATH="$SWIFT_DIR/Sources/Detto/Assets/AppIcon.icns"
if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
  echo "App icon copied"
fi

# Copy fonts and license
mkdir -p "$APP_DIR/Contents/Resources/Fonts"
cp "$SWIFT_DIR/Sources/Detto/Fonts/"*.ttf "$APP_DIR/Contents/Resources/Fonts/"
cp "$SWIFT_DIR/Sources/Detto/Fonts/OFL.txt" "$APP_DIR/Contents/Resources/Fonts/"
echo "Fonts copied"

# Copy Sparkle framework
SPARKLE_ARTIFACT_DIR="$SWIFT_DIR/.build/artifacts/sparkle"
SPARKLE_FW=$(find "$SPARKLE_ARTIFACT_DIR" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [[ -n "$SPARKLE_FW" ]]; then
  cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
  echo "Sparkle.framework copied"
else
  echo "Warning: Sparkle.framework not found in build artifacts"
fi

# Compile MLX Metal shaders into default.metallib
MLX_METAL_DIR="$SWIFT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
if [[ -d "$MLX_METAL_DIR" ]]; then
  METAL_BUILD_DIR=$(mktemp -d)
  echo "Compiling MLX Metal shaders..."
  find "$MLX_METAL_DIR" -name "*.metal" | while read f; do
    name=$(basename "$f" .metal)
    xcrun metal -c -target air64-apple-macos26.0 -I "$MLX_METAL_DIR" "$f" -o "$METAL_BUILD_DIR/$name.air"
  done
  mkdir -p "$APP_DIR/Contents/MacOS/Resources"
  xcrun metallib "$METAL_BUILD_DIR"/*.air -o "$APP_DIR/Contents/MacOS/Resources/mlx.metallib"
  rm -rf "$METAL_BUILD_DIR"
  echo "MLX metallib compiled: $(du -h "$APP_DIR/Contents/MacOS/Resources/mlx.metallib" | cut -f1)"
else
  echo "Warning: MLX Metal shaders not found at $MLX_METAL_DIR"
fi

# Add PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "App bundle created: $APP_DIR"

# Auto-detect signing identity if not set
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
  fi
fi

# Sign the app
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  ENTITLEMENTS="$SWIFT_DIR/Sources/Detto/Detto.entitlements"
  echo "Signing with: $CODESIGN_IDENTITY"

  # Sign Sparkle components inside-out (innermost first)
  SPARKLE_FW_BUNDLE="$APP_DIR/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$SPARKLE_FW_BUNDLE" ]]; then
    # Sign XPC service executables, then their bundles
    for xpc in "$SPARKLE_FW_BUNDLE"/Versions/B/XPCServices/*.xpc; do
      if [[ -d "$xpc" ]]; then
        codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$xpc/Contents/MacOS/$(basename "${xpc%.xpc}")"
        codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$xpc"
      fi
    done

    # Sign Autoupdate helper
    AUTOUPDATE="$SPARKLE_FW_BUNDLE/Versions/B/Autoupdate"
    if [[ -f "$AUTOUPDATE" ]]; then
      codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$AUTOUPDATE"
    fi

    # Sign Updater.app
    UPDATER_APP="$SPARKLE_FW_BUNDLE/Versions/B/Updater.app"
    if [[ -d "$UPDATER_APP" ]]; then
      codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$UPDATER_APP/Contents/MacOS/Updater"
      codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$UPDATER_APP"
    fi

    # Sign the framework dylib, then the framework bundle
    codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$SPARKLE_FW_BUNDLE/Versions/B/Sparkle"
    codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --timestamp "$SPARKLE_FW_BUNDLE"
  fi

  # Sign MLX metallib
  MLX_METALLIB="$APP_DIR/Contents/MacOS/Resources/mlx.metallib"
  if [[ -f "$MLX_METALLIB" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$MLX_METALLIB"
  fi

  # Sign the main app bundle
  codesign --force --options runtime \
    --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_DIR"

  echo "Code signing complete"
  codesign -vvv "$APP_DIR"
else
  echo "Warning: No signing identity found. App will be unsigned."
  echo "Set CODESIGN_IDENTITY or install a Developer ID certificate for signed builds."
fi

# Install to /Applications if writable
if [[ -w /Applications/ ]]; then
  cp -R "$APP_DIR" /Applications/
  echo "Installed to /Applications/$APP_NAME.app"
else
  echo "Skipped install to /Applications (no write access). App is at: $APP_DIR"
fi

echo "=== Build complete ==="
