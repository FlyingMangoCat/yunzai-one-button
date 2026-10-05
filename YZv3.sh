#!/bin/bash

# ===========================================
# Yunzai一键安装脚本
# 版本: 3.0.0
# ===========================================

# ---------- 配置 ----------
VERSION="3.0.0"
SUPPORT_GROUP="658720198"
# 脚本所在目录（锚定安装位置，从任何目录启动脚本都能找到已安装的云崽）
# 注意: 用 bash <(curl ...) 管道方式运行时 BASH_SOURCE 指向 /proc/self/fd/xx（虚拟
# 文件，无法建目录），此时回退到家目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"
case "$SCRIPT_DIR" in
    /proc/*|/dev/*) SCRIPT_DIR="$HOME" ;;
esac
YUNZAI_DIR="$SCRIPT_DIR/yunzai-one-button-fmc"
CURRENT_PLATFORM=""
CURRENT_OS=""
IS_TERMUX=false

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件（新版 Android 限制写 /sdcard 根目录，实测可写才用，否则存到家目录）
if [ -d "/sdcard" ] && echo test > /sdcard/.yzb_write_test 2>/dev/null; then
    rm -f /sdcard/.yzb_write_test
    LOG_FILE="/sdcard/yunzai_install.log"
else
    LOG_FILE="$HOME/yunzai_install.log"
fi

# ---------- Windows 自动提权 ----------
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    powershell -Command "New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()) | ? { \$_.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "正在申请管理员权限..."
        powershell -Command "Start-Process -FilePath 'bash' -ArgumentList '-c \"cd $(pwd) && bash $0\"' -Verb RunAs -WindowStyle Hidden" 2>/dev/null
        exit 0
    fi
fi

# ---------- 日志函数 ----------
log() { local msg="$1"; local t=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "[$t] $msg" | tee -a "$LOG_FILE"; }
success() { log "${GREEN}[SUCCESS] $1${NC}"; }
warn() { log "${YELLOW}[WARNING] $1${NC}"; }
error() { log "${RED}[ERROR] $1${NC}"; exit 1; }

# ---------- Termux 主源切换清华镜像 ----------
# 官方 CDN(packages-cf.termux.dev) 部分网络极慢/超时, 实测清华镜像可用;
# 已使用国内镜像则不动, 原源备份为 sources.list.bak.yzb 可随时还原
ensure_termux_mirror() {
    local src="$PREFIX/etc/apt/sources.list"
    [ -f "$src" ] || return 0
    # 空文件/无有效行会导致 pkg 报 "No mirror or mirror group selected"，先恢复备份
    if [ ! -s "$src" ] || ! grep -q "^deb " "$src"; then
        if [ -s "$src.bak.yzb" ]; then
            log "sources.list 为空或损坏，从备份恢复..."
            cp "$src.bak.yzb" "$src"
        else
            echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" > "$src"
        fi
    fi
    if grep -q "mirrors.tuna.tsinghua.edu.cn\|mirrors.bfsu.edu.cn\|mirrors.ustc.edu.cn" "$src"; then
        return 0
    fi
    log "Termux 主源为官方 CDN, 切换为清华镜像加速（原源已备份为 sources.list.bak.yzb）..."
    cp "$src" "$src.bak.yzb" 2>/dev/null || true
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" > "$src"
}

# ---------- sqlite3 源码补丁（Termux/clang 21 专用） ----------
# sqlite3@5.1.6 的 statement.cc 两处 SQLITE_TRANSIENT 在 clang 21 下报
# invalid conversion 'int' to 'sqlite3_destructor_type'，
# 在调用点补显式强转修复；幂等，已打过的不重复处理
patch_sqlite_sources() {
    local base="$1"
    local patched=0
    while IFS= read -r f; do
        if grep -q "SQLITE_TRANSIENT" "$f" && ! grep -q "sqlite3_destructor_type)-1" "$f"; then
            sed -i 's/SQLITE_TRANSIENT)/((sqlite3_destructor_type)-1))/g' "$f"
            log "已补丁 sqlite3 源码: $f"
            patched=$((patched+1))
        fi
    done < <(find "$base/node_modules/.pnpm" -name statement.cc -path "*sqlite3*/src/*" 2>/dev/null)
    [ $patched -gt 0 ] && success "sqlite3 源码补丁完成（$patched 处）" || log "sqlite3 源码无需补丁"
}

# ---------- 1. 获取权限 ----------
get_permissions() {
    log "获取系统权限..."
    termux-setup-storage 2>/dev/null || true
    termux-wake-lock 2>/dev/null || true
    local tf=".perm_test_$$"
    if ! echo "test" > "$tf" 2>/dev/null; then error "无法写入文件，请检查目录权限"; fi
    rm -f "$tf"
    success "权限检查通过"
}

# ---------- 2. 检测平台 ----------
detect_platform() {
    log "检测当前平台..."
    if [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "linux-android"* ]]; then
        CURRENT_OS="Linux"
        # Termux 判定三重依据: TERMUX_VERSION 变量 / PREFIX 指向 Termux 路径 / 固定目录存在
        if [ -n "$TERMUX_VERSION" ] || { [ -n "$PREFIX" ] && [ -d "/data/data/com.termux" ]; }; then
            CURRENT_PLATFORM="Termux"
            IS_TERMUX=true
        else
            CURRENT_PLATFORM="Linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        CURRENT_OS="macOS"; CURRENT_PLATFORM="macOS"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        CURRENT_OS="Windows"; CURRENT_PLATFORM="Windows"
    else
        CURRENT_PLATFORM="Unknown"; CURRENT_OS="Unknown"
    fi
    success "检测到平台: $CURRENT_PLATFORM ($CURRENT_OS)"
    echo -e "${GREEN}当前平台: $CURRENT_PLATFORM ($CURRENT_OS)${NC}"
}

# ---------- 3. 安装环境依赖（每项验证，失败重试） ----------
install_environment() {
    log "配置运行环境..."

    case "$CURRENT_PLATFORM" in
        "Termux")
            log "Termux 环境安装..."
            # 官方 CDN 慢时自动切国内镜像（内部已判断，已在用国内源则不动）
            ensure_termux_mirror
            # 更新源（失败不阻断，错误可见）
            pkg update -y 2>&1 | tee -a "$LOG_FILE" || true
            pkg upgrade -y 2>&1 | tee -a "$LOG_FILE" || true
            # 核心依赖逐个安装并重试，失败原因直接可见
            # 注意: Termux 仓库无 python3(包名是 python)、无 wqy 字体包, 勿照搬发行版包名
            # python/make/clang/binutils 是 node-gyp 编译工具链, sqlite3 等原生模块必需
            local core_pkgs=(nodejs-lts git redis wget curl python ffmpeg make clang binutils fontconfig)
            for pkg in "${core_pkgs[@]}"; do
                for i in 1 2 3; do
                    pkg install -y "$pkg" 2>&1 | tee -a "$LOG_FILE"
                    [ "${PIPESTATUS[0]}" -eq 0 ] && break
                    log "安装 $pkg 失败，重试 ($i/3)..."
                    sleep 2
                done
            done
            # 验证关键组件是否安装成功
            command -v node &>/dev/null || error "Node.js 安装失败，请检查 pkg 源和网络（详见日志 $LOG_FILE）"
            command -v git &>/dev/null || error "Git 安装失败"
            # Chromium 在 x11 仓库（main 仓库没有），需先启用 x11-repo；体积大易失败，不阻塞主流程
            if ! command -v chromium &>/dev/null; then
                pkg install -y x11-repo 2>&1 | tee -a "$LOG_FILE" || true
                # x11 源默认指向官方 CDN，切到实测可用的 BFSU 镜像（tuna 未同步 x11）
                local x11src="$PREFIX/etc/apt/sources.list.d/x11.list"
                if [ -f "$x11src" ]; then
                    cp "$x11src" "$x11src.bak.yzb" 2>/dev/null || true
                    echo "deb https://mirrors.bfsu.edu.cn/termux/apt/termux-x11 x11 main" > "$x11src"
                fi
                pkg update -y 2>&1 | tee -a "$LOG_FILE" || true
                pkg install -y chromium 2>&1 | tee -a "$LOG_FILE"
                [ "${PIPESTATUS[0]}" -ne 0 ] && warn "Chromium 安装失败，可稍后手动执行: pkg install x11-repo && pkg update && pkg install chromium"
            fi
            # 中文字体（Termux 仓库无 wqy 字体包，直接下载字体文件；缺失会导致渲染图片中文乱码）
            # 三源依次尝试: jsDelivr → gh-proxy → GitHub raw，全部实测可用；TTF 魔数(00 01 00 00)校验
            if ! fc-list 2>/dev/null | grep -qi "simhei\|wqy\|noto.*cjk"; then
                mkdir -p "$PREFIX/share/fonts"
                local font_urls=(
                    "https://cdn.jsdelivr.net/gh/StellarCN/scp_zh@master/fonts/SimHei.ttf"
                    "https://gh-proxy.com/https://raw.githubusercontent.com/StellarCN/scp_zh/master/fonts/SimHei.ttf"
                    "https://raw.githubusercontent.com/StellarCN/scp_zh/master/fonts/SimHei.ttf"
                )
                local font_ok=false
                for furl in "${font_urls[@]}"; do
                    curl -fL --connect-timeout 15 --max-time 300 \
                        -o "$PREFIX/share/fonts/SimHei.ttf" "$furl" 2>/dev/null || continue
                    if [ "$(head -c 4 "$PREFIX/share/fonts/SimHei.ttf" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "00010000" ]; then
                        font_ok=true && break
                    fi
                done
                if $font_ok && fc-cache -f >/dev/null 2>&1; then
                    success "中文字体 SimHei 安装完成"
                else
                    rm -f "$PREFIX/share/fonts/SimHei.ttf"
                    warn "中文字体下载失败，渲染图片中文可能乱码，可稍后重试本项"
                fi
            fi
            # node-gyp 在 Android 上编译原生模块(sqlite3/better-sqlite3 等)会因缺
            # android_ndk_path 变量报 gyp configure error（termux-packages#19522/#20717
            # 官方确认的变通），写入 gyp 全局配置后所有后续编译永久生效
            if [ ! -f "$HOME/.gyp/include.gypi" ]; then
                mkdir -p "$HOME/.gyp"
                echo "{'variables': {'android_ndk_path': ''}}" > "$HOME/.gyp/include.gypi"
                success "已写入 gyp 全局配置，原生模块（sqlite3 等）可正常编译"
            fi
            # Termux 的 python 已是 3.12+（distutils 被移除），而旧版 node-gyp(v9.x)
            # 编译期仍 import distutils，缺失即报 ModuleNotFoundError；
            # setuptools 提供兼容层，装上后 node-gyp 可正常 configure
            if command -v python &>/dev/null && ! python -c "import distutils" 2>/dev/null; then
                log "Python 无 distutils（3.12+ 已移除），安装 setuptools 兼容层..."
                if ! command -v pip &>/dev/null; then
                    pkg install -y python-pip 2>&1 | tee -a "$LOG_FILE" || true
                fi
                pip install --upgrade setuptools 2>&1 | tee -a "$LOG_FILE" || \
                    warn "setuptools 安装失败，sqlite3 编译可能仍报 distutils 错误"
            fi
            # 启动 Redis
            redis-server --daemonize yes 2>/dev/null || true
            ;;

        "Linux")
            log "Linux 环境安装..."
            # 检测发行版
            local distro=""
            if [ -f /etc/os-release ]; then
                distro=$(grep -i "^id=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
            fi
            # 安装 Node.js（非 apt 系需要手动装；apt 系优先 nodesource 源，
            # 不可达时用 npmmirror 二进制直装兜底）
            if ! command -v node &>/dev/null; then
                if command -v apt &>/dev/null; then
                    log "添加 Node.js 20.x 源..."
                    curl -fsSL --connect-timeout 10 --max-time 30 https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - 2>/dev/null || true
                fi
                if ! command -v node &>/dev/null; then
                    local node_arch=""
                    case "$(uname -m)" in
                        x86_64) node_arch="x64" ;;
                        aarch64|arm64) node_arch="arm64" ;;
                    esac
                    if [ -n "$node_arch" ]; then
                        log "nodesource 不可用，从 npmmirror 直装 Node.js 20.x..."
                        curl -fsSL --connect-timeout 10 --max-time 120 \
                            "https://registry.npmmirror.com/-/binary/node/v20.19.1/node-v20.19.1-linux-${node_arch}.tar.xz" \
                            -o /tmp/node.tar.xz 2>/dev/null \
                        && mkdir -p /usr/local/lib/nodejs \
                        && tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs \
                        && ln -sf "/usr/local/lib/nodejs/node-v20.19.1-linux-${node_arch}/bin/node" /usr/local/bin/node \
                        && ln -sf "/usr/local/lib/nodejs/node-v20.19.1-linux-${node_arch}/bin/npm" /usr/local/bin/npm \
                        && ln -sf "/usr/local/lib/nodejs/node-v20.19.1-linux-${node_arch}/bin/npx" /usr/local/bin/npx \
                        && rm -f /tmp/node.tar.xz
                    fi
                fi
            fi
            # 按包管理器设置安装命令和包名
            local pm_install=""
            local pkgs=()
            if command -v apt &>/dev/null; then
                export DEBIAN_FRONTEND=noninteractive
                pm_install="apt-get install -y"
                # Debian 包名是 chromium，Ubuntu 是 chromium-browser
                local chromium_pkg="chromium-browser"
                local fonts_pkg="fonts-wqy-microhei fonts-wqy-zenhei"
                case "$distro" in
                    debian) chromium_pkg="chromium" ;;
                    ubuntu|mint|pop) chromium_pkg="chromium-browser" ;;
                esac
                pkgs=(nodejs git redis-server "$chromium_pkg" $fonts_pkg ffmpeg python3 python3-pip)
            elif command -v dnf &>/dev/null; then
                pm_install="dnf install -y"
                case "$distro" in
                    fedora) pkgs=(nodejs git redis chromium ffmpeg python3 python3-pip) ;;
                    rhel|centos|rocky|alma) pkgs=(nodejs git redis chromium ffmpeg python3 python3-pip) ;;
                esac
            elif command -v yum &>/dev/null; then
                pm_install="yum install -y"
                pkgs=(nodejs git redis chromium ffmpeg python3)
            elif command -v pacman &>/dev/null; then
                pm_install="pacman -S --noconfirm"
                pkgs=(nodejs git redis chromium wqy-microhei ffmpeg python python-pip)
            elif command -v zypper &>/dev/null; then
                pm_install="zypper install -y"
                pkgs=(nodejs git redis chromium ffmpeg python3 python3-pip)
            elif command -v apk &>/dev/null; then
                pm_install="apk add"
                pkgs=(nodejs git redis chromium ffmpeg python3 py3-pip)
            else
                error "不支持的 Linux 包管理器"
            fi
            for pkg in "${pkgs[@]}"; do
                for i in 1 2 3; do
                    $pm_install "$pkg" && break
                    log "安装 $pkg 失败，重试 ($i/3)..."
                    sleep 2
                done
            done
            # 验证关键组件是否安装成功
            command -v node &>/dev/null || error "Node.js 安装失败，请检查 apt 源和网络"
            command -v git &>/dev/null || error "Git 安装失败"
            # 启动 Redis
            systemctl start redis-server 2>/dev/null || service redis-server start 2>/dev/null || redis-server --daemonize yes 2>/dev/null || true
            ;;

        "macOS")
            log "macOS 环境安装..."
            if ! command -v brew &>/dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            for pkg in node redis chromium ffmpeg python3; do
                for i in 1 2 3; do
                    brew install "$pkg" 2>/dev/null && break
                    log "安装 $pkg 失败，重试 ($i/3)..."
                    sleep 2
                done
            done
            # 验证关键组件是否安装成功
            command -v node &>/dev/null || error "Node.js 安装失败，请检查 Homebrew 安装"
            command -v git &>/dev/null || error "Git 安装失败"
            brew services start redis 2>/dev/null || true
            ;;

        "Windows")
            log "Windows 环境安装..."
            # Node.js（验证安装）
            if ! command -v node &>/dev/null; then
                log "安装 Node.js..."
                curl -fsSL --connect-timeout 10 --max-time 120 -o /tmp/node-installer.msi "https://nodejs.org/dist/v20.19.1/node-v20.19.1-x64.msi" 2>/dev/null
                if [ -f /tmp/node-installer.msi ] && [ "$(head -c 2 /tmp/node-installer.msi 2>/dev/null)" = "$(printf '\xd0\xcf')" ]; then
                    powershell -Command "Start-Process msiexec -ArgumentList '/i \"$(cygpath -w /tmp/node-installer.msi)\" /quiet /norestart' -Wait -NoNewWindow" 2>/dev/null || true
                    rm -f /tmp/node-installer.msi
                    sleep 5
                fi
                export PATH="$PATH:/c/Program Files/nodejs"
                command -v node &>/dev/null || error "Node.js 安装失败"
            fi
            success "Node.js $(node --version) 已就绪"
            # npm
            command -v npm &>/dev/null || error "npm 未安装"
            success "npm $(npm --version) 已就绪"
            # git
            command -v git &>/dev/null || error "Git 安装失败"
            # Redis（验证安装，winget 优先）
            local redis_ok=false
            for i in 1 2 3; do
                # 尝试连接已有 Redis
                redis-cli ping 2>/dev/null && redis_ok=true && break
                # 找到 redis-server 就启动
                local redis_exe=""
                for p in "/c/Program Files/Redis/redis-server.exe" "$PROGRAMFILES/Redis/redis-server.exe"; do
                    [ -f "$p" ] && redis_exe="$p" && break
                done
                command -v redis-server &>/dev/null && redis_exe="redis-server"
                if [ -n "$redis_exe" ]; then
                    "$redis_exe" --daemonize yes 2>/dev/null || true
                    sleep 2
                    # 添加 PATH
                    export PATH="$PATH:$(dirname "$redis_exe")"
                    redis-cli ping 2>/dev/null && redis_ok=true && break
                fi
                log "安装 Redis (尝试 $i/3)..."
                # winget 安装
                if command -v winget &>/dev/null; then
                    winget install -e --id Redis.Redis --accept-source-agreements 2>/dev/null || true
                    sleep 5
                    # 安装后查找 redis-server
                    for p in "/c/Program Files/Redis/redis-server.exe" "$PROGRAMFILES/Redis/redis-server.exe"; do
                        [ -f "$p" ] && redis_exe="$p" && break
                    done
                    if [ -n "$redis_exe" ]; then
                        export PATH="$PATH:$(dirname "$redis_exe")"
                        "$redis_exe" --daemonize yes 2>/dev/null || true
                        sleep 2
                        redis-cli ping 2>/dev/null && redis_ok=true && break
                    fi
                fi
                # zip 下载解压安装（redis-windows 项目现以 zip 分发，无 MSI）
                local redis_urls=(
                    "https://github.com/redis-windows/redis-windows/releases/latest/download/Redis-8.10.2-Windows-x64-cygwin.zip"
                )
                local downloaded=""
                for url in "${redis_urls[@]}"; do
                    curl -fsSL --connect-timeout 10 --max-time 180 -o /tmp/redis.zip "$url" 2>/dev/null && downloaded="/tmp/redis.zip" && break
                done
                if [ -n "$downloaded" ] && [ -f "$downloaded" ]; then
                    # 校验 zip 魔数（PK），防 404 页面/HTML 被当包解压
                    if [ "$(head -c 2 "$downloaded" 2>/dev/null)" = "PK" ]; then
                        mkdir -p "/c/Program Files/Redis"
                        powershell -Command "Expand-Archive -Force -Path '$(cygpath -w "$downloaded")' -DestinationPath 'C:\Program Files\Redis'" 2>/dev/null || true
                    else
                        warn "下载的 Redis 包无效（非 zip），跳过"
                    fi
                    rm -f "$downloaded"
                    sleep 2
                    # zip 可能带一层顶层目录，find 逐行读取定位（路径含空格安全）
                    while IFS= read -r p; do
                        [ -f "$p" ] && redis_exe="$p" && break
                    done <<EOF
$(ls "/c/Program Files/Redis/redis-server.exe" 2>/dev/null; find "/c/Program Files/Redis" -mindepth 2 -maxdepth 2 -name redis-server.exe 2>/dev/null)
EOF
                    if [ -n "$redis_exe" ]; then
                        export PATH="$PATH:$(dirname "$redis_exe")"
                        "$redis_exe" --daemonize yes 2>/dev/null || true
                        sleep 2
                        redis-cli ping 2>/dev/null && redis_ok=true && break
                    fi
                fi
                sleep 3
            done
            $redis_ok && success "Redis 已就绪" || warn "Redis 未就绪，请手动启动后重试"
            # Chromium（通过 puppeteer）
            if ! command -v chromium &>/dev/null; then
                log "安装 Chromium..."
                npx puppeteer browsers install chrome 2>/dev/null || warn "Chromium 安装失败"
            fi
            # 刷新 PATH
            export PATH="$PATH:/c/Program Files/nodejs:$LOCALAPPDATA/Programs/Redis"
            ;;

        *)
            error "不支持的平台: $CURRENT_PLATFORM"
            ;;
    esac

    success "环境配置完成"
}

# ---------- 4. 安装云崽 ----------
install_yunzai() {
    local repo_url="$1"
    local version_name="$2"

    echo -e "\n${CYAN}========== 开始安装 $version_name ==========${NC}"

    # 4.1 获取权限
    get_permissions

    # 4.2 检测平台
    detect_platform

    # 4.3 安装环境依赖
    install_environment

    # 4.4 创建总目录（优先复用已有安装位置，兼容旧版以 $PWD 锚定的历史安装）
    local existing_base
    if existing_base=$(find_yunzai_base 2>/dev/null); then
        YUNZAI_DIR="$existing_base"
        log "检测到已有安装目录: $YUNZAI_DIR"
    fi
    mkdir -p "$YUNZAI_DIR" || error "创建目录 $YUNZAI_DIR 失败"

    # 4.5 克隆代码（含重试+镜像）
    local repo_name=$(basename "$repo_url" .git)
    if [ -d "$YUNZAI_DIR/$repo_name" ] && [ -f "$YUNZAI_DIR/$repo_name/package.json" ]; then
        log "云崽代码已存在，跳过克隆"
        YUNZAI_DIR="$YUNZAI_DIR/$repo_name"
    else
        log "克隆 $version_name 代码..."
        local clone_urls=("$repo_url")
        if echo "$repo_url" | grep -q "gitee.com"; then
            local rp=$(echo "$repo_url" | sed 's|https://gitee.com/||' | sed 's|\.git$||')
            if echo "$rp" | grep -q "huifeidemangguomao/MangoCat-Yunzai"; then
                clone_urls+=("https://github.com/FlyingMangoCat/MangoCat-Yunzai.git" "https://gh-proxy.com/https://github.com/FlyingMangoCat/MangoCat-Yunzai.git")
            fi
            if echo "$rp" | grep -q "yoimiya-kokomi/Miao-Yunzai"; then
                clone_urls+=("https://github.com/yoimiya-kokomi/Miao-Yunzai.git" "https://gh-proxy.com/https://github.com/yoimiya-kokomi/Miao-Yunzai.git")
            fi
            clone_urls+=("https://gitee.com/$rp.git")
        fi
        if echo "$repo_url" | grep -q "github.com"; then
            local rp=$(echo "$repo_url" | sed 's|https://github.com/||')
            clone_urls+=("https://gh-proxy.com/https://github.com/$rp")
        fi
        local ok=false
        local repo_name=$(basename "$repo_url" .git)
        for url in "${clone_urls[@]}"; do
            for i in 1 2 3; do
                git clone --depth=1 "$url" "$YUNZAI_DIR/$repo_name" 2>/dev/null && \
                [ -f "$YUNZAI_DIR/$repo_name/package.json" ] && ok=true && break 2
                log "克隆失败，重试 ($i/3)..."
                sleep 2
            done
        done
        $ok || error "代码克隆失败，请检查网络"
        # 更新 YUNZAI_DIR 为云崽根目录
        YUNZAI_DIR="$YUNZAI_DIR/$repo_name"
        success "代码克隆完成"
    fi

    # 4.6 全局安装 pnpm（兼容 Node.js 版本）
    log "安装 pnpm..."
    # 国内网络优先使用 npmmirror 镜像源，避免官方源超时
    if npm config get registry 2>/dev/null | grep -q "registry.npmjs.org"; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null || true
        log "已切换 npm 源为 npmmirror 镜像"
    fi
    local node_ver=$(node -v | sed 's/v//' | cut -d. -f1)
    # Termux/Android 文件系统不支持新版 pnpm 的 lock_shared()，必须用 pnpm@8；
    # 已装了新版 pnpm 的也要降级（不能只在未安装时固定）
    if [ "$IS_TERMUX" = "true" ] && command -v pnpm &>/dev/null; then
        local pnpm_major=$(pnpm --version 2>/dev/null | cut -d. -f1)
        if [ -n "$pnpm_major" ] && [ "$pnpm_major" -gt 8 ]; then
            log "检测到 pnpm v$pnpm_major（Termux 不支持 lock_shared），降级为 pnpm@8..."
            npm install -g pnpm@8 2>&1 | tee -a "$LOG_FILE" || warn "pnpm 降级失败，将继续尝试现有版本"
        fi
    fi
    if ! command -v pnpm &>/dev/null; then
        local pnpm_ver="pnpm@10"
        [ "$node_ver" -ge 22 ] && pnpm_ver="pnpm"
        if [ "$IS_TERMUX" = "true" ]; then
            pnpm_ver="pnpm@8"
            log "检测到 Termux 环境，使用 pnpm@8"
        fi
        local ok=false
        for i in 1 2 3; do
            npm install -g "$pnpm_ver" && ok=true && break
            log "pnpm 安装失败，重试 ($i/3)..."
            sleep 2
        done
        $ok || error "pnpm 安装失败，请检查网络或 npm 源（npm 报错见上方输出）"
    fi
    command -v pnpm &>/dev/null || error "pnpm 未安装成功，请检查 npm 全局 bin 目录"

    # 4.7 安装依赖
    cd "$YUNZAI_DIR"
    log "安装依赖..."
    rm -f package-lock.json
    # Termux 预防性配置: sqlite3 自带的 sqlite3.c 以 C++ 编译时报
    # invalid conversion 'int' to 'sqlite3_destructor_type'（SQLITE_TRANSIENT 宏），
    # 提前装系统级 libsqlite 并让 node-gyp 链接系统库，从源头绕开（termux#20678）
    local sqlite_env=()
    if [ "$IS_TERMUX" = true ]; then
        if ! [ -f "$PREFIX/lib/libsqlite3.so" ]; then
            log "安装系统级 SQLite 库（编译 sqlite3 用）..."
            pkg install -y libsqlite 2>&1 | tee -a "$LOG_FILE" || true
        fi
        if [ -f "$PREFIX/lib/libsqlite3.so" ]; then
            sqlite_env=(SQLITE3_INCLUDE_DIR="$PREFIX/include" SQLITE3_LIB_DIR="$PREFIX/lib" npm_config_build_from_source=true)
        fi
    fi
    # node-addon-api 4.x 的 napi.h 有 clang 21 不接受的类内静态初始化
    # (unknown_array_type = static_cast<napi_typedarray_type>(-1), 枚举值越界),
    # 上游 8.x 已移除该写法; Node-API ABI 稳定, 头文件可安全升级,
    # 用 pnpm overrides 强制全树使用新版(真机日志实锤 napi.h:1147 报错)
    if [ "$IS_TERMUX" = true ] && command -v node &>/dev/null; then
        node -e "
const fs = require('fs');
const p = JSON.parse(fs.readFileSync('package.json', 'utf8'));
p.pnpm = p.pnpm || {};
p.pnpm.overrides = Object.assign({}, p.pnpm.overrides, {'node-addon-api': '^8.9.2'});
fs.writeFileSync('package.json', JSON.stringify(p, null, 2));
console.log('已注入 pnpm.overrides: node-addon-api ^8.9.2');
" 2>&1 | tee -a "$LOG_FILE"
    fi
    local ok=false
    for i in 1 2 3; do
        env "${sqlite_env[@]}" pnpm install 2>&1 || env "${sqlite_env[@]}" pnpm install --ignore-scripts 2>&1 || true
        if [ -d "node_modules" ]; then
            ok=true && break
        fi
        log "依赖安装失败，重试 ($i/3)..."
        sleep 3
    done
    $ok || error "依赖安装失败，请检查网络连接"
    # sqlite3 源码补丁: 5.1.6 的 statement.cc 两处 SQLITE_TRANSIENT 在 clang 21 下
    # 报 invalid conversion 'int' to 'sqlite3_destructor_type'，调用点显式强转修复；
    # 必须在 install 之后打（源码 install 时才解包），打完重编译
    if [ "$IS_TERMUX" = true ]; then
        patch_sqlite_sources "$YUNZAI_DIR"
        if ! node -e "require('sqlite3')" >/dev/null 2>&1; then
            log "重编译 sqlite3（打补丁后）..."
            env "${sqlite_env[@]}" pnpm rebuild sqlite3 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi
    success "依赖安装完成"

    # 4.8 安装插件
    log "安装插件..."
    install_plugin "miao-plugin" "https://github.com/yoimiya-kokomi/miao-plugin.git" \
        "https://gitcode.com/TimeRainStarSky/miao-plugin.git" \
        "https://gitee.com/huifeidemangguomao/miao-plugin.git"
    install_plugin "xiaoyao-cvs-plugin" "https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git" \
        "https://gitcode.com/TimeRainStarSky/xiaoyao-cvs-plugin.git"
    install_plugin "liulian-plugin" "https://github.com/FlyingMangoCat/liulian-plugin.git" \
        "https://gitee.com/huifeidemangguomao/liulian-plugin.git"

    # 4.9 安装插件依赖
    log "安装插件依赖..."
    env "${sqlite_env[@]}" pnpm install 2>/dev/null || env "${sqlite_env[@]}" pnpm install --ignore-scripts 2>/dev/null || true
    if [ -d "node_modules" ]; then
        success "插件依赖安装完成"
    else
        error "插件依赖安装失败"
    fi

    cd ..

    # 4.10 启动云崽
    echo -e "${GREEN}$version_name 安装完成！${NC}"
    echo -e "${YELLOW}启动方式: cd $YUNZAI_DIR && node app${NC}"
    echo -e "${YELLOW}首次启动请配置主人QQ等参数${NC}"
}

# ---------- 插件安装函数 ----------
install_plugin() {
    local name="$1"; shift
    local urls=("$@")
    if [ -d "$YUNZAI_DIR/plugins/$name" ]; then
        log "  - $name 已存在，跳过"
        return
    fi
    for url in "${urls[@]}"; do
        for i in 1 2 3; do
            git clone --depth=1 "$url" "$YUNZAI_DIR/plugins/$name" 2>/dev/null && \
            [ -d "$YUNZAI_DIR/plugins/$name" ] && log "  - $name 安装完成" && return
            log "  - $name 安装失败，重试 ($i/3)..."
            sleep 2
        done
    done
    warn "  - $name 安装失败，已尝试所有镜像源"
}

# ---------- 选项 1: 芒果猫版云崽 ----------
install_mangocat() {
    log "用户选择: 安装芒果猫版云崽"
    install_yunzai \
        "https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git" \
        "芒果猫版云崽"
}

# ---------- 选项 2: 喵版云崽 ----------
install_miao() {
    log "用户选择: 安装喵版云崽"
    install_yunzai \
        "https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git" \
        "喵版云崽"
}

# ---------- 定位云崽总目录 ----------
# 依次探测: 脚本所在目录 / 家目录 / 当前目录（兼容旧版以 $PWD 锚定的历史安装位置）
# 优先返回已含云崽代码(package.json)的总目录，其次返回存在的空目录
find_yunzai_base() {
    local base d
    for base in "$SCRIPT_DIR/yunzai-one-button-fmc" "$HOME/yunzai-one-button-fmc" "$PWD/yunzai-one-button-fmc"; do
        [ -d "$base" ] || continue
        if [ -f "$base/package.json" ]; then echo "$base"; return 0; fi
        for d in "$base"/*/; do
            if [ -f "${d}package.json" ]; then echo "$base"; return 0; fi
        done
    done
    for base in "$SCRIPT_DIR/yunzai-one-button-fmc" "$HOME/yunzai-one-button-fmc" "$PWD/yunzai-one-button-fmc"; do
        [ -d "$base" ] && { echo "$base"; return 0; }
    done
    return 1
}

