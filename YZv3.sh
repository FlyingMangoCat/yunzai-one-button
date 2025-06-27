#!/bin/bash

# 配置区 ========================================
LOG_FILE="/sdcard/yunzai_install.log"
TERMUX_HOME="$HOME"
UBUNTU_DIR="$TERMUX_HOME/ubuntu-in-termux"
SUPPORT_GROUP="658720198"
VERSION="1.6.0"

# 全局变量
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
    
    # 请求必要权限
    log "请求存储权限和唤醒锁..."
    termux-setup-storage
    termux-wake-lock
    
    # 安装基础依赖
    pkg update && pkg upgrade -y
    pkg install git proot python -y
    
    # 安装Ubuntu环境
    if [ ! -d "$UBUNTU_DIR" ]; then
        log "克隆Ubuntu环境..."
        git clone --depth=1 -b ubuntu22.04 https://gitee.com/KudouShinnyan/ubuntu-in-termux.git "$UBUNTU_DIR"
        
        if [ -d "$UBUNTU_DIR" ]; then
            cd "$UBUNTU_DIR"
            chmod +x ubuntu.sh
            ./ubuntu.sh -y
            success "Ubuntu容器安装完成"
            
            # 配置Ubuntu源
            log "配置Ubuntu国内源..."
            sed -i 's/ports.ubuntu.com/mirrors.bfsu.edu.cn/g' $TERMUX_HOME/Termux-Linux/Ubuntu/etc/apt/sources.list
            
            # 显示进入容器的提示
            echo -e "\n${GREEN}容器安装完成！请选择以下操作：${NC}"
            echo -e "1. ${YELLOW}选择选项2直接进入容器${NC}"
            echo -e "2. ${YELLOW}手动进入容器: cd ~/ubuntu-in-termux && ./startubuntu.sh${NC}"
            echo -e "3. ${YELLOW}进入容器后，重新运行本脚本选择后续操作${NC}"
        else
            error "Ubuntu容器安装失败"
        fi
    else
        warn "Ubuntu容器已存在，跳过安装"
        echo -e "${YELLOW}Ubuntu容器已存在，请选择选项2进入容器${NC}"
    fi
}

# 进入容器
enter_container() {
    if [ ! -d "$UBUNTU_DIR" ]; then
        warn "容器未安装，请先选择选项1安装容器"
        return
    fi
    
    if [ ! -f "$UBUNTU_DIR/startubuntu.sh" ]; then
        error "找不到启动脚本: $UBUNTU_DIR/startubuntu.sh"
    fi
    
    echo -e "${GREEN}正在进入Ubuntu容器...${NC}"
    echo -e "${YELLOW}进入容器后，请重新运行本脚本选择后续操作${NC}"
    sleep 2
    
    # 进入容器
    cd "$UBUNTU_DIR"
    ./startubuntu.sh
}

# 容器内安装基础环境
install_container_env() {
    log "开始在容器内安装基础环境..."
    
    # 更新系统
    dpkg --configure -a
    apt update && apt upgrade -y
    
    # 安装Node.js
    log "安装Node.js..."
    curl -sL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install nodejs -y
    apt-get install nsolid -y
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
 
    # 安装git
    log "安装git..."
    apt install git -y

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
        
        # 记录已安装的版本
        INSTALLED_YUNZAI="$yunzai_type"
    else
        warn "$yunzai_type 已存在，跳过克隆"
        INSTALLED_YUNZAI="$yunzai_type"
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
    
    success "$yunzai_type 安装完成"
    show_start_instructions
}

# 启动云崽
start_yunzai() {
    log "启动云崽服务..."
    local in_container=0
    if [ -f /etc/os-release ] && grep -q 'Ubuntu' /etc/os-release; then
        in_container=1
    fi

    # 启动容器环境
    if [ $in_container -eq 0 ]; then
        if [ ! -d "$UBUNTU_DIR" ]; then
            error "容器未安装，请先安装容器"
        fi
    else
    
    # 进入容器
    echo -e "${GREEN}正在启动容器环境...${NC}"
    cd "$UBUNTU_DIR"
    ./startubuntu.sh
    groupadd -g 3003 group3003
    groupadd -g 9997 group9997
    groupadd -g 20323 group20323
    groupadd -g 50323 group50323
    groupadd -g 99909997 group99909997
    
    # 启动Redis
    redis-server --daemonize yes --save 900 1 --save 300 10
    
    # 根据安装的版本启动云崽
    if [ -d "/root/MangoCat-Yunzai" ] && [ "$INSTALLED_YUNZAI" = "芒果猫版云崽" ]; then
        echo -e "${GREEN}正在启动芒果猫版云崽...${NC}"
        cd /root/MangoCat-Yunzai
        node app
    elif [ -d "/root/Miao-Yunzai" ] && [ "$INSTALLED_YUNZAI" = "喵版云崽" ]; then
        echo -e "${GREEN}正在启动喵版云崽...${NC}"
        cd /root/Miao-Yunzai
        node app
    else
        warn "未找到云崽安装目录，请先安装云崽"
    fi
}

