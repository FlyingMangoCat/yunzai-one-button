#!/bin/bash

# 配置区 ========================================
LOG_FILE="/sdcard/yunzai_install.log"
SUPPORT_GROUP="658720198"
VERSION="2.0.0"

# 全局变量
CURRENT_PLATFORM=""  # 当前平台
CURRENT_OS=""       # 当前操作系统
INSTALLED_YUNZAI=""  # 记录已安装的云崽版本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 日志函数
log() {
    local msg="${1}"
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

# 检测平台
detect_platform() {
    log "检测当前平台..."
    
    # 检测操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        CURRENT_OS="Linux"
        # 检测是否是 Termux
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

# 检查/安装 Docker
check_install_docker() {
    log "检查 Docker 安装状态..."
    
    # 检测是否已安装 Docker
    if command -v docker &> /dev/null; then
        success "Docker 已安装"
        docker --version
        return 0
    fi
    
    warn "Docker 未安装，开始安装..."
    
    case "$CURRENT_PLATFORM" in
        "Termux")
            install_docker_termux
            ;;
        "Linux")
            install_docker_linux
            ;;
        "macOS")
            install_docker_macos
            ;;
        "Windows")
            install_docker_windows
            ;;
        *)
            error "不支持的平台: $CURRENT_PLATFORM"
            ;;
    esac
}

# Termux 安装 Docker
install_docker_termux() {
    log "在 Termux 中安装 Docker..."
    
    # 请求必要权限
    log "请求存储权限和唤醒锁..."
    termux-setup-storage
    termux-wake-lock
    
    # 更新包管理器
    pkg update && pkg upgrade -y
    
    # 安装 Docker 依赖
    pkg install -y git proot docker
    
    # 启动 Docker
    log "启动 Docker 服务..."
    dockerd --host=unix:///data/data/com.termux/files/usr/var/run/docker.sock --iptables=false &
    
    # 等待 Docker 启动
    sleep 5
    
    # 验证 Docker 是否正常运行
    if docker ps &> /dev/null; then
        success "Docker 安装并启动成功"
        docker --version
    else
        error "Docker 启动失败，请检查权限和配置"
    fi
}

# Linux 安装 Docker
install_docker_linux() {
    log "在 Linux 中安装 Docker..."
    
    # 检测 Linux 发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        error "无法检测 Linux 发行版"
    fi
    
    case $DISTRO in
        ubuntu|debian)
            # Ubuntu/Debian 安装 Docker
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            # CentOS/RHEL 安装 Docker
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        fedora)
            # Fedora 安装 Docker
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            error "不支持的 Linux 发行版: $DISTRO"
            ;;
    esac
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    success "Docker 安装完成"
    docker --version
}

# macOS 安装 Docker
install_docker_macos() {
    log "在 macOS 中安装 Docker..."
    
    # 检查是否已安装 Homebrew
    if ! command -v brew &> /dev/null; then
        log "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # 安装 Docker Desktop
    log "安装 Docker Desktop..."
    brew install --cask docker
    
    warn "Docker Desktop 安装完成后，请手动启动 Docker Desktop 应用"
    warn "启动后请重新运行此脚本"
    
    success "Docker Desktop 安装完成"
}

# Windows 安装 Docker
install_docker_windows() {
    log "在 Windows 中安装 Docker..."
    
    warn "Windows 上需要安装 Docker Desktop"
    warn "请访问 https://www.docker.com/products/docker-desktop 下载安装"
    
    echo -e "${YELLOW}请按照以下步骤操作：${NC}"
    echo -e "1. 访问 https://www.docker.com/products/docker-desktop"
    echo -e "2. 下载并安装 Docker Desktop"
    echo -e "3. 启动 Docker Desktop"
    echo -e "4. 安装完成后重新运行此脚本"
    
    read -p "按回车键继续..."
}

