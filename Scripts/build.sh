#!/bin/bash
# ============================================================
# 魔改新机 v2.0 Pro - CI 自动编译脚本
# 在 macOS GitHub Actions runner 上运行
# 产物: build/output/MogaiDylib.dylib + MogaiConfig.ipa
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="$BUILD_DIR/output"
SDK=$(xcrun -sdk iphoneos --show-sdk-path)
SDK_FLAGS="-isysroot $SDK -F$SDK/System/Library/Frameworks -I$SDK/usr/include"
TARGET="-target arm64-apple-ios14.0"
BASE_FLAGS="-arch arm64 -fobjc-arc $TARGET $SDK_FLAGS"

echo "=========================================="
echo "  魔改新机 v2.0 Pro - CI Build"
echo "  SDK: $SDK"
echo "=========================================="

mkdir -p "$BUILD_DIR/obj" "$OUTPUT_DIR"

# =====================
# 1. 编译 MogaiDylib.dylib
# =====================
echo ""
echo "[1/3] Building MogaiDylib.dylib ..."

clang $BASE_FLAGS \
    -dynamiclib \
    -o "$OUTPUT_DIR/MogaiDylib.dylib" \
    "$PROJECT_DIR/MogaiDylib/MogaiDylib.m" \
    "$PROJECT_DIR/MogaiDylib/DeviceRandomizer.m" \
    "$PROJECT_DIR/MogaiDylib/Fishhook/fishhook.c" \
    -framework Foundation \
    -framework UIKit \
    -framework CoreFoundation \
    -install_name "@executable_path/MogaiDylib.dylib" \
    -Wno-deprecated-declarations

echo "  ✓ MogaiDylib.dylib ($(stat -f%z "$OUTPUT_DIR/MogaiDylib.dylib" 2>/dev/null || echo "unknown") bytes)"

# =====================
# 2. 编译 MogaiConfig.app
# =====================
echo ""
echo "[2/3] Building MogaiConfig.app ..."

CONFIG_APP_DIR="$OUTPUT_DIR/MogaiConfig.app"
mkdir -p "$CONFIG_APP_DIR"

# 编译所有 .m 文件
echo "  Compiling source files..."
for src in \
    "$PROJECT_DIR/MogaiConfig/main.m" \
    "$PROJECT_DIR/MogaiConfig/AppDelegate.m" \
    "$PROJECT_DIR/MogaiConfig/ViewControllers/MainVC.m" \
    "$PROJECT_DIR/MogaiConfig/ViewControllers/LogVC.m" \
    "$PROJECT_DIR/MogaiConfig/Models/MogaiConfig.m"; do

    if [ ! -f "$src" ]; then
        echo "  [!] Source not found: $src"
        exit 1
    fi
    basename=$(basename "$src" .m)
    clang $BASE_FLAGS \
        -I"$PROJECT_DIR/MogaiConfig" \
        -I"$PROJECT_DIR/MogaiConfig/ViewControllers" \
        -I"$PROJECT_DIR/MogaiConfig/Models" \
        -c "$src" \
        -o "$BUILD_DIR/obj/${basename}.o"
    echo "    compiled ${basename}.o"
done

# 链接
echo "  Linking..."
clang $BASE_FLAGS \
    "$BUILD_DIR/obj/"*.o \
    -o "$CONFIG_APP_DIR/MogaiConfig" \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -fobjc-link-runtime \
    -Wl,-no_adhoc_codesign

# 复制资源文件
echo "  Copying resources..."
cp "$PROJECT_DIR/MogaiConfig/Resources/Info.plist" "$CONFIG_APP_DIR/"
cp "$PROJECT_DIR/MogaiConfig/Resources/Entitlements.plist" "$CONFIG_APP_DIR/"

echo "  ✓ MogaiConfig.app built"

# 验证 .app 结构
echo ""
echo "  [Verify] App contents:"
ls -la "$CONFIG_APP_DIR/"
echo ""
if command -v file &>/dev/null; then
    echo "  [Verify] Binary type:"
    file "$CONFIG_APP_DIR/MogaiConfig"
fi
echo ""
if command -v otool &>/dev/null; then
    echo "  [Verify] Minimum deployment target:"
    otool -l "$CONFIG_APP_DIR/MogaiConfig" | grep -A2 "LC_VERSION_MIN\|LC_BUILD_VERSION" || echo "  (no version LC found!)"
fi

# =====================
# 3. 打包 MogaiConfig.ipa
# =====================
echo ""
echo "[3/3] Packaging MogaiConfig.ipa ..."

cd "$OUTPUT_DIR"
mkdir -p Payload
cp -r MogaiConfig.app Payload/
zip -q -r MogaiConfig.ipa Payload/
rm -rf Payload

echo "  ✓ MogaiConfig.ipa ($(stat -f%z "MogaiConfig.ipa" 2>/dev/null || echo "unknown") bytes)"

# 验证 IPA 内容
echo ""
echo "  [Verify] IPA contents:"
unzip -l MogaiConfig.ipa 2>/dev/null || echo "  (unzip failed!)"

# =====================
# 完成
# =====================
echo ""
echo "=========================================="
echo "  Build Complete!"
echo "=========================================="
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR/"
echo ""
echo "How to use:"
echo "  1. Download MogaiConfig.ipa from Actions artifacts"
echo "  2. AirDrop to iPhone → TrollStore → install"
echo "  3. Download MogaiDylib.dylib for repack script"
echo "  4. On iPhone, use TrollStore to install injected Douyin IPA"
echo "=========================================="