# 显示启动指南（根据安装的版本）
show_start_instructions() {
    echo -e "\n${CYAN}============== 启动指南 ==============${NC}"
    
    if [ "$INSTALLED_YUNZAI" = "芒果猫版云崽" ]; then
        echo -e "${GREEN}芒果猫版云崽启动命令:${NC}"
        echo -e "${YELLOW}cd ~/ubuntu-in-termux${NC}"
        echo -e "${YELLOW}./startubuntu.sh${NC}"
        echo -e "${YELLOW}redis-server --daemonize yes --save 900 1 --save 300 10${NC}"
        echo -e "${YELLOW}cd ~/MangoCat-Yunzai${NC}"
        echo -e "${YELLOW}node app${NC}"
    elif [ "$INSTALLED_YUNZAI" = "喵版云崽" ]; then
        echo -e "${GREEN}喵版云崽启动命令:${NC}"
        echo -e "${YELLOW}cd ~/ubuntu-in-termux${NC}"
        echo -e "${YELLOW}./startubuntu.sh${NC}"
        echo -e "${YELLOW}redis-server --daemonize yes --save 900 1 --save 300 10${NC}"
        echo -e "${YELLOW}cd ~/Miao-Yunzai${NC}"
        echo -e "${YELLOW}node app${NC}"
    else
        echo -e "${YELLOW}请先安装云崽版本${NC}"
    fi
    
    echo -e "${CYAN}====================================${NC}"
    echo -e "${GREEN}提示：下次启动可以直接选择选项6一键启动${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示帮助信息
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "${GREEN}初次安装请按照以下顺序操作:${NC}"
    echo -e "1. ${GREEN}安装容器${NC} - 选择选项1"
    echo -e "2. ${GREEN}进入容器${NC} - 选择选项2"
    echo -e "3. ${GREEN}在容器内配置环境${NC} - 选择选项3"
    echo -e "4. ${GREEN}在容器内安装云崽${NC} - 选择选项4或5"
    echo -e "5. ${GREEN}启动云崽${NC} - 选择选项6"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示支持信息
show_support() {
    echo -e "\n${CYAN}============== 技术支持 ==============${NC}"
    echo -e "如使用中遇到问题:"
    echo -e "${GREEN}QQ号: 3598537042${NC}"
    echo -e "${GREEN}昵称: 会飞的芒果猫${NC}"
    echo -e "\n添加好友时请说明问题并提供相关截图"
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
        echo -e "                0. 退出脚本${NC}"
        echo -e "                1. 安装容器${NC}"
        echo -e "                2. 进入容器${NC}"
        echo -e "                6. 启动云崽${NC}"
        echo -e "                7. 使用帮助${NC}"
        echo -e "                8. 技术支持${NC}"
        echo -e "${GREEN}注意：安装容器后请选择选项2进入容器${NC}"
    else
        # 容器内菜单
        echo -e "                0. 退出脚本${NC}"
        echo -e "                3. 配置环境${NC}"
        echo -e "                4. 安装芒果猫版云崽${NC}"
        echo -e "                5. 安装喵版云崽${NC}"
        echo -e "                6. 启动云崽${NC}"
        echo -e "                7. 使用帮助${NC}"
        echo -e "                8. 技术支持${NC}"
        echo -e "${GREEN}注意：当前在Ubuntu容器内${NC}"
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
    echo "                                   v$VERSION  "
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
        
        # 检测已安装的云崽版本
        if [ -d "/root/MangoCat-Yunzai" ]; then
            INSTALLED_YUNZAI="芒果猫版云崽"
        elif [ -d "/root/Miao-Yunzai" ]; then
            INSTALLED_YUNZAI="喵版云崽"
        fi
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
            0)
                log "用户选择: 退出脚本"
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
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
                if [ $in_container -eq 1 ]; then
                    warn "您已在容器内"
                else
                    log "用户选择: 进入容器"
                    enter_container
                fi
                read -p "按回车键返回菜单..."
                ;;
            3) 
                if [ $in_container -eq 0 ]; then
                    warn "此操作需要在容器内执行"
                else
                    log "用户选择: 配置环境"
                    install_container_env
                fi
                read -p "按回车键返回菜单..."
                ;;
            4) 
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
            5) 
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
            6) 
                log "用户选择: 启动云崽"
                start_yunzai
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