#!/bin/bash

# ===========================================
# 云崽(喵崽)一键安装脚本 - Docker容器化版
# 版本: 2.0.0
# ===========================================

# ---------- 配置 ----------
VERSION="2.0.0"
SUPPORT_GROUP="658720198"
YUNZAI_DIR="yunzai-one-button-fmc"
CONTAINER_NAME="yunzai-bot"
CURRENT_PLATFORM=""
CURRENT_OS=""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件路径（平台自适应）
if [ -d "/sdcard" ]; then
    LOG_FILE="/sdcard/yunzai_install.log"
else
    LOG_FILE="./yunzai_install.log"
fi

# ---------- 日志函数 ----------
log() {
    local msg="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

success() {
    log "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    log "${YELLOW}[WARNING] $1${NC}"
}

error() {
    log "${RED}[ERROR] $1${NC}"
    exit 1
}

# ---------- 1. 获取权限 ----------
get_permissions() {
    log "获取系统权限..."

    # 尝试各平台权限命令（能获取就获取，获取不了不影响）
    if command -v termux-setup-storage &> /dev/null; then
        termux-setup-storage 2>/dev/null || warn "存储权限请求未响应，如后续写入失败请手动授权"
    fi
    if command -v termux-wake-lock &> /dev/null; then
        termux-wake-lock 2>/dev/null || warn "唤醒锁获取失败，后台运行可能受限"
    fi

    # 实际测试：写入 + 执行权限
    local test_file=".permission_test_$$"
    if ! echo "test" > "$test_file" 2>/dev/null; then
        error "无法写入文件，请检查目录权限"
    fi
    if ! chmod +x "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        error "无法添加执行权限，请检查文件系统权限"
    fi
    rm -f "$test_file"

    success "权限检查通过"
}

# ---------- 2. 检测平台 ----------
detect_platform() {
    log "检测当前平台..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        CURRENT_OS="Linux"
        if [ -d "$PREFIX" ]; then
            CURRENT_PLATFORM="Termux"
        else
            CURRENT_PLATFORM="Linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        CURRENT_OS="macOS"
        CURRENT_PLATFORM="macOS"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        CURRENT_OS="Windows"
        CURRENT_PLATFORM="Windows"
    else
        CURRENT_PLATFORM="Unknown"
        CURRENT_OS="Unknown"
    fi
    success "检测到平台: $CURRENT_PLATFORM ($CURRENT_OS)"
    echo -e "${GREEN}当前平台: $CURRENT_PLATFORM ($CURRENT_OS)${NC}"
}

# ---------- 3. Docker 安装（各平台） ----------
check_install_docker() {
    log "检查 Docker 安装状态..."
    if command -v docker &> /dev/null; then
        success "Docker 已安装"
        docker --version
        # 验证 Docker 守护进程是否在运行
        log "检查 Docker 守护进程..."
        if docker ps &> /dev/null; then
            success "Docker 守护进程运行中"
        else
            warn "Docker 守护进程未运行，尝试自动启动..."
            # 各平台自动启动 Docker
            case "$CURRENT_PLATFORM" in
                "Windows")
                    # 修复 Docker Desktop 后端崩溃：重置内部 WSL 组件
                    log "修复 Docker Desktop 后端组件..."
                    # 关闭所有 Docker 进程
                    taskkill //f //im "Docker Desktop.exe" 2>/dev/null || true
                    taskkill //f //im "com.docker.backend.exe" 2>/dev/null || true
                    # 重置 Docker 内部 WSL 发行版（Docker 会自动重建）
                    wsl --shutdown 2>/dev/null || true
                    wsl --unregister docker-desktop 2>/dev/null || true
                    wsl --unregister docker-desktop-data 2>/dev/null || true
                    sleep 3
                    # 启动 Docker Desktop
                    if [ -f "$PROGRAMFILES/Docker/Docker/Docker Desktop.exe" ]; then
                        "$PROGRAMFILES/Docker/Docker/Docker Desktop.exe" &
                    elif [ -f "/c/Program Files/Docker/Docker/Docker Desktop.exe" ]; then
                        "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
                    fi
                    ;;
                "macOS")
                    open -a Docker 2>/dev/null || true
                    ;;
                "Linux")
                    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
                    ;;
            esac
            # 等待 Docker 就绪（带进程存活检测）
            # 设置较短的 CLI 超时，避免 docker ps 挂起太久
            export DOCKER_CLI_TIMEOUT=10
            local docker_waited=0
            while [ $docker_waited -lt 30 ]; do
                sleep 5
                docker_waited=$((docker_waited + 1))
                # 检查 Docker 是否就绪
                if timeout 10 docker ps &> /dev/null; then
                    success "Docker 守护进程已启动"
                    docker --version
                    return 0
                fi
                # Windows 下检查 Docker Desktop 后端进程是否还在
                if [ "$CURRENT_PLATFORM" = "Windows" ] && ! pgrep -f "com.docker.backend" &> /dev/null; then
                    warn "Docker Desktop 后端进程已退出，尝试重新启动..."
                    "$PROGRAMFILES/Docker/Docker/Docker Desktop.exe" &>/dev/null &
                    sleep 5
                fi
                log "等待 Docker 启动 ($docker_waited/30)..."
            done
            error "Docker 自动启动失败，请检查 Docker 安装状态"
        fi
        return 0
    fi

    warn "Docker 未安装，开始安装..."
    case "$CURRENT_PLATFORM" in
        "Termux") install_docker_termux ;;
        "Linux")  install_docker_linux ;;
        "macOS")  install_docker_macos ;;
        "Windows") install_docker_windows ;;
        *) error "不支持的平台: $CURRENT_PLATFORM" ;;
    esac
}

