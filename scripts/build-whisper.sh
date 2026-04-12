#!/bin/bash
# Build whisper.cpp as a static library with Metal acceleration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_DIR/whisper.cpp"
BUILD_DIR="$WHISPER_DIR/build"
LIB_OUTPUT_DIR="$PROJECT_DIR/lib"

echo "==> Building whisper.cpp static library with Metal support..."

# Verify submodule is initialized
if [ ! -f "$WHISPER_DIR/CMakeLists.txt" ]; then
    echo "Error: whisper.cpp submodule not initialized."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LIB_OUTPUT_DIR"

cd "$WHISPER_DIR"

MIN_MACOS="14.0"

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF

cmake --build build -j$(sysctl -n hw.ncpu) --config Release

# Copy static libraries to project lib directory
echo "==> Copying static libraries..."
cp build/src/libwhisper.a "$LIB_OUTPUT_DIR/"
find build/ggml -name "*.a" -exec cp {} "$LIB_OUTPUT_DIR/" \;

# Copy headers
echo "==> Copying headers..."
cp include/whisper.h "$LIB_OUTPUT_DIR/"
cp ggml/include/*.h "$LIB_OUTPUT_DIR/"

# List what we built
echo ""
echo "==> Built libraries:"
ls -lh "$LIB_OUTPUT_DIR/"*.a

echo ""
echo "==> Done! Libraries are in $LIB_OUTPUT_DIR/"
