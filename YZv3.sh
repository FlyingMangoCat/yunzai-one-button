#!/bin/bash

# ===========================================
# 云崽(喵崽)一键安装脚本 - 原生环境版
# 版本: 3.0.0
# ===========================================

# ---------- 配置 ----------
VERSION="3.0.0"
SUPPORT_GROUP="658720198"
YUNZAI_DIR="yunzai-one-button-fmc"
CURRENT_PLATFORM=""
CURRENT_OS=""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件
if [ -d "/sdcard" ]; then
    LOG_FILE="/sdcard/yunzai_install.log"
else
    LOG_FILE="./yunzai_install.log"
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
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        CURRENT_OS="Linux"
        if [ -d "$PREFIX" ]; then CURRENT_PLATFORM="Termux"
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
            pkg update -y && pkg upgrade -y
            pkg install -y nodejs-lts git redis chromium wget curl python3 ffmpeg \
                fonts-wqy-microhei fonts-wqy-zenhei 2>/dev/null
            # 启动 Redis
            redis-server --daemonize yes 2>/dev/null || true
            ;;

        "Linux")
            log "Linux 环境安装..."
            local pm_install=""
            local pkgs=()
            if command -v apt &>/dev/null; then
                curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null || true
                pm_install="apt-get install -y -qq"
                pkgs=(nodejs git redis-server chromium-browser fonts-wqy-microhei fonts-wqy-zenhei ffmpeg python3 python3-pip)
            elif command -v yum &>/dev/null; then
                curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - 2>/dev/null || true
                pm_install="yum install -y"
                pkgs=(nodejs git redis chromium ffmpeg python3)
            elif command -v dnf &>/dev/null; then
                pm_install="dnf install -y"
                pkgs=(nodejs git redis chromium ffmpeg python3)
            else
                error "不支持的 Linux 包管理器"
            fi
            for pkg in "${pkgs[@]}"; do
                for i in 1 2 3; do
                    $pm_install "$pkg" 2>/dev/null && break
                    log "安装 $pkg 失败，重试 ($i/3)..."
                    sleep 2
                done
            done
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
    if [ -f "$YUNZAI_DIR/package.json" ]; then
        log "云崽代码已存在，跳过克隆"
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
        for url in "${clone_urls[@]}"; do
            for i in 1 2 3; do
                git clone --depth=1 "$url" "$YUNZAI_DIR" 2>/dev/null && \
                [ -f "$YUNZAI_DIR/package.json" ] && ok=true && break 2
                log "克隆失败，重试 ($i/3)..."
                sleep 2
            done
        done
        $ok || error "代码克隆失败，请检查网络"
        success "代码克隆完成"
    fi

    # 4.6 全局安装 pnpm
    log "安装 pnpm..."
    npm install -g pnpm 2>/dev/null || npm install -g cnpm --registry=https://registry.npmmirror.com 2>/dev/null || true

    # 4.7 安装依赖
    cd "$YUNZAI_DIR"
    log "安装依赖..."
    local ok=false
    for reg in "https://registry.npmmirror.com" "https://registry.npmjs.org" "https://registry.npm.taobao.org"; do
        for i in 1 2 3; do
            if npm install --registry="$reg" --timeout=120000 2>&1 | tail -5; then
                [ -d "node_modules" ] && [ -f "node_modules/file-type/package.json" ] && ok=true && break 2
            fi
            log "依赖安装失败，重试 ($i/3)..."
            sleep 3
        done
    done
    $ok || error "依赖安装失败，请检查网络连接后重试"

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
    pnpm install -P 2>/dev/null || pnpm install -P --ignore-scripts 2>/dev/null || true
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

# ---------- 菜单 ----------
show_menu() {
    echo -e "${YELLOW}----------------------菜单---------------------${NC}"
    echo -e "${GREEN}             请选择要执行的操作：${NC}"
    echo -e "                0. 退出脚本${NC}"
    echo -e "                1. 安装芒果猫版云崽${NC}"
    echo -e "                2. 安装喵版云崽${NC}"
    echo -e "                3. 启动云崽${NC}"
    echo -e "                4. 使用帮助${NC}"
    echo -e "                5. 技术支持${NC}"
    if [ -d "$YUNZAI_DIR" ]; then
        echo -e "${GREEN}当前已安装云崽${NC}"
    fi
    echo -e "${YELLOW}----------------by 会飞的芒果猫------------------${NC}"
}

# ---------- 帮助 ----------
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "1. 安装云崽 - 选择 1 或 2 安装对应版本"
    echo -e "2. 启动云崽 - 选择 3 启动云崽"
    echo -e "3. 配置云崽 - 修改 $YUNZAI_DIR/config 目录下的配置文件"
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
    echo "             云崽(喵崽)一键安装脚本  "
    echo "                                        v$VERSION  "
    echo "==================================================="
    echo -e "${NC}"
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
            4) show_help; read -p "按回车键返回菜单..." ;;
            5) show_support; read -p "按回车键返回菜单..." ;;
            *) warn "请输入正确选项"; sleep 1 ;;
        esac
    done
}

main