# ---------- 查找云崽根目录 ----------
# 总目录本身或其一级子目录中含 package.json 的那个（安装后代码在仓库子目录里，
# 重启脚本后不能只查总目录，否则误报"未安装"）
find_yunzai_root() {
    local base
    base=$(find_yunzai_base) || return 1
    if [ -f "$base/package.json" ]; then
        echo "$base"
        return 0
    fi
    local d
    for d in "$base"/*/; do
        if [ -f "${d}package.json" ]; then
            echo "${d%/}"
            return 0
        fi
    done
    return 1
}

# ---------- 选项 3: 启动云崽 ----------
start_yunzai() {
    log "用户选择: 启动云崽"
    local target
    target=$(find_yunzai_root) || {
        echo -e "${RED}未检测到已安装的云崽（$YUNZAI_DIR 下无 package.json），请先安装${NC}"
        return
    }
    # Redis 未运行时先拉起（重启脚本/手机后 Redis 不会自动恢复，Termux 无 systemd）
    if ! redis-cli ping 2>/dev/null | grep -q PONG; then
        log "Redis 未运行，启动 Redis..."
        redis-server --daemonize yes 2>/dev/null || true
        sleep 1
        redis-cli ping 2>/dev/null | grep -q PONG && success "Redis 已启动" || warn "Redis 启动失败，云崽可能无法连接数据库"
    fi
    # sqlite3 自检: 编译产物缺失/失效时自动重编译（此前 Termux 缺编译工具链导致编译失败，
    # 或 Node 升级后 ABI 变化使旧产物失效，运行期才报 Please install sqlite3 package manually）
    if [ -d "$target/node_modules" ] && ! (cd "$target" && node -e "require('sqlite3')" >/dev/null 2>&1); then
        log "检测到 sqlite3 模块不可用，自动重编译..."
        if command -v pnpm &>/dev/null; then
            # 先补丁源码再编译（clang 21 下 SQLITE_TRANSIENT 报类型转换错误）
            patch_sqlite_sources "$target"
            # 第一级: 常规 rebuild（NDK 路径已由 ~/.gyp/include.gypi 兜底）
            (cd "$target" && pnpm rebuild sqlite3) 2>&1 | tee -a "$LOG_FILE"
            # 第二级: 若仍失败（报 invalid conversion 'int' to 'sqlite3_destructor_type'
            # 等 C++ 编译错误），改链 Termux 系统级 libsqlite 编译，完全绕开
            # 自带 sqlite3.c 源码（termux-packages#20678 官方确认方案）
            if ! (cd "$target" && node -e "require('sqlite3')" >/dev/null 2>&1) && [ "$IS_TERMUX" = true ]; then
                log "常规编译失败，改用系统级 SQLite 库编译..."
                pkg install -y libsqlite 2>&1 | tee -a "$LOG_FILE" || true
                (cd "$target" && \
                    SQLITE3_INCLUDE_DIR="$PREFIX/include" \
                    SQLITE3_LIB_DIR="$PREFIX/lib" \
                    npm_config_build_from_source=true \
                    pnpm rebuild sqlite3) 2>&1 | tee -a "$LOG_FILE"
            fi
            if (cd "$target" && node -e "require('sqlite3')" >/dev/null 2>&1); then
                success "sqlite3 重编译成功"
            else
                warn "sqlite3 仍不可用，请把上方 gyp/编译报错完整反馈给脚本维护者"
            fi
        else
            warn "未检测到 pnpm，无法自动重编译 sqlite3，请先通过菜单 1/2 安装依赖"
        fi
    fi
    # 联动拉起 NapCat（未安装/未配置仅提示，不阻断云崽启动）
    start_napcat_and_show_token auto || true
    # Termux: puppeteer 无 android/arm64 预编译浏览器(Cannot download a binary for
    # the provided platform), 用系统 chromium 替代; puppeteer 24+ 原生读此变量
    if [ "$IS_TERMUX" = true ]; then
        local chromium_bin="/data/data/com.termux/files/usr/bin/chromium-browser"
        # 没有就自动补装（Termux chromium 在 x11 仓库；二进制名是 chromium-browser）
        if [ ! -x "$chromium_bin" ]; then
            log "未找到系统 chromium，自动安装（x11 仓库）..."
            pkg install -y x11-repo 2>&1 | tee -a "$LOG_FILE" || true
            local x11src="$PREFIX/etc/apt/sources.list.d/x11.list"
            if [ -f "$x11src" ] && ! grep -q mirrors.bfsu.edu.cn "$x11src"; then
                cp "$x11src" "$x11src.bak.yzb" 2>/dev/null || true
                echo "deb https://mirrors.bfsu.edu.cn/termux/apt/termux-x11 x11 main" > "$x11src"
            fi
            pkg update -y 2>&1 | tee -a "$LOG_FILE" || true
            pkg install -y chromium 2>&1 | tee -a "$LOG_FILE" || true
        fi
        if [ -x "$chromium_bin" ]; then
            export PUPPETEER_EXECUTABLE_PATH="$chromium_bin"
            success "图片渲染使用系统 chromium"
        else
            warn "chromium 自动安装失败，图片渲染不可用；手动执行: pkg install x11-repo && pkg update && pkg install chromium"
        fi
    fi
    echo -e "${GREEN}启动云崽...${NC}"
    cd "$target" && node app
}

# ---------- 查看 NapCat WebUI token ----------
show_napcat_token() {
    log "用户选择: 查看 NapCat token"
    detect_platform

    # 收集各平台常见 webui.json 位置（NapCat 首次启动后才会生成）
    local candidates=()
    case "$CURRENT_PLATFORM" in
        "Termux")
            # 官方 Termux 脚本装在 proot-distro 容器（别名 napcat）内
            # 新版布局 containers/<名>/rootfs/...，旧版 installed-rootfs/<名>/...
            local nc_root="$PREFIX/var/lib/proot-distro"
            local nc_rel="root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/webui.json"
            candidates=("$nc_root/containers/napcat/rootfs/$nc_rel" "$nc_root/installed-rootfs/napcat/$nc_rel")
            ;;
        "Linux")
            # 官方 Shell 直装默认在 /opt/QQ 下
            candidates=("/opt/QQ/resources/app/app_launcher/napcat/config/webui.json")
            ;;
        *)
            candidates=()
            ;;
    esac

    local found=""
    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then found="$f"; break; fi
    done

    # 没有在固定位置找到时，兜底搜索（限深度，避免卡顿）
    if [ -z "$found" ]; then
        log "固定位置未找到 webui.json，尝试搜索（可能较慢）..."
        case "$CURRENT_PLATFORM" in
            "Termux") found=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 12 -name webui.json -path "*napcat*" 2>/dev/null | head -n 1) ;;
            "Linux")  found=$(find /opt "$HOME" -maxdepth 8 -path "*napcat*/config/webui.json" 2>/dev/null | head -n 1) ;;
        esac
    fi

    if [ -z "$found" ]; then
        warn "未找到 NapCat 配置文件（config/webui.json）"
        echo -e "${YELLOW}可能原因: NapCat 还没启动过（token 首次启动才生成），或安装在非常规目录${NC}"
        echo -e "${YELLOW}请先启动一次 NapCat，再重新选择本项；或手动查看启动日志中的 WebUI token${NC}"
        return 1
    fi

    log "找到配置文件: $found"
    local token=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$found" | head -n 1 | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [ -z "$token" ]; then
        warn "配置文件里没读到 token，请直接打开查看: $found"
        return 1
    fi
    success "NapCat WebUI token: $token"
    echo -e "${GREEN}登录 WebUI 时输入上面的 token 即可${NC}"
}

