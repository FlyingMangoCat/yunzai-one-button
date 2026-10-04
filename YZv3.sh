#!/bin/bash

# ===========================================
# Yunzai一键安装脚本
# 版本: 3.0.0
# ===========================================

# ---------- 配置 ----------
VERSION="3.0.0"
SUPPORT_GROUP="658720198"
YUNZAI_DIR="$PWD/yunzai-one-button-fmc"
CURRENT_PLATFORM=""
CURRENT_OS=""

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
    if grep -q "mirrors.tuna.tsinghua.edu.cn\|mirrors.bfsu.edu.cn\|mirrors.ustc.edu.cn" "$src"; then
        return 0
    fi
    log "Termux 主源为官方 CDN, 切换为清华镜像加速（原源已备份为 sources.list.bak.yzb）..."
    cp "$src" "$src.bak.yzb" 2>/dev/null || true
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" > "$src"
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
        if [ -n "$PREFIX" ] && [ -d "$PREFIX" ]; then CURRENT_PLATFORM="Termux"
        else CURRENT_PLATFORM="Linux"; fi
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
            local core_pkgs=(nodejs-lts git redis wget curl python3 ffmpeg fonts-wqy-microhei fonts-wqy-zenhei)
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
            # Chromium（体积大易失败，不阻塞主流程）
            if ! command -v chromium &>/dev/null; then
                pkg install -y chromium 2>&1 | tee -a "$LOG_FILE"
                [ "${PIPESTATUS[0]}" -ne 0 ] && warn "Chromium 安装失败，可稍后手动执行: pkg install -y chromium"
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
            # 安装 Node.js（非 apt 系需要手动装）
            if ! command -v node &>/dev/null; then
                if command -v apt &>/dev/null; then
                    log "添加 Node.js 20.x 源..."
                    curl -fsSL --connect-timeout 10 --max-time 30 https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - 2>/dev/null || true
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
                curl -fsSL -o /tmp/node-installer.msi "https://nodejs.org/dist/v20.19.1/node-v20.19.1-x64.msi" 2>/dev/null
                if [ -f /tmp/node-installer.msi ]; then
                    powershell -Command "Start-Process msiexec -ArgumentList '/i /tmp/node-installer.msi /quiet /norestart' -Wait -NoNewWindow" 2>/dev/null || true
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
                # MSI 下载安装
                local redis_urls=(
                    "https://github.com/redis-windows/redis-windows/releases/latest/download/Redis-x64-msi.msi"
                    "https://github.com/redis-windows/redis-windows/releases/download/3.2.100/Redis-x64-3.2.100.msi"
                )
                local downloaded=""
                for url in "${redis_urls[@]}"; do
                    curl -fsSL -o /tmp/redis.msi "$url" 2>/dev/null && downloaded="/tmp/redis.msi" && break
                done
                if [ -n "$downloaded" ] && [ -f "$downloaded" ]; then
                    powershell -Command "Start-Process msiexec -ArgumentList '/i $downloaded /quiet /norestart' -Wait -NoNewWindow" 2>/dev/null || true
                    rm -f "$downloaded"
                    sleep 5
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

    # 4.4 创建总目录
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
                clone_urls+=("https://github.com/FlyingMangoCat/MangoCat-Yunzai.git" "https://ghproxy.com/https://github.com/FlyingMangoCat/MangoCat-Yunzai.git")
            fi
            if echo "$rp" | grep -q "yoimiya-kokomi/Miao-Yunzai"; then
                clone_urls+=("https://github.com/yoimiya-kokomi/Miao-Yunzai.git" "https://ghproxy.com/https://github.com/yoimiya-kokomi/Miao-Yunzai.git")
            fi
            clone_urls+=("https://gitee.com/$rp.git")
        fi
        if echo "$repo_url" | grep -q "github.com"; then
            local rp=$(echo "$repo_url" | sed 's|https://github.com/||')
            clone_urls+=("https://ghproxy.com/https://github.com/$rp" "https://hub.fastgit.xyz/$rp")
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
    if ! command -v pnpm &>/dev/null; then
        local pnpm_ver="pnpm@10"
        [ "$node_ver" -ge 22 ] && pnpm_ver="pnpm"
        # Termux/Android 文件系统不支持新版 pnpm 的 lock_shared()，固定用 pnpm@8
        if [ -d "/data/data/com.termux" ]; then
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
    local ok=false
    for i in 1 2 3; do
        pnpm install 2>&1 || pnpm install --ignore-scripts 2>&1 || true
        if [ -d "node_modules" ]; then
            ok=true && break
        fi
        log "依赖安装失败，重试 ($i/3)..."
        sleep 3
    done
    $ok || error "依赖安装失败，请检查网络连接"
    success "依赖安装完成"

    # 4.8 安装插件
    log "安装插件..."
    install_plugin "miao-plugin" "https://github.com/yoimiya-kokomi/miao-plugin.git" \
        "https://gitcode.com/TimeRainStarSky/miao-plugin.git" \
        "https://gitee.com/huifeidemangguomao/miao-plugin.git"
    install_plugin "xiaoyao-cvs-plugin" "https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git" \
        "https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git"
    install_plugin "liulian-plugin" "https://github.com/FlyingMangoCat/liulian-plugin.git" \
        "https://gitee.com/huifeidemangguomao/liulian-plugin.git"

    # 4.9 安装插件依赖
    log "安装插件依赖..."
    pnpm install 2>/dev/null || pnpm install --ignore-scripts 2>/dev/null || true
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

