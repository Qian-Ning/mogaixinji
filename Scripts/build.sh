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
BASE_FLAGS="-arch arm64 -miphoneos-version-min=14.0 -fobjc-arc $SDK_FLAGS"

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
    "$PROJECT_DIR/MogaiDylib/SandboxCleaner.m" \
    "$PROJECT_DIR/MogaiDylib/Fishhook/fishhook.c" \
    -framework Foundation \
    -framework UIKit \
    -framework CoreFoundation \
    -framework Security \
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
    -framework CoreGraphics

# 复制资源文件
echo "  Copying resources..."
cp "$PROJECT_DIR/MogaiConfig/Resources/Info.plist" "$CONFIG_APP_DIR/"
cp "$PROJECT_DIR/MogaiConfig/Resources/Entitlements.plist" "$CONFIG_APP_DIR/"

# 用 ldid 签上 TrollStore 兼容的权限
if command -v ldid &>/dev/null; then
    ldid -S"$CONFIG_APP_DIR/Entitlements.plist" "$CONFIG_APP_DIR/MogaiConfig" 2>/dev/null || true
    echo "  ✓ ldid signature applied"
else
    echo "  [!] ldid not found, skipping signature (TrollStore will handle it)"
fi

echo "  ✓ MogaiConfig.app built"

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