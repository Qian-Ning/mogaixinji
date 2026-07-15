@echo off
chcp 65001 >nul
title 魔改新机 — Frida 启动器

echo ==========================================
echo   魔改新机 Frida 启动器
echo ==========================================
echo.

:: 检查 frida 是否安装
where frida >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] 未找到 frida，正在安装...
    pip install frida-tools
    if %errorlevel% neq 0 (
        echo [!] 安装失败，请手动执行: pip install frida-tools
        pause
        exit /b 1
    )
)

:: 检查 USB 设备
echo [*] 检查 iPhone 连接...
frida-ls-devices
echo.

:: 检查抖音是否在运行
echo [*] 当前运行的进程（查找抖音）...
frida-ps -U | findstr /i "aweme douyin"
echo.

:: 获取脚本路径
set SCRIPT_PATH=%~dp0hook.js
echo [*] Hook 脚本路径: %SCRIPT_PATH%
echo.

echo [*] 启动抖音并注入 Hook...
echo [*] 按 Ctrl+C 停止
echo.

frida -U -f com.ss.iphone.ugc.Aweme -l "%SCRIPT_PATH%"

pause