install_docker_termux() {
    log "在 Termux 中安装 Docker..."
    termux-setup-storage 2>/dev/null || true
    termux-wake-lock 2>/dev/null || true

    # 配置 Termux 镜像源（国内加速）
    log "配置包管理器镜像..."
    if command -v termux-change-repo &> /dev/null; then
        termux-change-repo 2>/dev/null || true
    fi
    # 手动替换为清华镜像
    sed -i 's|^deb https://termux.org|deb https://mirrors.tuna.tsinghua.edu.cn/termux|g' $PREFIX/etc/apt/sources.list 2>/dev/null || true

    # 更新并安装 Docker（带重试）
    for i in 1 2 3; do
        pkg update -y 2>/dev/null && pkg upgrade -y 2>/dev/null && break
        log "pkg 更新失败，重试 ($i/3)..."
        sleep 3
    done
    for i in 1 2 3; do
        pkg install -y git proot docker 2>/dev/null && break
        log "pkg 安装失败，重试 ($i/3)..."
        sleep 3
    done

    # 启动 Docker 服务
    log "启动 Docker 服务..."
    dockerd --host=unix:///data/data/com.termux/files/usr/var/run/docker.sock --iptables=false &
    local waited=0
    while [ $waited -lt 30 ]; do
        if docker ps &> /dev/null; then
            success "Docker 安装并启动成功"
            docker --version
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    error "Docker 启动失败，请检查 Termux 权限配置"
}

