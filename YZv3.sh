#!/bin/bash

echo '更新apt'
apt update
apt upgrade -y

echo '正在安装git python3.8 pip，请稍后……'
apt install git python3.8 python3-pip -y
ln -sf python3.8 /usr/bin/python
ln -sf /usr/bin/pip3 /usr/bin/pip
python -m pip install --upgrade pip
echo '安装完成'

echo '正在安装nodejs，请稍后……'
curl -sL https://deb.nodesource.com/setup_17.x | bash -
apt-get install -y nodejs
echo '安装完成'

echo '安装并启动redis'
apt-get install redis -y

redis-server --daemonize yes
echo '安装并启动成功'

echo '正在安装chromuim，中文字体等，请稍后……'
apt install chromium-browser -y
apt install -y --force-yes --no-install-recommends fonts-wqy-microhei
apt install git -y

cd ~/
echo '正在克隆云崽……'
git clone https://gitee.com/Le-niao/Yunzai-Bot.git
cd Yunzai-Bot
npm install pnpm -g
npm install -g cnpm --registry=https://registry.npmmirror.com
cnpm install
echo '克隆完毕'

echo '正在准备安装插件，如不想用某个插件，请在全部安装结束后自行删除'

echo '正在安装喵喵插件，支持查询游戏内角色面板'
git clone https://gitee.com/yoimiya-kokomi/miao-plugin.git ./plugins/miao-plugin/

echo '正在安装c佬图鉴插件，提供原魔、食物、武器、角色等图鉴帮助'
git clone https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin.git ./plugins/xiaoyao-cvs-plugin/

echo '正在安装榴莲插件，提供原神地下地图、插件管理、以及部分群聊功能'
git clone https://gitee.com/huifeidemangguomao/liulian-plugin.git ./plugins/liulian-plugin/

echo '插件安装完毕，启动后请按要求安装依赖'
echo '如果想删除插件，请进行以下操作'
echo 'cd ~/Yunzai-Bot/plugins'
echo '输入rm -rf 插件名称'
echo -e "\033[32m退出后台重进后输入以下代码(建议复制):\033[0m"
echo -e "\033[43;31mcd ~/Termux-Linux/Ubuntu\033[0m"
echo -e "\033[43;31m./start-ubuntu.sh\033[0m"
echo -e "\033[43;31mredis-server --daemonize yes --save 900 1 --save 300 10\033[0m"
echo -e "\033[43;31mcd Yunzai-Bot\033[0m"
echo -e "\033[43;31mnode app\033[0m"
echo '现在输入cd ~/Yunzai-Bot && node app启动bot进行账号及主人配置'
echo '完毕，收工'
echo '该一键部署如有问题不可以反馈，反馈我也不管'