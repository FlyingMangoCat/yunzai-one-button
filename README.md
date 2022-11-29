# 云崽一键安装

#### 说明

yunzai-Bot安卓一键部署

#### 支持版本：
| …… | v2 | v3 | …… |
|-------| ----- | ------ | ------|
|  | ✓ | ✓ |  |

#### 自带插件包(这三个基本装云崽都会用到，如需其他插件可以去[插件库](https://gitee.com/Hikari666/Yunzai-Bot-plugins-index)自行安装)
[喵喵插件](https://gitee.com/yoimiya-kokomi/miao-plugin)：查询游戏内角色面板
[图鉴插件](https://gitee.com/Ctrlcvs/xiaoyao-cvs-plugin)：提供角色、武器、原魔、食物等图鉴内容
[榴莲插件](https://gitee.com/huifeidemangguomao/liulian-plugin)：提供须弥地下地图，插件管理，一些群聊功能等

#### 部署工具

必备[Termux](https://f-droid.org/repo/com.termux_118.apk)

推荐[滑动验证助手](https://maupdate.rainchan.win/txcaptcha.apk) 

#### 开始安装

在Termux中依次输入
```
pkg install proot git python -y
```
```
git clone https://gitee.com/Le-niao/termux-install-linux.git
cd termux-install-linux 
python termux-linux-install.py
```
输入1，选择安装ubuntu；
```
cd ~/Termux-Linux/Ubuntu
./start-ubuntu.sh
```
```
apt update
```
```
apt install curl -y
```

安装云崽以及插件包

```
curl -sL https://gitee.com/fw-cn/Yunzai/raw/master/Yunzai-Bot-pkg.sh | bash
```
```
cd Yunzai-Bot
node app
```
#### 其他

[芒果猫(榴莲插件)问题反馈专栏]()