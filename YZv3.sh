#!/bin/bash

# 配置区 ========================================
LOG_FILE="/sdcard/yunzai_install.log"
TERMUX_HOME="$HOME"
UBUNTU_DIR="$TERMUX_HOME/ubuntu-in-termux"
SUPPORT_GROUP="658720198"

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

# 进度显示
show_progress() {
    local pid=$!
    local spin=('-' '\' '|' '/')
    local i=0
    
    echo -n "$1 "
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        echo -ne "${spin[$i]}"
        sleep 0.1
        echo -ne "\b"
    done
    echo -e "\n"
}

# 安装容器环境
install_container() {
    log "开始安装容器环境..."
    
    # 安装基础依赖
    pkg update && pkg upgrade -y
    pkg install git proot python -y
    
    # 安装Ubuntu环境
    if [ ! -d "$UBUNTU_DIR" ]; then
        log "克隆Ubuntu环境..."
        git clone --depth=1 -b ubuntu22.04 https://gitee.com/KudouShinnyan/ubuntu-in-termux.git &
        show_progress "克隆Ubuntu环境"
        
        cd ubuntu-in-termux
        chmod +x ubuntu.sh
        ./ubuntu.sh -y &
        show_progress "安装Ubuntu容器"
        success "Ubuntu容器安装完成"
    else
        warn "Ubuntu容器已存在，跳过安装"
    fi
    
    # 配置Ubuntu源
    log "配置Ubuntu国内源..."
    sed -i 's/ports.ubuntu.com/mirrors.bfsu.edu.cn/g' $TERMUX_HOME/Termux-Linux/Ubuntu/etc/apt/sources.list
    
    # 显示进入容器的提示
    echo -e "\n${GREEN}容器安装完成！请按照以下步骤操作：${NC}"
    echo -e "1. ${YELLOW}输入命令: cd ~/ubuntu-in-termux${NC}"
    echo -e "2. ${YELLOW}输入命令: ./startubuntu.sh 进入Ubuntu容器${NC}"
    echo -e "3. ${YELLOW}在容器内，输入命令: apt update && apt install curl && bash <(curl -sL https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)${NC}"
    echo -e "4. ${YELLOW}然后选择后续操作 (配置环境、安装云崽等)${NC}"
    echo -e "\n${CYAN}注意：后续操作需要在Ubuntu容器内执行${NC}"
}

# 容器内安装基础环境
install_container_env() {
    log "开始在容器内安装基础环境..."
    
    # 更新系统
    apt update && apt upgrade -y
    
    # 安装Node.js
    log "安装Node.js..."
    curl -sL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    success "Node.js安装完成"
    
    # 安装Redis
    log "安装Redis..."
    apt-get install redis -y
    redis-server --daemonize yes
    success "Redis安装并启动成功"
    
    # 安装必要组件
    log "安装浏览器和字体..."
    apt install chromium-browser -y
    apt install -y --force-yes --no-install-recommends fonts-wqy-microhei
    
    success "基础环境配置完成"
}

# 容器内安装云崽
install_yunzai() {
    local yunzai_type="$1"
    local yunzai_dir="$2"
    local repo_url="$3"
    
    log "开始安装 $yunzai_type..."
    
    # 克隆仓库
    if [ ! -d "$yunzai_dir" ]; then
        log "克隆仓库..."
        git clone $repo_url $yunzai_dir
        success "$yunzai_type 克隆完成"
    else
        warn "$yunzai_type 已存在，跳过克隆"
    fi
    
    # 安装依赖
    log "安装依赖..."
    cd $yunzai_dir
    npm install pnpm -g
    npm install -g cnpm --registry=https://registry.npmmirror.com
    cnpm install
    
    # 安装插件
    log "安装插件..."
    if [ ! -d "plugins/miao-plugin" ]; then
        git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/
    fi
    if [ ! -d "plugins/xiaoyao-cvs-plugin" ]; then
        git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/
    fi
    if [ ! -d "plugins/liulian-plugin" ]; then
        git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/
    fi
    
    # 安装插件依赖
    pnpm install -P
    
    success "$yunzai_type 安装完成"
    show_start_instructions
}

# 启动云崽
start_yunzai() {
    log "启动云崽服务..."
    
    # 检查并启动芒果猫版
    if [ -d "/root/MangoCat-Yunzai" ]; then
        cd /root/MangoCat-Yunzai
        node app &
        success "芒果猫版云崽已启动"
    fi
    
    # 检查并启动喵版
    if [ -d "/root/Miao-Yunzai" ]; then
        cd /root/Miao-Yunzai
        node app &
        success "喵版云崽已启动"
    fi
}

# 显示启动指南
show_start_instructions() {
    echo -e "\n${CYAN}============== 启动指南 ==============${NC}"
    echo -e "${GREEN}下次启动云崽只需执行以下命令:${NC}"
    echo -e "${YELLOW}cd ~/Miao-Yunzai${NC} (或 cd ~/MangoCat-Yunzai)"
    echo -e "${YELLOW}node app${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示帮助信息
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "${GREEN}初次安装请按照以下顺序操作:${NC}"
    echo -e "1. ${GREEN}安装容器${NC} - 创建Linux环境"
    echo -e "2. ${GREEN}进入容器${NC} - 执行: cd ~/ubuntu-in-termux && ./startubuntu.sh"
    echo -e "3. ${GREEN}在容器内配置环境${NC} - 选择选项2"
    echo -e "4. ${GREEN}在容器内安装云崽${NC} - 选择选项3或4"
    echo -e "5. ${GREEN}在容器内启动云崽${NC} - 选择选项6"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示支持信息
show_support() {
    echo -e "\n${CYAN}============== 技术支持 ==============${NC}"
    echo -e "如使用中遇到问题:"
    echo -e "${GREEN}QQ号: 3598537042${NC}"
    echo -e "${GREEN}昵称: 会飞的芒果猫${NC}"
    echo -e "\n添加好友时请说明问题并提供日志或相关截图"
    echo -e "${CYAN}====================================${NC}\n"
}

# 主菜单
show_menu() {
    # 检测是否在容器内
    local in_container=0
    if [ -f /etc/os-release ] && grep -q 'Ubuntu' /etc/os-release; then
        in_container=1
    fi

    echo -e "${YELLOW}----------------------菜单---------------------${NC}"
    echo -e "${GREEN}             请选择要执行的操作：${NC}"
    
    if [ $in_container -eq 0 ]; then
        # Termux 环境菜单
        echo -e "                1. 安装容器${NC}"
        echo -e "                7. 使用帮助${NC}"
        echo -e "                8. 技术支持${NC}"
        echo -e "${GREEN}注意：安装容器后需要进入容器内执行后续操作${NC}"
    else
        # 容器内菜单
        echo -e "                2. 配置环境${NC}"
        echo -e "                3. 安装芒果猫版云崽${NC}"
        echo -e "                4. 安装喵崽${NC}"
        echo -e "                5. 安装插件依赖${NC}"
        echo -e "                6. 启动云崽${NC}"
        echo -e "                7. 使用帮助${NC}"
        echo -e "                8. 技术支持${NC}"
        echo -e "${GREEN}注意：当前在Ubuntu容器内${NC}"
    fi

    echo -e "${GREEN}注意！初次安装请按照以下顺序：1，2，3/4，5，6${NC}"
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
    echo "                                   v1.2.0  "
    echo "==================================================="
    echo -e "${NC}"
    echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
    echo -e "QQ群: ${GREEN}$SUPPORT_GROUP${NC}"
    echo -e "安装指南: ${GREEN}https://b23.tv/pg84aQ0${NC}"
    echo -e "问题反馈: ${GREEN}https://b23.tv/k4k0PDt${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo
    
    # 检测是否在容器内
    if [ -f /etc/os-release ] && grep -q 'Ubuntu' /etc/os-release; then
        echo -e "${GREEN}当前环境: Ubuntu容器${NC}"
    else
        echo -e "${GREEN}当前环境: Termux${NC}"
    fi
}

# 主流程
main() {
    init_script
    
    while true; do
        show_menu
        
        # 读取用户输入
        read -p "请输入要执行操作选项：" choice
        
        # 检测是否在容器内
        local in_container=0
        if [ -f /etc/os-release ] && grep -q 'Ubuntu' /etc/os-release; then
            in_container=1
        fi

        # 根据用户输入的选项执行相应的函数
        case $choice in
            1) 
                if [ $in_container -eq 1 ]; then
                    warn "您已在容器内，无需安装容器"
                else
                    log "用户选择: 安装容器"
                    install_container
                fi
                read -p "按回车键返回菜单..."
                ;;
            2) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 配置环境"
                    install_container_env
                fi
                read -p "按回车键返回菜单..."
                ;;
            3) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 安装芒果猫版云崽"
                    install_yunzai \
                        "芒果猫版云崽" \
                        "/root/MangoCat-Yunzai" \
                        "https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git"
                fi
                read -p "按回车键返回菜单..."
                ;;
            4) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 安装喵版云崽"
                    install_yunzai \
                        "喵版云崽" \
                        "/root/Miao-Yunzai" \
                        "https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git"
                fi
                read -p "按回车键返回菜单..."
                ;; 
            5) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 安装插件依赖"
                    if [ -d "/root/MangoCat-Yunzai" ]; then
                        cd /root/MangoCat-Yunzai
                        pnpm install -P
                    fi
                    if [ -d "/root/Miao-Yunzai" ]; then
                        cd /root/Miao-Yunzai
                        pnpm install -P
                    fi
                    success "插件依赖安装完成"
                fi
                read -p "按回车键返回菜单..."
                ;;
            6) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 启动云崽"
                    start_yunzai
                fi
                read -p "按回车键返回菜单..."
                ;;
            7) 
                log "用户选择: 使用帮助"
                show_help
                read -p "按回车键返回菜单..."
                ;;
            8) 
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