# ---------- 启动 NapCat（后台）并抓取 token ----------
# 模式: 空=安装流程(询问+显示token) direct=菜单(不询问+显示token)
#       auto=启动云崽联动(不询问不显示token; 未安装仅提示不阻断)
start_napcat_and_show_token() {
    local mode="$1"
    if [ "$mode" != "direct" ] && [ "$mode" != "auto" ]; then
        echo -e "${YELLOW}是否现在启动 NapCat? 启动后才能生成 WebUI token${NC}"
        read -p "立即启动 NapCat? (y/回车): " start_now
        [ "$start_now" != "y" ] && return 0
    fi

    detect_platform
    case "$CURRENT_PLATFORM" in
        "Termux")
            # 官方 Termux 方式: proot-distro 容器 + screen 后台（与官方脚本输出一致）
            if ! command -v proot-distro &>/dev/null || ! command -v screen &>/dev/null; then
                if [ "$mode" = "auto" ]; then
                    warn "未安装 proot-distro/screen，跳过自动拉起 NapCat（菜单 5 可安装）"
                else
                    warn "未找到 proot-distro/screen，请按安装脚本输出的说明手动启动"
                fi
                return 1
            fi
            # 定位容器 root 家目录（rootfs 里真有 /bin/sh 才算装好）
            local pd_root="$PREFIX/var/lib/proot-distro"
            local container_root=""
            if [ -e "$pd_root/containers/napcat/rootfs/bin/sh" ]; then
                container_root="$pd_root/containers/napcat/rootfs/root"
            elif [ -e "$pd_root/installed-rootfs/napcat/bin/sh" ]; then
                container_root="$pd_root/installed-rootfs/napcat/root"
            fi
            if [ -z "$container_root" ]; then
                if [ "$mode" = "auto" ]; then
                    warn "未检测到已安装的 NapCat，跳过自动拉起（菜单 5 可安装）"
                else
                    warn "未检测到已安装的 NapCat 容器，请先通过菜单 5 安装"
                fi
                return 1
            fi
            # 已有同名后台会话则不再重复启动
            if screen -ls 2>/dev/null | grep -q "\.napcat"; then
                log "NapCat 已在后台运行（screen 会话 napcat）"
                [ "$mode" != "auto" ] && echo -e "查看输出: ${GREEN}screen -r napcat${NC}，离开按 ${GREEN}Ctrl+A 再按 D${NC}"
                return 0
            fi
            # 登录会话保存在容器内，重启 NapCat 会自动快速登录，无需额外参数
            log "后台启动 NapCat（screen 会话 napcat）..."
            screen -dmS napcat bash -c "proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"" || {
                warn "启动失败，请手动执行:"
                echo -e "${GREEN}screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"'${NC}"
                return 1
            }
            echo -e "${GREEN}已在 screen 后台会话 napcat 中启动${NC}"
            echo -e "查看启动输出: ${GREEN}screen -r napcat${NC}，离开按 ${GREEN}Ctrl+A 再按 D${NC}"
            ;;
        "Linux")
            if ! command -v napcat &>/dev/null && ! command -v qq &>/dev/null; then
                if [ "$mode" = "auto" ]; then
                    warn "未安装 NapCat，跳过自动拉起（菜单 5 可安装）"
                else
                    warn "未找到 napcat/qq 启动命令，请按安装输出的说明手动启动，启动后再选菜单 6 查看 token"
                fi
                return 1
            fi
            if command -v napcat &>/dev/null; then
                log "后台启动 NapCat..."
                nohup napcat >/dev/null 2>&1 &
            else
                log "后台启动 NapCat（qq --no-sandbox）..."
                nohup qq --no-sandbox >/dev/null 2>&1 &
            fi
            ;;
        *)
            warn "当前平台请按对应安装说明手动启动，启动后再选菜单 6 查看 token"
            return 1
            ;;
    esac

    if [ "$mode" = "auto" ]; then
        log "NapCat 已联动拉起"
        return 0
    fi
    log "等待 NapCat 首次初始化（生成 token）..."
    sleep 8
    show_napcat_token
}

