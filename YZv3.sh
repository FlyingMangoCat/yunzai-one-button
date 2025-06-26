#!/bin/bash

# 配置区 ========================================
LOG_FILE="/sdcard/yunzai_install.log"
TERMUX_HOME="$HOME"
INSTALL_DIR="$TERMUX_HOME/Termux-Linux/Ubuntu"
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
    if [ ! -d "$TERMUX_HOME/ubuntu-in-termux" ]; then
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
    sed -i 's/ports.ubuntu.com/mirrors.bfsu.edu.cn/g' $INSTALL_DIR/etc/apt/sources.list
    apt update && apt install curl -y
    
    success "容器环境安装完成"
}

# 安装FFmpeg
install_ffmpeg() {
    log "开始安装FFmpeg..."
    
    apt update && apt upgrade -y
    apt install git -y
    
    log "克隆FFmpeg仓库..."
    git clone https://gitee.com/mirrors/ffmpeg.git ~/ffmpeg &
    show_progress "克隆FFmpeg"
    
    log "安装FFmpeg依赖..."
    apt install make libgmp3-dev pkg-config gnutls-bin -y
    apt install libnuma-dev build-essential yasm nasm -y
    apt install libaom-dev libass-dev libbluray-dev libfdk-aac-dev -y
    apt install libmp3lame-dev libopencore-amrnb-dev libopencore-amrwb-dev -y
    apt install libopenmpt-dev libopus-dev libshine-dev libsnappy-dev -y
    apt install libsoxr-dev libspeex-dev libtheora-dev libtwolame-dev -y
    apt install libvo-amrwbenc-dev libvpx-dev libwavpack-dev libwebp-dev -y
    apt install libx264-dev libx265-dev libxvidcore-dev liblzma-dev -y
    
    log "配置FFmpeg..."
    cd ~/ffmpeg
    ./configure --prefix=/usr/local --pkg-config-flags=--static --enable-gpl --enable-version3 \
        --enable-libass --enable-libbluray --enable-libmp3lame --enable-libopencore-amrnb \
        --enable-libopencore-amrwb --enable-libopus --enable-libshine --enable-libsnappy \
        --enable-libsoxr --enable-libtheora --enable-libtwolame --enable-libwebp --enable-libx264 \
        --enable-libx265 --enable-libxml2 --enable-lzma --enable-zlib --enable-gmp \
        --enable-libvorbis --enable-libvo-amrwbenc --enable-libspeex --enable-libxvid \
        --enable-libaom --enable-libopenmpt --enable-libfdk-aac --enable-nonfree
    
    log "编译FFmpeg..."
    make -j2 &
    show_progress "编译FFmpeg"
    
    log "安装FFmpeg..."
    make install
    mv ffmpeg /usr/local/bin/
    mv ffprobe /usr/local/bin/
    
    success "FFmpeg安装完成"
}

# 安装Python 3.10
install_python310() {
    log "开始安装Python 3.10..."
    
    apt update && apt upgrade -y
    apt install git -y
    
    log "克隆Python源码..."
    git clone https://gitee.com/paimon114514/python3.10.8.git ~/Python &
    show_progress "克隆Python"
    
    cd ~/Python/
    tar -zxvf Python-3.10.8.tgz -C ~
    cd ~/Python-3.10.8/
    
    log "安装Python依赖..."
    apt install make -y
    apt-get install zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev \
        libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev \
        liblzma-dev libffi-dev libc6-dev -y
    
    log "配置Python..."
    ./configure
    
    log "编译Python..."
    make -j2 &
    show_progress "编译Python"
    
    log "安装Python..."
    make install
    ln -s /usr/local/bin/python3 /usr/local/bin/python
    ln -s /usr/local/bin/pip3 /usr/local/bin/pip
    
    log "优化pip源..."
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
    pip install poetry
    
    log "清理临时文件..."
    rm -rf ~/Python/
    rm -rf ~/Python-3.10.8/
    
    success "Python 3.10安装完成"
}

# 配置基础环境
configure_environment() {
    log "开始配置基础环境..."
    
    # 更新系统
    apt update && apt upgrade -y
    
    # 安装Node.js
    if ! command -v node &> /dev/null; then
        log "安装Node.js..."
        curl -sL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        success "Node.js安装完成"
    else
        warn "Node.js已安装，跳过安装"
    fi
    
    # 安装Redis
    if ! command -v redis-server &> /dev/null; then
        log "安装Redis..."
        apt-get install redis -y
        redis-server --daemonize yes
        success "Redis安装并启动成功"
    else
        warn "Redis已安装，跳过安装"
    fi
    
    # 安装必要组件
    log "安装浏览器和字体..."
    apt install chromium-browser -y
    apt install -y --force-yes --no-install-recommends fonts-wqy-microhei
    apt install git -y
    
    # 安装FFmpeg和Python
    install_ffmpeg
    install_python310
    
    success "基础环境配置完成"
}