# 安装芒果猫版云崽
install_mangocat() {
    log "开始安装芒果猫版云崽..."
    
    # 检查 Docker
    check_install_docker
    
    # 创建数据目录
    mkdir -p yunzai-data yunzai-config redis-data
    
    # 克隆仓库
    YUNZAI_DIR="yunzai-data"
    if [ ! -d "$YUNZAI_DIR" ]; then
        log "克隆芒果猫版云崽仓库..."
        git clone https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git "$YUNZAI_DIR"
        success "芒果猫版云崽克隆完成"
    else
        warn "芒果猫版云崽已存在"
    fi
    
    cd "$YUNZAI_DIR"
    
    # 安装依赖
    log "安装依赖..."
    npm install pnpm -g
    npm install -g cnpm --registry=https://registry.npmmirror.com
    cnpm install
    
    # 安装插件
    log "安装插件..."
    if [ ! -d "plugins/miao-plugin" ]; then
        git clone --depth=1 https://gitcode.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/
    fi
    if [ ! -d "plugins/xiaoyao-cvs-plugin" ]; then
        git clone https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/
    fi
    if [ ! -d "plugins/liulian-plugin" ]; then
        git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/
    fi
    
    # 安装插件依赖
    pnpm install -P
    
    # 记录已安装的版本
    INSTALLED_YUNZAI="芒果猫版云崽"
    
    # 保存安装信息
    echo "INSTALLED_YUNZAI=芒果猫版云崽" > yunzai-config/version.txt
    
    success "芒果猫版云崽安装完成"
    show_start_instructions
}

# 安装喵版云崽
install_miao() {
    log "开始安装喵版云崽..."
    
    # 检查 Docker
    check_install_docker
    
    # 创建数据目录
    mkdir -p yunzai-data yunzai-config redis-data
    
    # 克隆仓库
    YUNZAI_DIR="yunzai-data"
    if [ ! -d "$YUNZAI_DIR" ]; then
        log "克隆喵版云崽仓库..."
        git clone https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git "$YUNZAI_DIR"
        success "喵版云崽克隆完成"
    else
        warn "喵版云崽已存在"
    fi
    
    cd "$YUNZAI_DIR"
    
    # 安装依赖
    log "安装依赖..."
    npm install pnpm -g
    npm install -g cnpm --registry=https://registry.npmmirror.com
    cnpm install
    
    # 安装插件
    log "安装插件..."
    if [ ! -d "plugins/miao-plugin" ]; then
        git clone --depth=1 https://gitcode.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/
    fi
    if [ ! -d "plugins/xiaoyao-cvs-plugin" ]; then
        git clone https://github.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/
    fi
    if [ ! -d "plugins/liulian-plugin" ]; then
        git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/
    fi
    
    # 安装插件依赖
    pnpm install -P
    
    # 记录已安装的版本
    INSTALLED_YUNZAI="喵版云崽"
    
    # 保存安装信息
    echo "INSTALLED_YUNZAI=喵版云崽" > yunzai-config/version.txt
    
    success "喵版云崽安装完成"
    show_start_instructions
}

# 启动云崽
start_yunzai() {
    log "启动云崽..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装云崽"
    fi
    
    # 检查是否已安装
    if [ ! -f "yunzai-config/version.txt" ]; then
        error "未检测到已安装的云崽，请先安装"
    fi
    
    # 读取安装的版本
    INSTALLED_YUNZAI=$(cat yunzai-config/version.txt | grep INSTALLED_YUNZAI | cut -d'=' -f2)
    
    echo -e "${GREEN}检测到已安装: $INSTALLED_YUNZAI${NC}"
    
    # 构建并启动容器
    log "构建 Docker 镜像..."
    docker-compose build
    
    log "启动容器..."
    docker-compose up -d
    
    success "云崽启动成功"
    echo -e "${GREEN}容器已后台运行${NC}"
    echo -e "${YELLOW}查看日志: docker-compose logs -f${NC}"
    echo -e "${YELLOW}停止云崽: docker-compose down${NC}"
}

# 进入容器命令行
enter_container_shell() {
    log "进入容器命令行..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装"
    fi
    
    # 检查容器是否运行
    if ! docker ps | grep -q yunzai-bot; then
        error "云崽容器未运行，请先启动云崽"
    fi
    
    # 进入容器
    docker exec -it yunzai-bot /bin/bash
}