# ---------- NapCat 反向 WS 配置提示 ----------
show_napcat_ws_guide() {
    echo -e "\n${CYAN}========== NapCat 反向 WS 配置（连接云崽） ==========${NC}"
    echo -e "1. 启动 NapCat 后，会输出 WebUI 地址（如 http://localhost:6099/webui），浏览器打开"
    echo -e "2. 首次进入需要登录 token，两种方式获取："
    echo -e "   a. 启动日志里会打印 ${GREEN}WebUI token: xxxx${NC}，注意看启动输出"
    echo -e "   b. 找不到日志就打开 NapCat 安装目录下 ${GREEN}config/webui.json${NC}，${GREEN}token${NC} 字段即登录密码"
    echo -e "3. 进入 ${GREEN}网络配置${NC} → 新建 → 选 ${GREEN}WebSocket 客户端（反向 WS）${NC}"
    echo -e "4. URL 填: ${GREEN}ws://127.0.0.1:8080${NC}（云崽默认端口，以云崽实际配置为准）"
    echo -e "5. 保存并启用后，云崽端确认已开启 OneBot 适配（首次启动云崽按提示配置）"
    echo -e "6. 云崽端收到 \"OneBot 接入成功\" 之类的日志即表示连接成功"
    echo -e "${CYAN}====================================================${NC}\n"
}

