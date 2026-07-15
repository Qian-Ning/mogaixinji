# 魔改新机 — Frida 方案完整实操指南

## 一、环境准备

### 1. iPhone 端（iOS 14.0-16.6，TrollStore）

#### 安装 frida-server

**方法1：TrollStore 安装 frida-server（推荐）**

1. 下载 TrollStore 兼容的 frida-server：
   - 去 https://github.com/frida/frida/releases
   - 找到对应版本，下载 `frida-server-X.X.X-ios-arm64.xz`
   - 解压得到 `frida-server-X.X.X-ios-arm64`

2. 将 frida-server 包装成 IPA：
   - 用 Filza 或 SSH 将 frida-server 二进制放入一个 .app 目录
   - 或者直接用现成的 TrollStore 版 frida-server IPA（GitHub搜 "frida-server trollstore"）

3. TrollStore 安装该 IPA

4. 打开 frida-server app，点 "Start" 启动

**方法2：通过 TrollStore 的 SSH/RiceShell 执行**

如果你有 TrollStore 装的 SSH 工具（如 OpenSSH via TrollStore）：
```bash
# 将 frida-server 传到 iPhone
scp frida-server mobile@iPhone_IP:/var/mobile/

# SSH 进 iPhone 执行
ssh mobile@iPhone_IP
chmod +x /var/mobile/frida-server
/var/mobile/frida-server &
```

#### 验证 frida-server 运行
```bash
# 在 Windows 上执行
frida-ps -U
# 如果能看到进程列表，说明连接成功
```

---

### 2. Windows 端

```bash
# 安装 Python 3.x（去 python.org 下载）
# 然后：
pip install frida-tools

# 验证
frida --version
```

#### 安装 iTunes（需要 Apple USB 驱动）
- 去苹果官网下载 iTunes 64位
- 安装后用数据线连接 iPhone
- iPhone 上点「信任此电脑」

---

## 二、连接与启动

### 1. USB 连接 iPhone

```bash
# 确认设备连接
frida-ls-devices

# 输出应该类似：
# id: auto11223344
# type: usb
# name: iPhone
```

### 2. 列出抖音进程

```bash
frida-ps -U
# 找到 com.ss.iphone.ugc.Aweme 或 抖音
```

### 3. 启动 Hook 脚本

**方式A：附加到已运行的抖音**
```bash
frida -U -n "抖音" -l hook.js
# 或用 Bundle ID
frida -U -f com.ss.iphone.ugc.Aweme -l hook.js --no-pause
```

**方式B：冷启动抖音并注入（推荐）**
```bash
frida -U -f com.ss.iphone.ugc.Aweme -l hook.js
```

---

## 三、Hook 脚本说明

`hook.js` 是核心脚本，功能包括：

1. **UIDevice 伪装** — idfv / model / systemVersion / name
2. **MobileGestalt (MGCopyAnswer)** — 全量设备硬件参数
3. **sysctl** — hw.machine / hw.model
4. **IDFA** — advertisingIdentifier
5. **NSProcessInfo** — operatingSystemVersionString
6. **验证弹窗拦截** — presentViewController 关键词匹配
7. **网络请求拦截** — 修改 NSURLSession 请求头/参数
8. **参数随机化** — 每次启动生成全新设备身份

---

## 四、使用流程

### 标准操作（每次改机）

1. iPhone 上启动 frida-server（TrollStore app 里点 Start）
2. Windows 上打开终端
3. 执行：
   ```bash
   frida -U -f com.ss.iphone.ugc.Aweme -l hook.js
   ```
4. 抖音会自动启动，Hook 生效
5. 看到 `[Mogai-Frida] hooks active` 说明注入成功

### 换身份

1. Ctrl+C 停止当前 Frida 会话
2. 杀掉抖音后台
3. 重新执行启动命令（脚本会自动生成新随机参数）

### 自定义参数

编辑 `hook.js` 开头的 `CONFIG` 部分：
```javascript
var CONFIG = {
    model: "iPhone15,3",        // 改成你想要的型号
    systemVersion: "16.6.1",    // 系统版本
    deviceName: "My iPhone",    // 设备名
    // 留空的参数会自动随机生成
};
```

---

## 五、常见问题

### Q: frida-ps -U 连不上？
- 确认 iPhone 上 frida-server 在运行
- 确认 USB 连接正常，iPhone 点了「信任」
- 尝试重启 frida-server
- 检查 Windows 上 iTunes Apple Mobile Device Service 是否在运行

### Q: 抖音启动后还是闪退？
- Frida 注入比 dylib 注入隐蔽得多，一般不会闪退
- 如果闪退，尝试加 `--no-pause` 参数让脚本立刻执行
- 确认 frida-server 版本和 frida-tools 版本一致

### Q: 抖音检测到 Frida？
- 尝试用 `frida-server` 改名后运行
- 或使用 `objection` 的 anti-anti-frida 补丁
- 命令：`frida --codeshare pcipolloni/universal-androidssl-pinning-bypass -U -f com.ss.iphone.ugc.Aweme`

### Q: Hook 生效但还是有验证？
- 确认 `[Mogai-Frida] hooks active` 日志出现
- 清理抖音数据：设置→通用→iPhone存储→抖音→删除APP，重装
- 配合切换网络/IP 使用

---

## 六、对比其他方案

| 方案 | 隐蔽性 | 难度 | 是否需连电脑 | 效果 |
|------|--------|------|------------|------|
| **Frida（本方案）** | 高 | 中 | 是 | 好 |
| dylib 注入 | 低（易被检测） | 低 | 否 | 差（闪退） |
| mitmproxy | 最高 | 高 | 是 | 中（需逆向签名） |
| 多开+描述文件 | 中 | 低 | 否 | 一般 |
| 自建API中转 | 最高 | 极高 | 否 | 最好 |