# 安装通用插件
install_plugins() {
    local yunzai_dir="$1"
    
    log "开始安装插件到: $yunzai_dir"
    
    # 喵喵插件
    if [ ! -d "$yunzai_dir/plugins/miao-plugin" ]; then
        log "安装喵喵插件..."
        git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git "$yunzai_dir/plugins/miao-plugin/"
    else
        warn "喵喵插件已存在，跳过安装"
    fi
    
    # 图鉴插件
    if [ ! -d "$yunzai_dir/plugins/xiaoyao-cvs-plugin" ]; then
        log "安装图鉴插件..."
        git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git "$yunzai_dir/plugins/xiaoyao-cvs-plugin/"
    else
        warn "图鉴插件已存在，跳过安装"
    fi
    
    # 榴莲插件
    if [ ! -d "$yunzai_dir/plugins/liulian-plugin" ]; then
        log "安装榴莲插件..."
        git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git "$yunzai_dir/plugins/liulian-plugin/"
    else
        warn "榴莲插件已存在，跳过安装"
    fi
    
    # 安装依赖
    log "安装插件依赖..."
    cd "$yunzai_dir"
    pnpm install -P
    
    success "插件安装完成"
}

# 安装芒果猫版云崽
install_mangocat_yunzai() {
    local yunzai_dir="$TERMUX_HOME/MangoCat-Yunzai"
    
    log "开始安装芒果猫版云崽..."
    
    # 克隆仓库
    if [ ! -d "$yunzai_dir" ]; then
        log "克隆芒果猫版云崽仓库..."
        git clone https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git "$yunzai_dir"
        success "芒果猫版云崽克隆完成"
    else
        warn "芒果猫版云崽已存在，跳过克隆"
    fi
    
    # 安装依赖
    log "安装PNPM和依赖..."
    cd "$yunzai_dir"
    npm install pnpm -g
    npm install -g cnpm --registry=https://registry.npmmirror.com
    cnpm install
    
    # 安装插件
    install_plugins "$yunzai_dir"
    
    success "芒果猫版云崽安装完成"
    show_start_instructions
}

# 安装喵版云崽
install_miao_yunzai() {
    local yunzai_dir="$TERMUX_HOME/Miao-Yunzai"
    
    log "开始安装喵版云崽..."
    
    # 克隆仓库
    if [ ! -d "$yunzai_dir" ]; then
        log "克隆喵版云崽仓库..."
        git clone --depth=1 https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git "$yunzai_dir"
        success "喵版云崽克隆完成"
    else
        warn "喵版云崽已存在，跳过克隆"
    fi
    
    # 安装依赖
    log "安装PNPM和依赖..."
    cd "$yunzai_dir"
    npm install pnpm -g
    npm install -g cnpm --registry=https://registry.npmmirror.com
    cnpm install
    
    # 安装插件
    install_plugins "$yunzai_dir"
    
    success "喵版云崽安装完成"
    show_start_instructions
}

# 安装依赖
install_dependencies() {
    log "开始安装依赖..."
    
    # 检查并安装芒果猫版依赖
    if [ -d "$TERMUX_HOME/MangoCat-Yunzai" ]; then
        log "为芒果猫版安装依赖..."
        cd "$TERMUX_HOME/MangoCat-Yunzai"
        pnpm install -P
    fi
    
    # 检查并安装喵版依赖
    if [ -d "$TERMUX_HOME/Miao-Yunzai" ]; then
        log "为喵版安装依赖..."
        cd "$TERMUX_HOME/Miao-Yunzai"
        pnpm install -P
    fi
    
    success "依赖安装完成"
}

# 启动云崽
start_yunzai() {
    log "启动云崽服务..."
    
    # 启动Ubuntu环境
    cd "$TERMUX_HOME/ubuntu-in-termux"
    ./startubuntu.sh
    
    # 启动Redis
    redis-server --save 900 1 --save 300 10 --daemonize yes
    
    # 启动芒果猫版
    if [ -d "$TERMUX_HOME/MangoCat-Yunzai" ]; then
        log "启动芒果猫版云崽..."
        cd "$TERMUX_HOME/MangoCat-Yunzai"
        node app &
    fi
    
    # 启动喵版
    if [ -d "$TERMUX_HOME/Miao-Yunzai" ]; then
        log "启动喵版云崽..."
        cd "$TERMUX_HOME/Miao-Yunzai"
        node app &
    fi
    
    success "云崽已启动"
    show_quick_start_guide
}

