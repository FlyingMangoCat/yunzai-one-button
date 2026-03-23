#!/bin/bash

# 容器启动脚本

# 检查是否已安装云崽
if [ ! -f "/app/package.json" ]; then
    echo "首次启动，请先在宿主机上运行安装脚本安装云崽"
    echo "运行: bash YZv3.sh"
    echo "选择: 1. 安装芒果猫版云崽 或 2. 安装喵版云崽"
    sleep 30
    exit 1
fi

# 设置环境变量
export CHROME_BIN=/usr/bin/chromium-browser
export CHROME_PATH=/usr/bin/chromium-browser

# 启动云崽
echo "正在启动云崽..."
cd /app
node app