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
    termux-setup-storage
    termux-wake-lock
    pkg update && pkg upgrade -y
    pkg install -y git proot docker
    log "启动 Docker 服务..."
    dockerd --host=unix:///data/data/com.termux/files/usr/var/run/docker.sock --iptables=false &
    sleep 5
    if docker ps &> /dev/null; then
        success "Docker 安装并启动成功"
        docker --version
    else
        error "Docker 启动失败，请检查权限和配置"
    fi
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
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        fedora)
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
            ;;
        *) error "不支持的 Linux 发行版: $DISTRO" ;;
    esac
    systemctl start docker
    systemctl enable docker
    success "Docker 安装完成"
    docker --version
}

install_docker_macos() {
    log "在 macOS 中安装 Docker..."
    if ! command -v brew &> /dev/null; then
        log "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install --cask docker
    warn "请手动启动 Docker Desktop，然后重新运行此脚本"
    read -p "按回车键继续..."
}

install_docker_windows() {
    log "在 Windows 中安装 Docker..."

    # 尝试 winget 自动安装（Windows 10/11 自带）
    if command -v winget &> /dev/null; then
        log "检测到 winget，自动安装 Docker Desktop..."
        winget install -e --id Docker.DockerDesktop --accept-source-agreements 2>&1 || true
        # 等待安装完成
        sleep 5
        if command -v docker &> /dev/null; then
            success "Docker Desktop 安装成功"
            docker --version
            return 0
        fi
        warn "winget 安装未完成，请检查 Docker Desktop 是否已安装"
    fi

    # 尝试下载安装包静默安装
    if command -v curl &> /dev/null; then
        log "下载 Docker Desktop 安装包..."
        curl -L -o /tmp/DockerDesktopInstaller.exe "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe" 2>/dev/null
        if [ -f /tmp/DockerDesktopInstaller.exe ]; then
            log "静默安装 Docker Desktop..."
            /tmp/DockerDesktopInstaller.exe install --accept-license --quiet 2>/dev/null || true
            rm -f /tmp/DockerDesktopInstaller.exe
            sleep 10
            if command -v docker &> /dev/null; then
                success "Docker Desktop 安装成功"
                docker --version
                return 0
            fi
        fi
    fi

    # 以上都失败，提示手动安装
    echo -e "${YELLOW}未能自动安装 Docker Desktop，请手动操作：${NC}"
    echo -e "1. 访问 https://www.docker.com/products/docker-desktop"
    echo -e "2. 下载并安装 Docker Desktop"
    echo -e "3. 启动 Docker Desktop"
    echo -e "4. 安装完成后重新运行此脚本"
    read -p "按回车键继续..."
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
        docker-compose build
        log "启动容器..."
        docker-compose up -d
        sleep 3
        echo -e "${GREEN}容器环境配置完成${NC}"
    elif ! container_running; then
        log "启动容器..."
        docker-compose up -d
        sleep 3
    fi
}

# ---------- 安装云崽（通用流程，每步验证） ----------
install_yunzai() {
    local repo_url="$1"
    local version_name="$2"

    echo -e "\n${CYAN}========== 开始安装 $version_name ==========${NC}"

    # 1. 获取权限
    get_permissions

    # 2. 检测环境
    detect_platform

    # 3. 检查 Docker
    check_install_docker

    # 4. 创建总目录
    mkdir -p "$YUNZAI_DIR" || error "创建目录 $YUNZAI_DIR 失败"

    # 5. 确保容器在运行
    ensure_container
    sleep 2
    if ! container_running; then
        error "容器启动失败，请检查 Docker 状态"
    fi

    # 6. 在容器内克隆代码
    if ! docker_exec "test -f /app/package.json" 2>/dev/null; then
        log "克隆 $version_name 代码..."
        docker_exec "cd /app && git clone $repo_url ." || error "代码克隆失败，请检查网络连接"
        # 验证克隆是否成功
        docker_exec "test -f /app/package.json" || error "代码克隆后未检测到 package.json"
        success "代码克隆完成"
    else
        log "云崽代码已存在"
    fi

    # 7. 装依赖
    log "安装依赖..."
    docker_exec "cd /app && npm install pnpm -g 2>/dev/null; npm install -g cnpm --registry=https://registry.npmmirror.com 2>/dev/null; cnpm install" || warn "依赖安装有警告，继续..."
    # 验证依赖是否安装成功
    docker_exec "test -d /app/node_modules" || error "依赖安装失败，node_modules 不存在"
    success "依赖安装完成"

    # 8. 装插件（每装一个验证一个）
    log "安装插件..."
    if ! docker_exec "test -d /app/plugins/miao-plugin" 2>/dev/null; then
        docker_exec "cd /app && git clone --depth=1 https://gitcode.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/" || warn "喵喵插件克隆失败"
        docker_exec "test -d /app/plugins/miao-plugin" && log "  - 喵喵插件 安装完成" || warn "  - 喵喵插件 未检测到"
    fi
    if ! docker_exec "test -d /app/plugins/xiaoyao-cvs-plugin" 2>/dev/null; then
        docker_exec "cd /app && git clone https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/" || warn "图鉴插件克隆失败"
        docker_exec "test -d /app/plugins/xiaoyao-cvs-plugin" && log "  - 图鉴插件 安装完成" || warn "  - 图鉴插件 未检测到"
    fi
    if ! docker_exec "test -d /app/plugins/liulian-plugin" 2>/dev/null; then
        docker_exec "cd /app && git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/" || warn "榴莲插件克隆失败"
        docker_exec "test -d /app/plugins/liulian-plugin" && log "  - 榴莲插件 安装完成" || warn "  - 榴莲插件 未检测到"
    fi

    # 9. 装插件依赖
    log "安装插件依赖..."
    docker_exec "cd /app && pnpm install -P" || warn "插件依赖安装有警告，继续..."
    docker_exec "test -d /app/node_modules" || error "插件依赖安装后 node_modules 丢失"
    success "插件依赖安装完成"

    # 10. 启动云崽
    log "启动 $version_name ..."
    docker_exec "cd /app && nohup node app > /app/yunzai.log 2>&1 &"
    sleep 2
    # 验证是否启动成功（检查进程）
    docker_exec "pgrep -f 'node app' > /dev/null" && \
        echo -e "${GREEN}$version_name 已启动！${NC}" || \
        warn "云崽可能未成功启动，请手动检查: docker exec $CONTAINER_NAME tail -f /app/yunzai.log"
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