# 显示启动指南
show_start_instructions() {
    echo -e "\n${CYAN}============== 启动指南 ==============${NC}"
    echo -e "${GREEN}首次安装完成后，请执行以下步骤：${NC}"
    echo -e "1. ${YELLOW}配置云崽（修改配置文件）${NC}"
    echo -e "2. ${YELLOW}选择选项3启动云崽${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示帮助信息
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "${GREEN}使用步骤：${NC}"
    echo -e "1. ${GREEN}安装云崽${NC} - 选择选项1或2安装对应版本"
    echo -e "2. ${GREEN}配置云崽${NC} - 修改 yunzai-data/config 目录下的配置文件"
    echo -e "3. ${GREEN}启动云崽${NC} - 选择选项3启动"
    echo -e "4. ${GREEN}调试${NC} - 选择选项4进入容器命令行"
    echo -e "${CYAN}====================================${NC}"
    echo -e "${GREEN}Docker 常用命令：${NC}"
    echo -e "查看日志: ${YELLOW}docker-compose logs -f${NC}"
    echo -e "停止服务: ${YELLOW}docker-compose down${NC}"
    echo -e "重启服务: ${YELLOW}docker-compose restart${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示支持信息
show_support() {
    echo -e "\n${CYAN}============== 技术支持 ==============${NC}"
    echo -e "如使用中遇到问题:"
    echo -e "${GREEN}QQ号: 3598537042${NC}"
    echo -e "${GREEN}昵称: 会飞的芒果猫${NC}"
    echo -e "${GREEN}QQ群: $SUPPORT_GROUP${NC}"
    echo -e "\n添加好友时请说明问题并提供相关截图"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示菜单
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
    
    # 显示已安装的版本
    if [ -f "yunzai-config/version.txt" ]; then
        INSTALLED_VERSION=$(cat yunzai-config/version.txt | grep INSTALLED_YUNZAI | cut -d'=' -f2)
        echo -e "${GREEN}当前已安装: $INSTALLED_VERSION${NC}"
    fi
    
    echo -e "${YELLOW}----------------by 会飞的芒果猫------------------${NC}"
}

# 初始化脚本
init_script() {
    # 清屏
    clear
    
    # 创建日志文件
    echo "=== 云崽安装日志 ===" > "$LOG_FILE"
    log "脚本初始化"
    
    # 显示欢迎信息
    echo -e "${BLUE}"
    echo "==================================================="
    echo "             云崽(喵崽)一键安装脚本  "
    echo "                          Docker容器化版  "
    echo "                                   v$VERSION  "
    echo "==================================================="
    echo -e "${NC}"
    echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
    echo -e "QQ群: ${GREEN}$SUPPORT_GROUP${NC}"
    echo -e "安装指南: ${GREEN}https://b23.tv/pg84aQ0${NC}"
    echo -e "问题反馈: ${GREEN}https://b23.tv/k4k0PDt${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo
    
    # 检测平台
    detect_platform
}

# 主流程
main() {
    init_script
    
    while true; do
        show_menu
        
        # 读取用户输入
        read -p "请输入要执行操作选项：" choice
        
        # 根据用户输入的选项执行相应的函数
        case $choice in
            0)
                log "用户选择: 退出脚本"
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            1) 
                log "用户选择: 安装芒果猫版云崽"
                install_mangocat
                read -p "按回车键返回菜单..."
                ;;
            2) 
                log "用户选择: 安装喵版云崽"
                install_miao
                read -p "按回车键返回菜单..."
                ;;
            3) 
                log "用户选择: 启动云崽"
                start_yunzai
                read -p "按回车键返回菜单..."
                ;;
            4) 
                log "用户选择: 进入容器命令行"
                enter_container_shell
                ;;
            5) 
                log "用户选择: 使用帮助"
                show_help
                read -p "按回车键返回菜单..."
                ;;
            6) 
                log "用户选择: 技术支持"
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

# 启动脚本
main