# ---------- 安装 NapCat ----------
NAPCAT_INSTALLER_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"

download_napcat_installer() {
    # 多源下载安装脚本，返回 0 表示成功，文件路径存入 NAPCAT_SH
    # 源顺序: 官方源 → jsDelivr 镜像 → GitHub raw 直连
    local base_name
    if [[ "$1" == *install.termux.sh ]]; then
        base_name="install.termux.sh"
    else
        base_name="install.sh"
    fi
    local urls=(
        "$1"
        "https://cdn.jsdelivr.net/gh/NapNeko/NapCat-Installer@main/script/$base_name"
        "https://raw.githubusercontent.com/NapNeko/NapCat-Installer/main/script/$base_name"
    )
    NAPCAT_SH=".napcat_install_$$"
    for url in "${urls[@]}"; do
        for i in 1 2 3; do
            curl -fsSL --connect-timeout 15 --max-time 120 -o "$NAPCAT_SH" "$url" && [ -s "$NAPCAT_SH" ] && return 0
            log "下载 NapCat 安装脚本失败（$url），重试 ($i/3)..."
            sleep 2
        done
    done
    return 1
}

patch_napcat_script() {
    # 官方脚本内部会再从 nclatest.znin.net 拉取文件，该源部分网络无法直连；
    # 下载后本地把内部源替换为 jsDelivr 镜像再执行，作为兜底
    if sed -i 's|https://nclatest.znin.net/NapNeko/NapCat-Installer/main/|https://cdn.jsdelivr.net/gh/NapNeko/NapCat-Installer@main/|g' "$NAPCAT_SH" 2>/dev/null; then
        log "已将安装脚本内部下载源替换为 jsDelivr 镜像"
    else
        warn "替换内部下载源失败，仍按脚本原样执行"
    fi
}

