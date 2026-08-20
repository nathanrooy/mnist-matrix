#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/MNISTMatrix.saver"
INSTALL_DIR="$HOME/Library/Screen Savers"

# Determine target architecture (default to host machine architecture)
ARCH_INPUT="${1:-$(uname -m)}"

if [ "$ARCH_INPUT" = "arm64" ] || [ "$ARCH_INPUT" = "apple" ] || [ "$ARCH_INPUT" = "aarch64" ]; then
    TARGET_ARCH="arm64"
    TARGET_TRIPLE="arm64-apple-macos12.0"
    ARCH_LABEL="Apple Silicon (arm64)"
elif [ "$ARCH_INPUT" = "x86_64" ] || [ "$ARCH_INPUT" = "intel" ]; then
    TARGET_ARCH="x86_64"
    TARGET_TRIPLE="x86_64-apple-macos12.0"
    ARCH_LABEL="Intel (x86_64)"
else
    echo "Unknown architecture '$ARCH_INPUT'. Usage: ./build.sh [arm64|x86_64]"
    exit 1
fi

# Verify mnist_atlas.bin exists in resources/
if [ ! -f "$PROJECT_DIR/resources/mnist_atlas.bin" ]; then
    echo "Error: resources/mnist_atlas.bin not found."
    echo "If regenerating from data/test-00000-of-00001.parquet, run: python3 scripts/munge.py"
    exit 1
fi

echo "=== 1. Creating Screen Saver Bundle Structure ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$PROJECT_DIR/src/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/resources/mnist_atlas.bin" "$BUNDLE_DIR/Contents/Resources/mnist_atlas.bin"

echo "=== 2. Compiling $ARCH_LABEL Swift ScreenSaver Binary ==="
swiftc -emit-library \
    -o "$BUNDLE_DIR/Contents/MacOS/MNISTMatrix" \
    "$PROJECT_DIR/src/MNISTAtlas.swift" \
    "$PROJECT_DIR/src/MNISTMatrixSaverView.swift" \
    -framework ScreenSaver \
    -framework AppKit \
    -framework CoreGraphics \
    -target "$TARGET_TRIPLE" \
    -O

echo "=== 3. Code Signing & Installing to $INSTALL_DIR ==="
codesign --force --deep -s - "$BUNDLE_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/MNISTMatrix.saver"
cp -R "$BUNDLE_DIR" "$INSTALL_DIR/"
codesign --force --deep -s - "$INSTALL_DIR/MNISTMatrix.saver"

# Flush legacyScreenSaver in-memory cache so System Settings loads the fresh bundle
killall legacyScreenSaver WallpaperAgent 2>/dev/null || true

echo ""
echo "=== BUILD SUCCESSFUL ==="
echo "Installed $ARCH_LABEL Screen Saver to: $INSTALL_DIR/MNISTMatrix.saver"
echo ""
echo "To configure or test in macOS System Settings, run:"
echo "open \"$INSTALL_DIR/MNISTMatrix.saver\""