install_docker_linux() {
    log "在 Linux 中安装 Docker..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        error "无法检测 Linux 发行版"
    fi

    case $DISTRO in
        ubuntu|debian)
            # 国内镜像加速
            local docker_repo="https://download.docker.com/linux/$DISTRO"
            curl -fsSL "${docker_repo}/gpg" | apt-key add - 2>/dev/null || \
            curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/$DISTRO/gpg" | apt-key add - 2>/dev/null
            add-apt-repository "deb [arch=amd64] ${docker_repo} $(lsb_release -cs) stable" 2>/dev/null || \
            add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/$DISTRO $(lsb_release -cs) stable" 2>/dev/null
            for i in 1 2 3; do
                apt-get update 2>/dev/null && apt-get install -y docker-ce docker-ce-cli containerd.io 2>/dev/null && break
                log "apt 安装失败，重试 ($i/3)..."
                sleep 3
            done
            ;;
        centos|rhel|fedora)
            local pm="yum"
            [ "$DISTRO" = "fedora" ] && pm="dnf"
            local repo_url="https://download.docker.com/linux/$DISTRO/docker-ce.repo"
            $pm install -y yum-utils dnf-plugins-core 2>/dev/null
            $pm-config-manager --add-repo "$repo_url" 2>/dev/null || \
            $pm-config-manager --add-repo "https://mirrors.aliyun.com/docker-ce/linux/$DISTRO/docker-ce.repo" 2>/dev/null
            for i in 1 2 3; do
                $pm install -y docker-ce docker-ce-cli containerd.io 2>/dev/null && break
                log "$pm 安装失败，重试 ($i/3)..."
                sleep 3
            done
            ;;
        *) error "不支持的 Linux 发行版: $DISTRO" ;;
    esac

    systemctl start docker 2>/dev/null || service docker start 2>/dev/null
    systemctl enable docker 2>/dev/null || true

    if command -v docker &> /dev/null; then
        success "Docker 安装完成"
        docker --version
    else
        error "Docker 安装失败"
    fi
}

install_docker_macos() {
    log "在 macOS 中安装 Docker..."
    if ! command -v brew &> /dev/null; then
        log "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    log "安装 Docker Desktop..."
    brew install --cask docker 2>&1 || error "Docker Desktop 安装失败"
    # 尝试启动 Docker Desktop
    log "启动 Docker Desktop..."
    open -a Docker 2>/dev/null || true
    sleep 10
    # 等待 Docker 可用
    for i in $(seq 1 30); do
        if command -v docker &> /dev/null && docker ps &> /dev/null; then
            success "Docker Desktop 安装并启动成功"
            docker --version
            return 0
        fi
        sleep 5
    done
    error "Docker Desktop 启动超时，请手动启动 Docker Desktop 应用"
}

install_docker_windows() {
    log "在 Windows 中安装 Docker..."

    # ---------- 查找 docker CLI ----------
    find_docker_cli() {
        if command -v docker &> /dev/null; then
            docker_exe="docker"
            return 0
        fi
        local paths=(
            "$PROGRAMFILES/Docker/Docker/resources/bin/docker.exe"
            "/c/Program Files/Docker/Docker/resources/bin/docker.exe"
            "$LOCALAPPDATA/Programs/Docker/Docker/resources/bin/docker.exe"
            "/c/Program Files/Docker/Docker/resources/bin/com.docker.cli.exe"
        )
        for p in "${paths[@]}"; do
            if [ -f "$p" ]; then
                docker_exe="$p"
                export PATH="$PATH:$(dirname "$p")"
                return 0
            fi
        done
        return 1
    }

    # ---------- 启动 Docker Desktop 并等待就绪 ----------
    wait_docker_ready() {
        local exe="${1:-docker}"
        log "启动 Docker Desktop..."
        # 尝试多种方式启动
        "$PROGRAMFILES/Docker/Docker/Docker Desktop.exe" 2>/dev/null || \
        "/c/Program Files/Docker/Docker/Docker Desktop.exe" 2>/dev/null || \
        powershell -Command "Start-Process 'Docker Desktop' -WindowStyle Hidden" 2>/dev/null || true
        for i in $(seq 1 30); do
            sleep 5
            if "$exe" ps &> /dev/null 2>&1; then
                success "Docker Desktop 启动成功"
                "$exe" --version
                return 0
            fi
            log "等待 Docker 启动 ($i/30)..."
        done
        warn "Docker Desktop 启动超时"
        return 1
    }

    local docker_exe=""

    # 1. 先找 docker CLI 在不在
    if find_docker_cli; then
        log "Docker Desktop 已安装"
        # 检查是否在运行
        if "$docker_exe" ps &> /dev/null 2>&1; then
            success "Docker Desktop 已在运行"
            "$docker_exe" --version
            return 0
        fi
        # 已安装但没运行，尝试启动
        wait_docker_ready "$docker_exe" && return 0
        # 启动超时，尝试修复
        log "Docker 启动失败，尝试修复安装..."
    fi

    # 2. 如果没找到 CLI，用 winget 检查是否已安装
    if command -v winget &> /dev/null; then
        if winget list --id Docker.DockerDesktop 2>/dev/null | grep -q "Docker"; then
            log "Docker Desktop 已安装（通过 winget 检测到），查找 CLI 路径..."
            if find_docker_cli; then
                wait_docker_ready "$docker_exe" && return 0
            fi
            # 找到 exe 但启动不了，尝试修复
        fi
    fi

    # 3. 真的没安装，用 winget 安装
    if command -v winget &> /dev/null; then
        log "安装 Docker Desktop（winget）..."
        winget install -e --id Docker.DockerDesktop --accept-source-agreements 2>&1
        sleep 10
        if find_docker_cli; then
            wait_docker_ready "$docker_exe" && return 0
        fi
    fi

    # 4. winget 不行，下载安装包
    log "下载 Docker Desktop 安装包..."
    local installer_urls=(
        "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
        "https://mirrors.aliyun.com/docker/win/stable/Docker%20Desktop%20Installer.exe"
    )
    local installer=""
    for url in "${installer_urls[@]}"; do
        log "尝试下载: $url"
        curl -fsSL -o /tmp/docker-installer.exe "$url" 2>/dev/null && installer="/tmp/docker-installer.exe" && break
    done

    if [ -n "$installer" ] && [ -f "$installer" ]; then
        log "静默安装 Docker Desktop..."
        "$installer" install --accept-license --quiet 2>/dev/null || true
        rm -f "$installer"
        sleep 15
        if find_docker_cli; then
            wait_docker_ready "$docker_exe" && return 0
        fi
    fi

    error "Docker Desktop 自动安装失败，请手动安装后重试: https://www.docker.com/products/docker-desktop"
}