# ---------- 选项 3: 启动云崽 ----------
start_yunzai() {
    log "用户选择: 启动云崽"
    if [ ! -d "$YUNZAI_DIR" ]; then
        echo -e "${RED}未检测到安装目录 $YUNZAI_DIR，请先安装云崽${NC}"
        return
    fi
    if [ ! -f "$YUNZAI_DIR/package.json" ]; then
        echo -e "${RED}未检测到云崽代码，请先安装${NC}"
        return
    fi
    echo -e "${GREEN}启动云崽...${NC}"
    cd "$YUNZAI_DIR" && node app
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
start_napcat_and_show_token() {
    echo -e "${YELLOW}是否现在启动 NapCat? 启动后才能生成 WebUI token${NC}"
    read -p "立即启动 NapCat? (y/回车): " start_now
    [ "$start_now" != "y" ] && return 0

    detect_platform
    case "$CURRENT_PLATFORM" in
        "Termux")
            # 官方 Termux 方式: proot-distro 容器 + screen 后台（与官方脚本输出一致）
            if ! command -v proot-distro &>/dev/null; then
                warn "未找到 proot-distro，请按安装脚本输出的说明手动启动"
                return 1
            fi
            log "后台启动 NapCat（screen 会话 napcat）..."
            screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c "xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"' || {
                warn "启动失败，请手动执行:"
                echo -e "${GREEN}screen -dmS napcat bash -c 'proot-distro sh napcat -- bash -c \"xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox\"'${NC}"
                return 1
            }
            echo -e "${GREEN}已在 screen 后台会话 napcat 中启动${NC}"
            echo -e "查看启动输出: ${GREEN}screen -r napcat${NC}，离开按 ${GREEN}Ctrl+A 再按 D${NC}"
            ;;
        "Linux")
            if command -v napcat &>/dev/null; then
                log "后台启动 NapCat..."
                nohup napcat >/dev/null 2>&1 &
            elif command -v qq &>/dev/null; then
                log "后台启动 NapCat（qq --no-sandbox）..."
                nohup qq --no-sandbox >/dev/null 2>&1 &
            else
                warn "未找到 napcat/qq 启动命令，请按安装输出的说明手动启动，启动后再选菜单 6 查看 token"
                return 1
            fi
            ;;
        *)
            warn "当前平台请按对应安装说明手动启动，启动后再选菜单 6 查看 token"
            return 1
            ;;
    esac

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
                # 第 1 次走官方 Docker Hub 源；失败后改用实测可用的国内镜像源兜底
                local image_refs=("debian" "dockerproxy.net/library/debian")
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
    if [ -d "$YUNZAI_DIR" ]; then
        echo -e "${GREEN}当前已安装云崽${NC}"
    fi
    echo -e "${YELLOW}----------------by 会飞的芒果猫------------------${NC}"
}

# ---------- 进入云崽根目录 ----------
enter_yunzai_dir() {
    log "用户选择: 进入云崽根目录"
    local target="$YUNZAI_DIR"
    # 查找云崽根目录（总目录下的子目录，含 package.json）
    if [ -d "$YUNZAI_DIR" ]; then
        for d in "$YUNZAI_DIR"/*/; do
            if [ -f "$d/package.json" ]; then
                target="$d"
                break
            fi
        done
    fi
    if [ ! -d "$target" ]; then
        echo -e "${RED}未检测到安装目录，请先安装云崽${NC}"
        return
    fi
    cd "$target" && exec bash
}

# ---------- 帮助 ----------
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "1. 安装云崽 - 选择 1 或 2 安装对应版本"
    echo -e "2. 启动云崽 - 选择 3 启动云崽"
    echo -e "3. 安装 NapCat - 选择 5，自动按平台选择安装方式（Termux/Linux/Docker）"
    echo -e "   安装完成后按提示在 NapCat WebUI 配置反向 WS 连接云崽"
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
            *) warn "请输入正确选项"; sleep 1 ;;
        esac
    done
}

main