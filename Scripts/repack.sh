#!/bin/bash
# ============================================================
# 魔改新机 v2.0 Pro - 一键重打包脚本
# 功能：砸壳 → 注入dylib → 重签名 → 输出IPA供TrollStore安装
# 使用: ./repack.sh <目标APP名称>
# 示例: ./repack.sh "抖音" 或 ./repack.sh "TikTok"
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DYLIB_PATH="$PROJECT_DIR/MogaiDylib/build/MogaiDylib.dylib"

TARGET_NAME="${1:-抖音}"
OUTPUT_DIR="$PROJECT_DIR/build"
OUTPUT_IPA="$OUTPUT_DIR/${TARGET_NAME}_魔改.ipa"
WORK_DIR="$OUTPUT_DIR/_repack_work"

echo "=========================================="
echo "  魔改新机 v2.0 Pro - 重打包工具"
echo "  目标APP: $TARGET_NAME"
echo "=========================================="

# 检查依赖
command -v frida >/dev/null 2>&1 || { echo "[!] 需要安装 frida (pip install frida-tools)"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "[!] 需要 unzip"; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "[!] 需要 zip"; exit 1; }

# 0. 检查dylib是否存在，不存在则编译
if [ ! -f "$DYLIB_PATH" ]; then
    echo "[*] 未找到编译好的dylib，尝试编译..."
    cd "$PROJECT_DIR/MogaiDylib"
    xcodebuild -project MogaiDylib.xcodeproj -scheme MogaiDylib -configuration Release -sdk iphoneos build \
        || { echo "[!] 编译失败，请先在Xcode中编译MogaiDylib target"; exit 1; }
    echo "[✓] dylib编译完成"
fi

# 1. 清理工作目录
rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# 2. 获取目标APP的Bundle ID
echo "[*] 获取设备上已安装的APP列表..."
# 尝试常见Bundle ID
case "$TARGET_NAME" in
    "抖音"|"Douyin"|"douyin")
        BUNDLE_ID="com.ss.iphone.ugc.Aweme"
        ;;
    "TikTok"|"tiktok")
        BUNDLE_ID="com.zhiliaoapp.musically"
        ;;
    *)
        echo "[?] 未知APP，尝试使用输入的Bundle ID..."
        BUNDLE_ID="$TARGET_NAME"
        ;;
esac
echo "[*] Bundle ID: $BUNDLE_ID"

# 3. 使用frida-ios-dump砸壳
echo "[*] 砸壳中 (需要iPhone连接并且运行frida-server)..."
frida-ios-dump "$BUNDLE_ID" "$WORK_DIR/decrypted.ipa" \
    || { echo "[!] 砸壳失败，请确认："; echo "   1. iPhone通过USB连接"; echo "   2. iPhone上运行着frida-server"; echo "   3. 目标APP已安装"; exit 1; }
echo "[✓] 砸壳完成"

# 4. 解压IPA
echo "[*] 解压IPA..."
cd "$WORK_DIR"
unzip -q decrypted.ipa -d payload/
PAYLOAD_DIR="$WORK_DIR/payload/Payload"
APP_DIR=$(ls "$PAYLOAD_DIR" | grep ".app$" | head -1)
echo "[*] APP目录: $APP_DIR"

# 5. 注入dylib
echo "[*] 注入dylib..."
cp "$DYLIB_PATH" "$PAYLOAD_DIR/$APP_DIR/"
# 使用install_name_tool修改加载路径
install_name_tool -id "@executable_path/MogaiDylib.dylib" "$PAYLOAD_DIR/$APP_DIR/MogaiDylib.dylib"
# 使用optool或insert_dylib注入
if command -v optool &>/dev/null; then
    optool install -p "@executable_path/MogaiDylib.dylib" -t "$PAYLOAD_DIR/$APP_DIR/$TARGET_NAME"
elif command -v insert_dylib &>/dev/null; then
    insert_dylib --strip-codesign --all-yes "@executable_path/MogaiDylib.dylib" \
        "$PAYLOAD_DIR/$APP_DIR/$TARGET_NAME" "$PAYLOAD_DIR/$APP_DIR/${TARGET_NAME}_patched"
    mv "$PAYLOAD_DIR/$APP_DIR/${TARGET_NAME}_patched" "$PAYLOAD_DIR/$APP_DIR/$TARGET_NAME"
else
    echo "[!] 需要 optool 或 insert_dylib"
    echo "    安装: brew install optool"
    exit 1
fi
echo "[✓] dylib注入完成"

# 6. 重签名
echo "[*] 重签名..."
# 生成entitlements
ldid -e "$PAYLOAD_DIR/$APP_DIR" > "$WORK_DIR/entitlements.plist" 2>/dev/null || true
# 使用TrollStore的签名方式——直接用ldid
ldid -S"$WORK_DIR/entitlements.plist" "$PAYLOAD_DIR/$APP_DIR/$TARGET_NAME" 2>/dev/null || true
ldid -S "$PAYLOAD_DIR/$APP_DIR/MogaiDylib.dylib"

# 对Framework签名
for fw in "$PAYLOAD_DIR/$APP_DIR/Frameworks/"*; do
    if [ -d "$fw" ] || [ -f "$fw" ]; then
        ldid -S "$fw" 2>/dev/null || true
    fi
done

echo "[✓] 重签名完成"

# 7. 打包IPA
echo "[*] 打包IPA..."
cd "$WORK_DIR/payload"
zip -qr "$OUTPUT_IPA" Payload/
echo "[✓] IPA已生成: $OUTPUT_IPA"

# 8. 清理临时文件
cd "$PROJECT_DIR"
rm -rf "$WORK_DIR"

echo ""
echo "=========================================="
echo "  完成！"
echo "  IPA位置: $OUTPUT_IPA"
echo "  使用方法："
echo "  1. 将IPA传到iPhone (AirDrop / 网盘)"
echo "  2. 用TrollStore打开安装"
echo "  3. 首次安装配置APP → 设置参数"
echo "  4. 重新安装注入版抖音 → 享受魔改新机"
echo "=========================================="