# ---------- 容器辅助函数 ----------
container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

docker_exec() {
    docker exec "$CONTAINER_NAME" bash -c "$1"
}

ensure_container() {
    # 检查并启动容器
    # 确保 docker-compose.yml 和 Dockerfile 存在（从远程下载）
    local repo_base="https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master"
    if [ ! -f "docker-compose.yml" ]; then
        log "下载 docker-compose.yml..."
        curl -fsSL -o docker-compose.yml "$repo_base/docker-compose.yml" || \
            error "下载 docker-compose.yml 失败"
    fi
    if [ ! -f "Dockerfile" ]; then
        log "下载 Dockerfile..."
        curl -fsSL -o Dockerfile "$repo_base/Dockerfile" || \
            error "下载 Dockerfile 失败"
    fi
    if [ ! -f "docker-entrypoint.sh" ]; then
        log "下载 docker-entrypoint.sh..."
        curl -fsSL -o docker-entrypoint.sh "$repo_base/docker-entrypoint.sh" || \
            error "下载 docker-entrypoint.sh 失败"
        chmod +x docker-entrypoint.sh
    fi

    if ! container_exists; then
        # 首次：构建镜像并启动
        echo -e "${CYAN}========== 配置容器运行环境 ==========${NC}"
        echo -e "Docker 镜像将自动安装以下环境："
        echo -e "  ${GREEN}•${NC} Ubuntu 22.04 基础系统"
        echo -e "  ${GREEN}•${NC} Node.js 20.x"
        echo -e "  ${GREEN}•${NC} Redis 数据库"
        echo -e "  ${GREEN}•${NC} Chromium 浏览器（截图功能）"
        echo -e "  ${GREEN}•${NC} pnpm / cnpm 包管理器"
        echo -e "  ${GREEN}•${NC} 中文字体（wqy-microhei / wqy-zenhei）"
        echo -e "  ${GREEN}•${NC} ffmpeg、Python 3.10 等依赖"
        echo -e "${CYAN}========================================${NC}"
        log "构建 Docker 镜像（首次需要下载依赖，请耐心等待）..."
        docker-compose build || error "Docker 镜像构建失败，请检查网络和 Docker 状态"
        log "启动容器..."
        docker-compose up -d || error "容器启动失败"
        sleep 3
        if ! container_running; then
            error "容器启动后未正常运行，请检查 Docker 状态"
        fi
        echo -e "${GREEN}容器环境配置完成${NC}"
    elif ! container_running; then
        log "启动容器..."
        docker-compose up -d || error "容器启动失败"
        sleep 3
        if ! container_running; then
            error "容器启动后未正常运行"
        fi
    fi
}

