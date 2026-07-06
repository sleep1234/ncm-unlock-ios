#!/bin/bash

# NCM Unlock iOS 编译脚本
# 需要 macOS + Theos 环境

set -e

echo "=== NCM Unlock iOS 编译脚本 ==="

# 检查 Theos 环境
if [ -z "$THEOS" ]; then
    echo "错误: 未设置 THEOS 环境变量"
    echo "请先安装 Theos: https://theos.dev/docs/installation"
    exit 1
fi

# 检查是否在 macOS 上
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "警告: 当前不是 macOS 环境，可能无法编译"
fi

# 清理旧文件
echo "清理旧文件..."
make clean 2>/dev/null || true

# 编译
echo "开始编译..."
make package FINALPACKAGE=1

# 检查编译结果
if [ -f "packages/com.raincat.ncm-unlock-ios_*.deb" ]; then
    echo "=== 编译成功 ==="
    echo "deb 文件位置: packages/com.raincat.ncm-unlock-ios_*.deb"
    echo ""
    echo "安装方法:"
    echo "1. 将 deb 文件传输到 iPhone"
    echo "2. 使用 Filza 或 dpkg 安装:"
    echo "   dpkg -i com.raincat.ncm-unlock-ios_*.deb"
    echo "3. 重启网易云音乐"
else
    echo "=== 编译失败 ==="
    exit 1
fi