# ---------- 预下载 QQ 安装包 ----------
# NapCat 官方安装脚本内置的 qqdl.gtimg.cn QQ 下载链接已被腾讯下架(404,
# 下载到的是 XML 错误页, 解压报 not a Debian format archive), 官方仓库
# issue #97 未修复。改为从第三方存档仓库预下载可用安装包放到官方脚本
# 的工作目录; 官方脚本检测到本地 QQ.deb/QQ.rpm 存在时会跳过下载直接解压。
prepare_qq_package() {
    local dest_dir="$1"   # 官方脚本运行时的工作目录
    local pkg_type="$2"   # deb 或 rpm

    # 架构映射: aarch64→arm64(deb)/aarch64(rpm), x86_64→amd64(deb)/x86_64(rpm)
    local qq_arch
    case "$(uname -m)" in
        x86_64)  qq_arch=$([ "$pkg_type" = "deb" ] && echo amd64 || echo x86_64) ;;
        aarch64) qq_arch=$([ "$pkg_type" = "deb" ] && echo arm64 || echo aarch64) ;;
        *) warn "架构 $(uname -m) 无可用 QQ 安装包，交由官方脚本自行处理"; return 1 ;;
    esac

    local file_name="QQ.deb"
    [ "$pkg_type" = "rpm" ] && file_name="QQ.rpm"
    local dest="$dest_dir/$file_name"

    # 校验函数: deb 包头为 !<arch>, rpm 包头为 ed ab ee db; 404 错误页会被拒绝
    verify_qq_file() {
        if [ "$pkg_type" = "deb" ]; then
            head -c 8 "$dest" 2>/dev/null | grep -q '!<arch>'
        else
            [ "$(head -c 4 "$dest" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "edabeedb" ]
        fi
    }

    # 已存在且合法则跳过
    if [ -f "$dest" ] && verify_qq_file; then
        log "检测到已预下载的 QQ 安装包，跳过下载"
        return 0
    fi
    rm -f "$dest"

    # 从存档仓库解析最新包地址
    local url
    url=$(curl -s --connect-timeout 10 --max-time 30 "https://api.github.com/repos/Rodert/qq-versions/releases/latest" \
        | grep -o "\"browser_download_url\": \"[^\"]*_01\.$pkg_type\"" \
        | cut -d'"' -f4 | grep "_${qq_arch}_" | head -n 1)
    if [ -z "$url" ]; then
        warn "未能从存档仓库解析出 QQ ${qq_arch} 包地址，交由官方脚本自行下载"
        return 1
    fi

    log "QQ 官方下载链接已失效，预下载可用安装包（约 200MB）..."
    local i
    for i in 1 2 3; do
        curl -fL -# --connect-timeout 15 --max-time 1800 -o "$dest" "$url" || true
        if [ -f "$dest" ] && verify_qq_file; then
            success "QQ 安装包预下载完成并校验通过"
            return 0
        fi
        log "QQ 安装包下载/校验失败，重试 ($i/3)..."
        rm -f "$dest"
        sleep 2
    done
    warn "QQ 安装包预下载失败，交由官方脚本自行下载（其内置链接当前已失效，失败请重试本项）"
    return 1
}