# ---------- 安装插件通用函数（多镜像重试） ----------
install_plugin() {
    local name="$1"
    shift
    local urls=("$@")
    if docker_exec "test -d /app/plugins/$name" 2>/dev/null; then
        log "  - $name 已存在，跳过"
        return
    fi
    for url in "${urls[@]}"; do
        for i in 1 2 3; do
            docker_exec "cd /app && git clone --depth=1 $url ./plugins/$name" 2>/dev/null && \
            docker_exec "test -d /app/plugins/$name" 2>/dev/null && \
            log "  - $name 安装完成" && return
            log "  - $name 安装失败，重试 ($i/3)..."
            sleep 2
        done
    done
    warn "  - $name 安装失败，已尝试所有镜像源"
}

# ---------- 安装云崽（通用流程，每步验证+重试+镜像+断点续装） ----------
install_yunzai() {
    local repo_url="$1"
    local version_name="$2"

    echo -e "\n${CYAN}========== 开始安装 $version_name ==========${NC}"

    # 1. 获取权限（轻量操作，每次执行）
    get_permissions

    # 2. 检测环境（轻量操作，每次执行）
    detect_platform

    # 3. 检查 Docker（已装则跳过）
    check_install_docker

    # 4. 创建总目录（轻量操作，每次执行）
    mkdir -p "$YUNZAI_DIR" || error "创建目录 $YUNZAI_DIR 失败"

    # 5. 容器环境（检查断点：容器已存在则跳过构建）
    if container_exists && container_running; then
        log "容器环境已就绪，跳过"
    else
        ensure_container
        sleep 2
        if ! container_running; then
            error "容器启动失败，请检查 Docker 状态"
        fi
    fi

    # 6. 克隆代码（检查断点：package.json 存在则跳过）
    if docker_exec "test -f /app/package.json" 2>/dev/null; then
        log "云崽代码已存在，跳过克隆"
    else
        log "克隆 $version_name 代码..."
        local clone_success=false
        local clone_urls=("$repo_url")
        # 为 gitee 仓库添加 GitHub 镜像
        if echo "$repo_url" | grep -q "gitee.com"; then
            local repo_path=$(echo "$repo_url" | sed 's|https://gitee.com/||' | sed 's|\.git$||')
            if echo "$repo_path" | grep -q "huifeidemangguomao/MangoCat-Yunzai"; then
                clone_urls+=("https://github.com/FlyingMangoCat/MangoCat-Yunzai.git")
                clone_urls+=("https://ghproxy.com/https://github.com/FlyingMangoCat/MangoCat-Yunzai.git")
            fi
            if echo "$repo_path" | grep -q "yoimiya-kokomi/Miao-Yunzai"; then
                clone_urls+=("https://github.com/yoimiya-kokomi/Miao-Yunzai.git")
                clone_urls+=("https://ghproxy.com/https://github.com/yoimiya-kokomi/Miao-Yunzai.git")
            fi
            clone_urls+=("https://gitee.com/$repo_path.git")
        fi
        if echo "$repo_url" | grep -q "github.com"; then
            local repo_path=$(echo "$repo_url" | sed 's|https://github.com/||')
            clone_urls+=("https://ghproxy.com/https://github.com/$repo_path")
            clone_urls+=("https://hub.fastgit.xyz/$repo_path")
        fi
        for url in "${clone_urls[@]}"; do
            for i in 1 2 3; do
                docker_exec "cd /app && git clone --depth=1 $url ." 2>/dev/null && \
                docker_exec "test -f /app/package.json" 2>/dev/null && \
                clone_success=true && break 2
                log "克隆失败，重试 ($i/3)..."
                sleep 2
            done
        done
        if [ "$clone_success" != true ]; then
            error "代码克隆失败，已尝试所有镜像源，请检查网络"
        fi
        success "代码克隆完成"
    fi

    # 7. 装依赖（检查断点：node_modules 存在则跳过）
    if docker_exec "test -d /app/node_modules" 2>/dev/null; then
        log "依赖已安装，跳过"
    else
        log "安装依赖..."
        local dep_success=false
        local npm_registries=(
            "https://registry.npmmirror.com"
            "https://registry.npmjs.org"
            "https://registry.npm.taobao.org"
        )
        for reg in "${npm_registries[@]}"; do
            for i in 1 2 3; do
                docker_exec "cd /app && npm install pnpm -g 2>/dev/null; npm install -g cnpm --registry=https://registry.npmmirror.com 2>/dev/null; cnpm install --registry=$reg" 2>/dev/null
                if docker_exec "test -d /app/node_modules" 2>/dev/null; then
                    dep_success=true
                    break 2
                fi
                log "依赖安装失败，切换镜像重试 ($i/3)..."
                sleep 2
            done
        done
        if [ "$dep_success" != true ]; then
            error "依赖安装失败，已尝试所有镜像源"
        fi
        success "依赖安装完成"
    fi

    # 8. 装插件（检查断点：每个插件目录存在则跳过）
    log "安装插件..."
    install_plugin "miao-plugin" "https://github.com/yoimiya-kokomi/miao-plugin.git" \
        "https://gitcode.com/TimeRainStarSky/miao-plugin.git" \
        "https://gitee.com/huifeidemangguomao/miao-plugin.git"
    install_plugin "xiaoyao-cvs-plugin" "https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git" \
        "https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git" \
        "https://ghproxy.com/https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git"
    install_plugin "liulian-plugin" "https://github.com/FlyingMangoCat/liulian-plugin.git" \
        "https://gitee.com/huifeidemangguomao/liulian-plugin.git" \
        "https://ghproxy.com/https://github.com/FlyingMangoCat/liulian-plugin.git"

    # 9. 装插件依赖（检查断点：pnpm-lock.yaml 存在则跳过）
    #    注意：cnpm install 生成 package-lock.json，pnpm install 生成 pnpm-lock.yaml
    if docker_exec "test -f /app/pnpm-lock.yaml" 2>/dev/null; then
        log "插件依赖已安装，跳过"
    else
        log "安装插件依赖..."
        local pnpm_success=false
        for i in 1 2 3; do
            docker_exec "cd /app && pnpm install -P" 2>/dev/null && \
            docker_exec "test -f /app/pnpm-lock.yaml" 2>/dev/null && \
            pnpm_success=true && break
            log "插件依赖安装失败，重试 ($i/3)..."
            sleep 3
        done
        if [ "$pnpm_success" != true ]; then
            error "插件依赖安装失败"
        fi
        success "插件依赖安装完成"
    fi

    # 10. 启动云崽（检查断点：node app 进程存在则跳过）
    if docker_exec "pgrep -f 'node app' > /dev/null" 2>/dev/null; then
        echo -e "${GREEN}$version_name 已在运行中${NC}"
    else
        log "启动 $version_name ..."
        docker_exec "cd /app && nohup node app > /app/yunzai.log 2>&1 &"
        sleep 3
        if docker_exec "pgrep -f 'node app' > /dev/null" 2>/dev/null; then
            echo -e "${GREEN}$version_name 已启动！${NC}"
        else
            warn "云崽可能未成功启动，请手动检查日志"
        fi
    fi
    echo -e "${YELLOW}查看日志: docker exec $CONTAINER_NAME tail -f /app/yunzai.log${NC}"
    echo -e "${YELLOW}首次启动请配置主人QQ等参数${NC}"
}

