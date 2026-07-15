#!/usr/bin/env python3
"""
魔改新机 — Frida 配置版启动器
支持自定义设备参数，自动生成随机身份
"""

import frida
import sys
import json
import random
import string
import os

def random_uuid():
    return '{:08x}-{:04x}-4{:03x}-{:04x}-{:012x}'.format(
        random.randint(0, 0xFFFFFFFF),
        random.randint(0, 0xFFFF),
        random.randint(0, 0xFFF),
        random.randint(8, 0xB),
        random.randint(0, 0xFFFFFFFFFFFF)
    )

def random_mac():
    return ':'.join(['{:02x}'.format(random.randint(0, 255)) for _ in range(6)])

MODELS = [
    "iPhone16,2", "iPhone16,1", "iPhone15,5", "iPhone15,4",
    "iPhone15,3", "iPhone15,2", "iPhone15,1", "iPhone14,6",
    "iPhone14,5", "iPhone14,4", "iPhone14,3", "iPhone14,2",
]

VERSIONS = [
    "17.5.1", "17.4.1", "16.7", "16.6.1", "16.5.1", "15.8"
]

NAMES = ["iPhone", "My iPhone", "iPhone 15 Pro", "iPhone 16"]

def gen_identity(custom=None):
    c = custom or {}
    return {
        "idfv": random_uuid(),
        "deviceName": c.get("deviceName") or random.choice(NAMES),
        "model": c.get("model") or random.choice(MODELS),
        "systemVersion": c.get("systemVersion") or random.choice(VERSIONS),
        "serialNumber": random_uuid(),
        "wifiMac": random_mac(),
        "btMac": random_mac(),
        "locale": c.get("locale", "zh_CN"),
        "timezone": c.get("timezone", "Asia/Shanghai"),
    }

def on_message(message, data):
    if message['type'] == 'send':
        print(f"[App] {message['payload']}")
    elif message['type'] == 'error':
        print(f"[Error] {message['description']}")

def main():
    print("=" * 50)
    print("  魔改新机 — Frida 配置版启动器")
    print("=" * 50)

    # 检查设备
    try:
        device = frida.get_usb_device(timeout=5)
        print(f"[*] 设备: {device.name}")
    except Exception as e:
        print(f"[!] 找不到 USB 设备: {e}")
        print("[!] 请确认:")
        print("    1. iPhone 已通过 USB 连接")
        print("    2. iPhone 上 frida-server 正在运行")
        print("    3. iPhone 点了「信任此电脑」")
        sys.exit(1)

    # 生成身份
    identity = gen_identity()
    print(f"\n[*] 生成设备身份:")
    for k, v in identity.items():
        print(f"    {k}: {v}")

    # 读取脚本
    script_path = os.path.join(os.path.dirname(__file__), "hook.js")
    with open(script_path, 'r', encoding='utf-8') as f:
        hook_code = f.read()

    # 注入身份参数到脚本
    identity_json = json.dumps(identity, ensure_ascii=False)
    hook_code = f"var IDENTITY = {identity_json};\n" + hook_code.replace(
        "// ========== 随机生成器 ==========",
        "// ========== 随机生成器（已被Python替换）==========\n/*"
    ).replace(
        "console.log(\"[Mogai-Frida] ============================\");",
        "*/\nconsole.log(\"[Mogai-Frida] ============================\");"
    )

    # 启动抖音
    bundle_id = "com.ss.iphone.ugc.Aweme"
    print(f"\n[*] 启动 {bundle_id}...")

    try:
        pid = device.spawn([bundle_id])
        session = device.attach(pid)
        script = session.create_script(hook_code)
        script.on('message', on_message)
        script.load()
        device.resume(pid)
        print(f"[*] 注入成功，PID: {pid}")
        print("[*] 按 Ctrl+C 退出\n")
        sys.stdin.read()
    except frida.ProcessNotFoundError:
        print(f"[!] 找不到 {bundle_id}，尝试附加到已运行的抖音...")
        try:
            session = device.attach("抖音")
            script = session.create_script(hook_code)
            script.on('message', on_message)
            script.load()
            print("[*] 注入成功")
            sys.stdin.read()
        except Exception as e:
            print(f"[!] 附加失败: {e}")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n[*] 退出")
    except Exception as e:
        print(f"[!] 错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