install_napcat() {
    log "用户选择: 安装 NapCat"
    detect_platform

    case "$CURRENT_PLATFORM" in
        "Termux")
            log "Termux 环境：按官方 Termux 方案安装（proot-distro debian 容器）..."
            # 以下步骤复刻官方 install.termux.sh，区别: 容器安装失败会自动重试
            # 1. 准备 proot-distro / screen（官方 CDN 慢时自动切国内镜像）
            if ! command -v proot-distro &>/dev/null || ! command -v screen &>/dev/null; then
                ensure_termux_mirror
                pkg update -y 2>&1 | tee -a "$LOG_FILE" || true
                pkg install -y proot-distro screen 2>&1 | tee -a "$LOG_FILE"
                if [ "${PIPESTATUS[0]}" -ne 0 ]; then
                    apt-get update -y 2>&1 | tee -a "$LOG_FILE"
                    apt-get install -y proot-distro screen 2>&1 | tee -a "$LOG_FILE"
                fi
            fi
            command -v proot-distro &>/dev/null || error "proot-distro 安装失败，请手动执行: pkg install proot-distro screen"
            command -v screen &>/dev/null || error "screen 安装失败，请手动执行: pkg install screen"

            # 2. 安装 debian 容器（镜像下载易受网络波动影响，失败自动清理重试）
            # 容器目录新版在 containers/<名>/rootfs，旧版在 installed-rootfs/<名>，两版都判
            local napcat_rootfs_new="$PREFIX/var/lib/proot-distro/containers/napcat"
            local napcat_rootfs_legacy="$PREFIX/var/lib/proot-distro/installed-rootfs/napcat"
            # rootfs 里真有 /bin/sh 才算装好: 安装中断留下的残缺目录必须清理重装
            local container_ready=false
            if [ -e "$napcat_rootfs_new/rootfs/bin/sh" ] || [ -e "$napcat_rootfs_legacy/bin/sh" ]; then
                container_ready=true
            elif [ -d "$napcat_rootfs_new" ] || [ -d "$napcat_rootfs_legacy" ]; then
                warn "检测到残缺的 napcat 容器目录（上次安装中断所致），清理后重装..."
                proot-distro remove napcat 2>/dev/null || true
                rm -rf "$napcat_rootfs_new" "$napcat_rootfs_legacy"
            fi
            if [ "$container_ready" != "true" ]; then
                local container_ok=false
                # 预检: 5 秒探测官方 Docker Hub, 不通则跳过官方源直接走国内镜像, 免去漫长等待
                local image_refs=("debian" "dockerproxy.net/library/debian")
                if ! curl -s --connect-timeout 5 --max-time 8 "https://registry-1.docker.io/v2/" -o /dev/null; then
                    log "官方 Docker Hub 连接失败（预检 5 秒超时），直接使用国内镜像源"
                    image_refs=("dockerproxy.net/library/debian")
                fi
                for ref in "${image_refs[@]}"; do
                    for i in 1 2 3; do
                        log "安装 napcat 容器（来源 $ref，尝试 $i/3）..."
                        proot-distro install "$ref" --override-alias napcat 2>&1 | tee -a "$LOG_FILE"
                        # 管道后 $? 是 tee 的退出码，必须用 PIPESTATUS 取 proot-distro 的真实结果
                        [ "${PIPESTATUS[0]}" -eq 0 ] && container_ok=true && break
                        log "容器安装失败，清理后重试..."
                        proot-distro remove napcat 2>/dev/null || true
                        rm -rf "$napcat_rootfs_new" "$napcat_rootfs_legacy" 2>/dev/null || true
                        sleep 3
                    done
                    $container_ok && break
                done
                $container_ok || error "napcat 容器安装失败（官方源+国内镜像源均已重试）。请换网络环境（如热点）后重新运行本项"
            else
                log "napcat 容器已存在，跳过安装"
            fi

            # 3. 容器内初始化 NapCat（内部源已替换为 jsDelivr，规避 nclatest 不可达）
            # 定位容器 root 的家目录（官方脚本在 /root 下运行）
            local container_root=""
            if [ -d "$napcat_rootfs_new/rootfs/root" ]; then
                container_root="$napcat_rootfs_new/rootfs/root"
            elif [ -d "$napcat_rootfs_legacy/root" ]; then
                container_root="$napcat_rootfs_legacy/root"
            fi
            if [ -n "$container_root" ]; then
                # 清理上次失败残留的官方脚本临时目录（残留会导致官方脚本拒绝执行）
                rm -rf "$container_root/NapCat" 2>/dev/null || true
                # QQ 官方下载链接已失效(404)，预下载可用安装包放进容器，官方脚本检测到本地包会跳过下载
                prepare_qq_package "$container_root" deb || true
            fi
            log "初始化容器内 NapCat（首次较慢，请耐心等待）..."
            proot-distro sh napcat -- bash -c "export DEBIAN_FRONTEND=noninteractive && \
                apt-get update -y && \
                apt-get install -y sudo curl libgcrypt20 && \
                curl -fsSL -o napcat.sh https://cdn.jsdelivr.net/gh/NapNeko/NapCat-Installer@main/script/install.sh && \
                sudo bash napcat.sh --docker n --cli n && \
                apt-get autoremove -y && apt-get clean && rm -rf /tmp/* /var/lib/apt/lists" 2>&1 | tee -a "$LOG_FILE"
            local ret=${PIPESTATUS[0]}
            if [ $ret -ne 0 ]; then
                warn "容器内初始化退出码 $ret，请查看上方输出（多为网络波动，可重新运行本项重试）"
                return 1
            fi
            success "NapCat 安装完成"
            if [ -d "$napcat_rootfs_new" ]; then
                echo -e "容器数据位置: ${GREEN}$napcat_rootfs_new${NC}"
            else
                echo -e "容器数据位置: ${GREEN}$napcat_rootfs_legacy${NC}"
            fi
            show_napcat_ws_guide
            start_napcat_and_show_token
            ;;
        "Linux")
            if command -v docker &>/dev/null; then
                log "检测到 Docker，可使用容器方式安装"
                echo -e "${YELLOW}提示: 回车直接用 Shell 方式安装；输入 y 用 Docker 方式安装${NC}"
                read -p "是否使用 Docker 安装 NapCat? (y/回车): " use_docker
            else
                use_docker=""
                log "未检测到 Docker，使用 Shell 方式安装"
            fi
            local args=()
            [ "$use_docker" = "y" ] && args+=(--docker y)
            if download_napcat_installer "$NAPCAT_INSTALLER_URL"; then
                patch_napcat_script
                # 非 Docker 方式: QQ 官方链接已失效(404)，预下载本地安装包，官方脚本检测到会跳过下载
                if [ "$use_docker" != "y" ]; then
                    local qq_pkg_type="deb"
                    command -v dpkg &>/dev/null || qq_pkg_type="rpm"
                    prepare_qq_package "$PWD" "$qq_pkg_type" || true
                fi
                bash "$NAPCAT_SH" "${args[@]}"
                local ret=$?
                rm -f "$NAPCAT_SH"
                if [ $ret -eq 0 ]; then
                    success "NapCat 安装脚本执行完成"
                    show_napcat_ws_guide
                    start_napcat_and_show_token
                else
                    warn "NapCat 安装脚本退出码 $ret，请查看上方输出"
                fi
            else
                error "NapCat 安装脚本下载失败，请检查网络"
            fi
            ;;
        "macOS")
            log "macOS 环境：请手动下载 NapCat.MacOs 安装工具"
            echo -e "\n${CYAN}========== macOS 安装 NapCat 步骤 ==========${NC}"
            echo -e "1. 打开下载页: ${GREEN}https://github.com/NapNeko/NapCatQQ/releases${NC}"
            echo -e "2. 下载 ${GREEN}NapCat.MacOs${NC} (需要 macOS 12.0 或以上系统)"
            echo -e "3. 打开下载的文件，按安装工具界面引导完成安装"
            echo -e "   注意: 由于权限问题，补丁过程可能需要手动替换 package.json，注意备份原文件"
            echo -e "4. 安装完成后按下方提示配置反向 WS 连接云崽"
            echo -e "${CYAN}============================================${NC}\n"
            show_napcat_ws_guide
            ;;
        "Windows")
            log "Windows 环境：请手动下载 NapCat 一键版"
            echo -e "\n${CYAN}========== Windows 安装 NapCat 步骤 ==========${NC}"
            echo -e "1. 打开下载页: ${GREEN}https://github.com/NapNeko/NapCatQQ/releases${NC}"
            echo -e "2. 下载 ${GREEN}NapCat.Shell.Windows.OneKey.zip${NC} (无头绿色版本，无需安装 QQ 和 NapCat，已内置)"
            echo -e "3. 解压到任意目录"
            echo -e "4. 双击运行 ${GREEN}NapCatInstaller.exe${NC} 等待自动化配置完成"
            echo -e "5. 进入 NapCat.XXXX.Shell 目录，双击 ${GREEN}napcat.bat${NC} 启动"
            echo -e "   快速登录: 启动时可传 QQ 号参数，如 napcat.bat 123456"
            echo -e "6. 启动后会输出 WebUI 地址，按下方提示配置反向 WS 连接云崽"
            echo -e "${CYAN}==============================================${NC}\n"
            show_napcat_ws_guide
            ;;
        *)
            error "无法识别当前平台，无法安装 NapCat"
            ;;
    esac
}

