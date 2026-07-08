# 魔改新机 v2.0 Pro — TrollStore 注入版

iOS 14.0–16.6 无越狱设备改机工具，通过 TrollStore 注入 dylib 实现设备指纹伪造 + 沙盒清理。

## 架构总览

```
┌─────────────────────────────────────┐
│       MogaiConfig (TrollStore APP)   │ ← 配置UI、生成参数、标记清理
│       Bundle: com.mogai.config       │
└──────────────┬──────────────────────┘
               │ NSUserDefaults (suite: group.com.mogai.config)
               ▼
┌─────────────────────────────────────┐
│   MogaiDylib.dylib (注入目标APP)     │ ← 所有Hook逻辑在此
│   通过 insert_dylib 注入抖音          │
└─────────────────────────────────────┘
```

**通信方式**: 两组件通过 `NSUserDefaults initWithSuiteName:@"group.com.mogai.config"` 共享配置。配置APP写入 → dylib读取。

## 文件结构

```
MogaiXinji/
├── MogaiDylib/                          # 注入动态库
│   ├── MogaiDylib.m                     # 主入口 + 所有Hook注册
│   ├── DeviceRandomizer.h/m             # 参数生成器 + 配置读写
│   ├── SandboxCleaner.h/m               # 沙盒/Keychain/Cookie清理
│   ├── Fishhook/fishhook.h/c            # Facebook符号劫持库
│   └── Info.plist
│
├── MogaiConfig/                         # TrollStore 配置APP
│   ├── AppDelegate.h/m                  # 启动入口 (TabBar)
│   ├── ViewControllers/
│   │   ├── MainVC.h/m                   # 主界面：开关、参数预览、操作按钮
│   │   └── LogVC.h/m                    # 本地日志查看
│   ├── Models/
│   │   └── MogaiConfig.h/m              # 配置模型 + NSUserDefaults读写
│   └── Resources/
│       ├── Info.plist
│       └── Entitlements.plist
│
├── Scripts/
│   └── repack.sh                        # 砸壳→注入→重签名→IPA 一键脚本
│
└── README.md
```

## Hook层覆盖（6层）

| 层面 | 具体Hook点 | 作用 |
|------|-----------|------|
| **1. UIDevice** | `identifierForVendor`, `name`, `model`, `systemVersion`, `localizedModel` | 基础设备参数 |
| **2. NSProcessInfo** | `operatingSystemVersionString`, `hostName`, `systemUptime` | 系统信息伪造 |
| **3. MobileGestalt** | `MGCopyAnswer` (UniqueDeviceID, Serial, WiFiMAC, ProductType等) | 私有硬件参数，抖音风控核心检测点 |
| **4. 文件系统隐藏** | `stat`, `lstat`, `access`, `open`, `[NSFileManager fileExistsAtPath:]` | 隐藏越狱痕迹 |
| **5. 注入检测隐藏** | `_dyld_image_count`, `_dyld_get_image_name`, `dladdr` | 隐藏注入dylib自身 |
| **6. 数据清理** | `SecItemCopyMatching`, 沙盒文件删除, Cookie清理, NSUserDefaults清理 | 一键重置环境 |

## 编译指南

### 准备工作

- Mac + Xcode 15+
- iPhone (iOS 14.0–16.6) 已安装 TrollStore
- iPhone 通过 USB 连接
- iPhone 上运行 frida-server（用于砸壳）
- `pip install frida-tools`
- `brew install optool`（用于注入dylib到MachO）

### 步骤

#### 1. 编译 MogaiDylib.dylib

在 Xcode 中新建 Dynamic Library 工程：
- Product Name: `MogaiDylib`
- Language: Objective-C
- 将 `MogaiDylib/MogaiDylib.m`, `DeviceRandomizer.h/m`, `SandboxCleaner.h/m`, `Fishhook/fishhook.h/c` 加入工程
- Build Settings:
  - Architectures: `arm64`
  - iOS Deployment Target: `14.0`
  - Mach-O Type: `Dynamic Library`
  - Signing: 不需要正式签名（TrollStore绕过）
- Build → 产物在 `Build/Products/Release-iphoneos/MogaiDylib.dylib`

#### 2. 编译 MogaiConfig.app

在 Xcode 中新建 iOS App 工程：
- Product Name: `MogaiConfig`
- Bundle ID: `com.mogai.config`
- Team: None（TrollStore不需要）
- 将所有 `MogaiConfig/` 下的源文件加入工程
- Build → 产物是 `.app` 包

#### 3. 打包配置APP为IPA

将编译出的 `MogaiConfig.app` 打包：
```bash
mkdir -p Payload
cp -r MogaiConfig.app Payload/
zip -qr MogaiConfig.ipa Payload/
```
通过 AirDrop/网盘 传到 iPhone，用 TrollStore 打开安装。

#### 4. 砸壳 + 重打包抖音

```bash
# 确保 iPhone 连接且 frida-server 在运行

# 砸壳
frida-ios-dump com.ss.iphone.ugc.Aweme ./douyin.ipa

# 解压
unzip -q douyin.ipa -d work/
cd work/Payload
APP="Douyin.app"  # 具体名称看解压结果

# 复制dylib
cp /path/to/MogaiDylib.dylib "$APP/"
install_name_tool -id "@executable_path/MogaiDylib.dylib" "$APP/MogaiDylib.dylib"

# 注入
optool install -p "@executable_path/MogaiDylib.dylib" -t "$APP/Douyin"

# 重签名 (用于TrollStore)
ldid -S "$APP/MogaiDylib.dylib"
ldid -S "$APP/Douyin"

# 打包
cd ..
zip -qr ../douyin_mogai.ipa Payload/
```

#### 5. 安装

1. 先用 TrollStore 安装 `MogaiConfig.ipa` → 打开 → 设置参数 → 生成新参数
2. 再用 TrollStore 安装 `douyin_mogai.ipa` → 打开抖音 → 自动加载注入

每次想换设备身份 → 打开配置APP → 一键生成 → 杀掉抖音重开。

## 【免核对】原理说明

抖音注册/登录的"免核对"不是绕过短信验证，而是**不触发设备安全验证滑块**。实现路径：

```
改机参数全新 → 设备信任分初始高 → 不弹滑块/设备绑定 → 正常走手机号注册
  ↑                    ↑                       ↑
  Hook层               MGCopyAnswer            stat/access
  全部伪造             返回随机硬件ID          隐藏越狱痕迹
```

配合本工具的沙盒清理 + Keychain擦除 + 全新设备指纹，每次改机相当于抖音看到一台新出厂的 iPhone。

> ⚠️ 注意：短信验证码是运营商层面，改机不影响。免核对指的是"不额外弹设备安全验证"。

## 调试

查看 dylib 运行日志：
```bash
idevicesyslog | grep Mogai
```
