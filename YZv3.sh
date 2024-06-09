#!/bin/bash

function container {
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/environment)
apt install update
apt install curl -y
echo '安装完毕'
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)
}
function continue {
echo '正在更新apt，请稍后……'
apt update
apt upgrade -y

echo '正在安装nodejs，请稍后……'
curl -sL https://deb.nodesource.com/setup_20.x | bash -
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
curl -o ffmpeg https://cdn.npmmirror.com/binaries/ffmpeg-static/b6.0/ffmpeg-linux-${structure}
curl -o ffprobe https://cdn.npmmirror.com/binaries/ffmpeg-static/b6.0/ffprobe-linux-${structure}
mv -f ffmpeg /usr/local/bin/ffmpeg
mv -f ffprobe /usr/local/bin/ffpro
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)
}

function MangoCat-Yunzai {
echo '正在克隆芒果猫版云崽……'
if [ ! -d "$HOME/MangoCat-Yunzai" ]; 
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
cd $HOME/MangoCat-Yunzai
npm install pnpm -g
npm install -g cnpm --registry=https://registry.npmmirror.com
cnpm install

echo '正在安装喵喵插件，支持查询游戏内角色面板'
git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/

echo '正在安装c佬图鉴插件，提供原魔、食物、武器、角色等图鉴帮助'
git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/

echo '正在安装榴莲插件，提供原神猜角色、插件管理、以及部分群聊功能'
git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/

echo '正在安装部分依赖'
pnpm install -P

echo '插件安装完毕，启动后请按要求安装依赖'
echo -e "\033[32m退出后台重进后输入以下代码(建议复制！！！):\033[0m"
echo -e "\033[43;31mcd ~/Termux-Linux/Ubuntu\033[0m"
echo -e "\033[43;31m./start-ubuntu.sh\033[0m"
echo -e "\033[43;31mredis-server --daemonize yes --save 900 1 --save 300 10\033[0m"
echo -e "\033[43;31mcd MangoCat-Yunzai\033[0m"
echo -e "\033[43;31mnode app\033[0m"
echo '现在输入cd ~/Yunzai-Bot && node app启动bot进行账号及主人配置'
echo '完毕，收工'
echo '答疑群:658720198'
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)
}

function Miao-Yunzai {
echo '正在克隆喵版云崽……'
if [ ! -d "$HOME/Miao-Yunzai" ]; 
then 
    git clone --depth=1 https://gitee.com/yoimiya-kokomi/Miao-Yunzai.git
    if [ ! -d "$HOME/Miao-Yunzai/" ];
  then
        echo "克隆失败"
        exit  
    else # 如果克隆成功
        echo "克隆完成"
    fi
else 
    echo "克隆完毕"
fi
cd $HOME/Miao-Yunzai
npm install pnpm -g
npm install -g cnpm --registry=https://registry.npmmirror.com
cnpm install

echo '正在安装喵喵插件，支持查询游戏内角色面板'
git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/

echo '正在安装c佬图鉴插件，提供原魔、食物、武器、角色等图鉴帮助'
git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/

echo '正在安装榴莲插件，提供原神地下地图、插件管理、以及部分群聊功能'
git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/

echo '正在安装部分依赖'
pnpm install -P

echo '插件安装完毕，启动后请按要求安装依赖'
echo -e "\033[32m退出后台重进后输入以下代码(建议复制！！！):\033[0m"
echo -e "\033[43;31mcd ~/Termux-Linux/Ubuntu\033[0m"
echo -e "\033[43;31m./start-ubuntu.sh\033[0m"
echo -e "\033[43;31mredis-server --daemonize yes --save 900 1 --save 300 10\033[0m"
echo -e "\033[43;31mcd Miao-Yunzai\033[0m"
echo -e "\033[43;31mnode app\033[0m"
echo '现在输入cd ~/Yunzai-Bot && node app启动bot进行账号及主人配置'
echo '完毕，收工'
echo '答疑群:658720198'
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)
}

function install-P {
echo '正在安装依赖……'
cd $HOME/MangoCat-Yunzai/
cd ~/MangoCat-Yunzai
cd $HOME/Miao-Yunzai/
cd ~/Miao-Yunzai
pnpm install -P
bash <(curl -l https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3.sh)
}

function start {
echo '正在启动云崽……'
cd ~/Termux-Linux/Ubuntu
./start-ubuntu.sh
redis-server --save 900 1 --save 300 10 --daemonize yes
cd $HOME/MangoCat-Yunzai/
cd ~/MangoCat-Yunzai && node app
cd $HOME/Miao-Yunzai/
cd ~/Miao-Yunzai && node app
}

echo "-----------------------菜单-------------------"
echo "              请选择要执行的操作："
echo "              1. 安装容器"
echo "              2. 配置环境"
echo "              3. 安装芒果猫版云崽"
echo "              4. 安装喵崽"
echo "              5. 安装依赖"
echo "              6. 启动云崽"
echo "              7. 使用帮助"
echo "              8. 我不会"
echo -e "\033[32m注意！初次安装请按照以下顺序：1，2，3/4，5，6\033[0m"
echo "----------------by 会飞的芒果猫-----------------"

# 读取用户输入
read -p "请输入要执行操作选项：" choice

# 根据用户输入的选项执行相应的函数
case $choice in
  1) container ;;
  2) continue ;;
  3) MangoCat-Yunzai ;;
  4) Miao-Yunzai ;; 
  5) install-P ;;
  6) start ;;
  7) echo -e "\033[32m初次安装请按照以下顺序进行操作：
  第一步，输入阿拉伯数字1，安装容器。
  第二步，输入阿拉伯数字2，配置环境。
  第三步，输入阿拉伯数字3或4安装对应的云崽版本。
  第四步，输入阿拉伯数字5，安装依赖。
  第五步，输入阿拉伯数字6，启动云崽。
  你学废了吗？\033[0m" ;;
  8) echo "请使用您会使用的电子通讯产品安装并打开腾讯QQ登录，
  点击搜索栏输入3598537042，
  输入完成后请点击搜索，添加用户“会飞的芒果猫”并耐心等待，
  通过好友后，请您说出您的问题并附对应截图（您所遇到问题界面的截图），并耐心等待即可
  等待有回复后，请您一定按照要求进行操作
  谢谢配合" container ;;
  *) echo "请输入正确选项" ;;
esac