# ---------- 选项 1: 安装芒果猫版云崽 ----------
install_mangocat() {
    log "用户选择: 安装芒果猫版云崽"
    install_yunzai \
        "https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git" \
        "芒果猫版云崽"
}

# ---------- 选项 2: 安装喵版云崽 ----------
install_miao() {
    log "用户选择: 安装喵版云崽"
    install_yunzai \
        "https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git" \
        "喵版云崽"
}

# ---------- 选项 3: 启动云崽 ----------
start_yunzai() {
    log "用户选择: 启动云崽"

    # 检测总目录
    if [ ! -d "$YUNZAI_DIR" ]; then
        echo -e "${RED}未检测到安装目录 $YUNZAI_DIR，请先安装云崽${NC}"
        return
    fi

    # 检测 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker 未安装，请先安装云崽${NC}"
        return
    fi

    # 确保容器在运行
    ensure_container

    # 检测云崽代码
    if ! docker_exec "test -f /app/package.json" 2>/dev/null; then
        echo -e "${RED}未检测到云崽代码，请先安装${NC}"
        return
    fi

    # 启动云崽
    log "启动云崽..."
    docker_exec "cd /app && nohup node app > /app/yunzai.log 2>&1 &"
    success "云崽已启动"
    echo -e "${GREEN}查看日志: docker exec $CONTAINER_NAME tail -f /app/yunzai.log${NC}"
}