# ---------- 菜单 ----------
show_menu() {
    echo -e "${YELLOW}----------------------菜单---------------------${NC}"
    echo -e "${GREEN}             请选择要执行的操作：${NC}"
    echo -e "                0. 退出脚本${NC}"
    echo -e "                1. 安装芒果猫版云崽${NC}"
    echo -e "                2. 安装喵版云崽${NC}"
    echo -e "                3. 启动云崽${NC}"
    echo -e "                4. 进入云崽根目录${NC}"
    echo -e "                5. 安装 NapCat${NC}"
    echo -e "                6. 查看 NapCat token${NC}"
    echo -e "                7. 使用帮助${NC}"
    echo -e "                8. 技术支持${NC}"
    echo -e "                9. 启动 NapCat${NC}"
    if find_yunzai_root >/dev/null 2>&1; then
        echo -e "${GREEN}当前已安装云崽${NC}"
    fi
    echo -e "${YELLOW}----------------by 会飞的芒果猫------------------${NC}"
}

# ---------- 进入云崽根目录 ----------
enter_yunzai_dir() {
    log "用户选择: 进入云崽根目录"
    local target
    target=$(find_yunzai_root) || {
        echo -e "${RED}未检测到安装目录，请先安装云崽${NC}"
        return
    }
    cd "$target" && exec bash
}

# ---------- 帮助 ----------
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "1. 安装云崽 - 选择 1 或 2 安装对应版本"
    echo -e "2. 启动云崽 - 选择 3 启动云崽"
    echo -e "3. 安装 NapCat - 选择 5，自动按平台选择安装方式（Termux/Linux/Docker）"
    echo -e "   安装完成后按提示在 NapCat WebUI 配置反向 WS 连接云崽"
    echo -e "4. 启动 NapCat - 选择 9（手机重启后 NapCat 不会自动恢复，需重新启动）"
    echo -e "${CYAN}====================================${NC}\n"
}

# ---------- 技术支持 ----------
show_support() {
    echo -e "\n${CYAN}============== 技术支持 ==============${NC}"
    echo -e "${GREEN}QQ号: 3598537042${NC}"
    echo -e "${GREEN}昵称: 会飞的芒果猫${NC}"
    echo -e "${GREEN}QQ群: $SUPPORT_GROUP${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# ---------- 初始化 ----------
init_script() {
    clear
    echo "=== 云崽安装日志 ===" > "$LOG_FILE"
    log "脚本初始化"
    echo -e "${BLUE}"
    echo "==================================================="
    echo "             Yunzai一键安装脚本  "
    echo "                                        v$VERSION  "
    echo "==================================================="
    echo -e "QQ群: ${GREEN}$SUPPORT_GROUP${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo
}

# ---------- 主流程 ----------
main() {
    init_script
    while true; do
        show_menu
        read -p "请输入要执行操作选项：" choice
        case $choice in
            0) log "用户选择: 退出脚本"; echo -e "${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            1) install_mangocat; read -p "按回车键返回菜单..." ;;
            2) install_miao; read -p "按回车键返回菜单..." ;;
            3) start_yunzai; read -p "按回车键返回菜单..." ;;
            4) enter_yunzai_dir ;;
            5) install_napcat; read -p "按回车键返回菜单..." ;;
            6) show_napcat_token; read -p "按回车键返回菜单..." ;;
            7) show_help; read -p "按回车键返回菜单..." ;;
            8) show_support; read -p "按回车键返回菜单..." ;;
            9) start_napcat_and_show_token direct; read -p "按回车键返回菜单..." ;;
            *) warn "请输入正确选项"; sleep 1 ;;
        esac
    done
}

main