# 显示启动指南
show_start_instructions() {
    echo -e "\n${CYAN}============== 启动指南 ==============${NC}"
    echo -e "${GREEN}退出后台重进后输入以下命令启动云崽:${NC}"
    echo -e "${YELLOW}cd ~/ubuntu-in-termux${NC}"
    echo -e "${YELLOW}./startubuntu.sh${NC}"
    echo -e "${YELLOW}redis-server --daemonize yes --save 900 1 --save 300 10${NC}"
    echo -e "${YELLOW}cd ~/Miao-Yunzai${NC} (或 cd ~/MangoCat-Yunzai)"
    echo -e "${YELLOW}node app${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示快速启动指南
show_quick_start_guide() {
    echo -e "\n${CYAN}============ 快速启动指南 ============${NC}"
    echo -e "${GREEN}下次启动只需执行以下步骤:${NC}"
    echo -e "1. ${YELLOW}cd ~/ubuntu-in-termux${NC}"
    echo -e "2. ${YELLOW}./startubuntu.sh${NC}"
    echo -e "3. ${YELLOW}redis-server --daemonize yes${NC}"
    echo -e "4. ${YELLOW}cd ~/Miao-Yunzai${NC} (或 MangoCat-Yunzai)"
    echo -e "5. ${YELLOW}node app${NC}"
    echo -e "${CYAN}====================================${NC}\n"
}

# 显示帮助信息
show_help() {
    echo -e "\n${CYAN}============== 使用帮助 ==============${NC}"
    echo -e "${GREEN}初次安装请按照以下顺序操作:${NC}"
    echo -e "1. ${GREEN}安装容器${NC} - 创建Linux环境"
    echo -e "2. ${GREEN}配置环境${NC} - 安装Node.js, Redis等依赖"
    echo -e "3. ${GREEN}选择云崽版本${NC} - 安装芒果猫版或喵版"
    echo -e "4. ${GREEN}安装依赖${NC} - 安装项目依赖"
    echo -e "5. ${GREEN}启动云崽${NC} - 启动机器人服务"
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
    echo -e "${YELLOW}----------------------菜单---------------------${NC}"
    echo -e "${GREEN}             请选择要执行的操作：${NC}"
    echo -e "                1. 安装容器${NC}"
    echo -e "                2. 配置环境${NC}"
    echo -e "                3. 安装芒果猫版云崽${NC}"
    echo -e "                4. 安装喵崽${NC}"
    echo -e "                5. 安装依赖${NC}"
    echo -e "                6. 启动云崽${NC}"
    echo -e "                7. 使用帮助${NC}"
    echo -e "                8. 我不会!${NC}"
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
            1) 
                log "用户选择: 安装容器"
                install_container
                read -p "按回车键返回菜单..."
                ;;
            2) 
                log "用户选择: 配置环境"
                configure_environment
                read -p "按回车键返回菜单..."
                ;;
            3) 
                log "用户选择: 安装芒果猫版云崽"
                install_mangocat_yunzai
                read -p "按回车键返回菜单..."
                ;;
            4) 
                log "用户选择: 安装喵版云崽"
                install_miao_yunzai
                read -p "按回车键返回菜单..."
                ;; 
            5) 
                log "用户选择: 安装依赖"
                install_dependencies
                read -p "按回车键返回菜单..."
                ;;
            6) 
                log "用户选择: 启动云崽"
                start_yunzai
                read -p "按回车键返回菜单..."
                ;;
            7) 
                log "用户选择: 使用帮助"
                echo -e "\n${GREEN}初次安装请按照以下顺序进行操作："
                echo -e "  第一步，输入阿拉伯数字1，安装容器。"
                echo -e "  第二步，输入阿拉伯数字2，配置环境。"
                echo -e "  第三步，输入阿拉伯数字3或4安装对应的云崽版本。"
                echo -e "  第四步，输入阿拉伯数字5，安装依赖。"
                echo -e "  第五步，输入阿拉伯数字6，启动云崽。"
                echo -e "  你学废了吗？${NC}\n"
                read -p "按回车键返回菜单..."
                ;;
            8) 
                log "用户选择: 技术支持"
                echo "请使用您会使用的电子通讯产品安装并打开腾讯QQ登录，"
                echo "点击搜索栏输入3598537042，"
                echo "输入完成后请点击搜索，添加用户"会飞的芒果猫"并耐心等待，"
                echo "通过好友后，请您说出您的问题并附对应截图（您所遇到问题界面的截图），并耐心等待即可"
                echo "等待有回复后，请您一定按照要求进行操作"
                echo "谢谢配合"
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