# ---------- 选项 4: 进入容器命令行 ----------
enter_container() {
    log "用户选择: 进入容器命令行"
    if ! container_running; then
        error "容器未运行，请先安装或启动云崽"
    fi
    docker exec -it "$CONTAINER_NAME" /bin/bash -c "cd /app && exec bash"
}

# ---------- 菜单 ----------
show_menu() {
    echo -e "${YELLOW}----------------------菜单---------------------${NC}"
    echo -e "${GREEN}             请选择要执行的操作：${NC}"
    echo -e "                0. 退出脚本${NC}"
    echo -e "                1. 安装芒果猫版云崽${NC}"
    echo -e "                2. 安装喵版云崽${NC}"
    echo -e "                3. 启动云崽${NC}"
    echo -e "                4. 进入容器命令行${NC}"
    echo -e "                5. 使用帮助${NC}"
    echo -e "                6. 技术支持${NC}"
    if [ -d "$YUNZAI_DIR" ]; then
        echo -e "${GREEN}当前已安装云崽${NC}"
    fi
    echo -e "${YELLOW}----------------by 会飞的芒果猫------------------${NC}"
}

# ---------- 帮助 ----------
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "1. 安装云崽 - 选择 1 或 2 安装对应版本，自动走完整个流程并启动"
    echo -e "2. 启动云崽 - 仅启动已安装的云崽，未安装则提示"
    echo -e "3. 进入容器 - 进入容器内云崽根目录进行操作"
    echo -e "${CYAN}====================================${NC}"
    echo -e "${GREEN}Docker 常用命令：${NC}"
    echo -e "  查看日志: docker exec $CONTAINER_NAME tail -f /app/yunzai.log"
    echo -e "  停止云崽: docker exec $CONTAINER_NAME pkill -f 'node app'"
    echo -e "  重启容器: docker-compose restart"
    echo -e "  停止容器: docker-compose down"
    echo -e "${CYAN}====================================${NC}\n"
}

# ---------- 技术支持 ----------
show_support() {
    echo -e "\n${CYAN}============== 技术支持 ==============${NC}"
    echo -e "如使用中遇到问题:"
    echo -e "${GREEN}QQ号: 3598537042${NC}"
    echo -e "${GREEN}昵称: 会飞的芒果猫${NC}"
    echo -e "${GREEN}QQ群: $SUPPORT_GROUP${NC}"
    echo -e "\n添加好友时请说明问题并提供相关截图"
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
    echo "                          Docker容器化版  "
    echo "                                   v$VERSION  "
    echo "==================================================="
    echo -e "${NC}"
    echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
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
            0)
                log "用户选择: 退出脚本"
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            1)
                install_mangocat
                read -p "按回车键返回菜单..."
                ;;
            2)
                install_miao
                read -p "按回车键返回菜单..."
                ;;
            3)
                start_yunzai
                read -p "按回车键返回菜单..."
                ;;
            4)
                enter_container
                ;;
            5)
                show_help
                read -p "按回车键返回菜单..."
                ;;
            6)
                show_support
                read -p "按回车键返回菜单..."
                ;;
            *)
                warn "请输入正确选项"
                sleep 1
                ;;
        esac
    done
}

main