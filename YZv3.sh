#!/bin/bash

function container {
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/environment)
apt install update
apt install curl -y
echo 'a'
}
function continue {
echo '正在更新apt，请稍后……'
apt update
apt upgrade -y

echo '正在安装nodejs，请稍后……'
curl -sL https://deb.nodesource.com/setup_17.x | bash -
apt-get install -y nodejs
echo '安装完成'

echo '正在安装并启动redis，请稍后……'
apt-get install redis -y

redis-server --daemonize yes
echo '安装并启动成功'

echo '正在安装chromuim，中文字体等，请稍后……'
apt install chromium-browser -y
apt install -y --force-yes --no-install-recommends fonts-wqy-microhei
apt install git -y
}

function MangoCat-Yunzai {
echo '正在克隆云崽……'
if [ ! -d "$HOME/Yunzai-Bot" ]; 
then 
    git clone https://gitee.com/huifeidemangguomao/MangoCat-Yunzai.git
    if [ ! -d "$HOME/MangoCat-Yunzai/" ];
  then
        echo "克隆失败"
        exit  
    else # 如果克隆成功
        echo "克隆完成"
    fi
else 
    echo "克隆完毕"
fi
}

function Miao-Yunzai {
echo '正在克隆云崽……'
if [ ! -d "$HOME/Yunzai-Bot" ]; 
then 
    git clone --depth=1 -b main https://gitee.com/yoimiya-kokomi/Yunzai-Bot.git
    if [ ! -d "$HOME/Yunzai-Bot/" ];
  then
        echo "克隆失败"
        exit  
    else # 如果克隆成功
        echo "克隆完成"
    fi
else 
    echo "克隆完毕"
fi
}

function install-P {
echo '正在安装依赖……'
cd $HOME/MangoCat-Yunzai/
cd ~/MangoCat-Yunzai
cd $HOME/Yunzai-Bot/
cd ~/Yunzai-Bot
pnpm install -P
}

function start {
echo '正在启动云崽……'
cd ~/Termux-Linux/Ubuntu
./start-ubuntu.sh
redis-server --save 900 1 --save 300 10 --daemonize yes
cd $HOME/MangoCat-Yunzai/
cd ~/MangoCat-Yunzai && node app
cd $HOME/Yunzai-Bot/
cd ~/Yunzai-Bot && node app
}
function plugins {
cd $HOME/Yunzai-Bot/
npm install pnpm -g
npm install -g cnpm --registry=https://registry.npmmirror.com
cnpm install

echo '正在准备安装插件……'

echo '正在安装喵喵插件，支持查询游戏内角色面板'
git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/

echo '正在安装c佬图鉴插件，提供原魔、食物、武器、角色等图鉴帮助'
git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/

echo '正在安装榴莲插件，提供原神地下地图、插件管理、以及部分群聊功能'
git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/

echo '正在安装部分依赖'
pnpm install -P

echo '插件安装完毕，启动后请按要求安装依赖'
echo '如果想删除插件，请进行以下操作'
echo 'cd ~/Yunzai-Bot/plugins'
echo '输入rm -rf 插件名称'
echo -e "\033[32m退出后台重进后输入以下代码(建议复制！！！):\033[0m"
echo -e "\033[43;31mcd ~/Termux-Linux/Ubuntu\033[0m"
echo -e "\033[43;31m./start-ubuntu.sh\033[0m"
echo -e "\033[43;31mredis-server --daemonize yes --save 900 1 --save 300 10\033[0m"
echo -e "\033[43;31mcd Yunzai-Bot\033[0m"
echo -e "\033[43;31mnode app\033[0m"
echo '现在输入cd ~/Yunzai-Bot && node app启动bot进行账号及主人配置'
echo '完毕，收工'
echo '答疑群:658720198'
}

echo "-----------------------菜单-------------------"
echo "              请选择要执行的操作："
echo "              1. 安装容器"
echo "              2. 继续(请在安装完容器后选择)"
echo "              3. 安装芒果猫版云崽"
echo "              4. 安装喵版云崽"
echo "              5. 安装插件(请在安装云崽本体后选择)"
echo "              6. 安装依赖"
echo "              7. 启动云崽"
echo "----------------by 会飞的芒果猫-----------------"

# 读取用户输入
read -p "请输入要执行操作选项：" choice

# 根据用户输入的选项执行相应的函数
case $choice in
  1) container ;;
  2) continue ;;
  3) MangoCat-Yunzai ;;
  4) Miao-Yunzai ;;
  5) plugins ;;
  6) install-P ;;
  7) start ;;
  *) echo "请输入正确选项" ;;
esac