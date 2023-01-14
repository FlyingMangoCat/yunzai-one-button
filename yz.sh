if [ $(arch) == "aarch64" ]; then
    echo -e "\033[36m 开始安装 \033[0m";
    wget -c https://gitee.com/huifeidemangguomao/yunzai-one-button/raw/master/YZv3-arm.sh
    chmod +x YZv3-arm.sh
    ./YZv3-arm.sh
    echo -e "\033[36m 执行完成 \033[0m"
    exit 1
elif [ $(uname -m) == "x86_64" ]; then
    echo -e "\033[36m 开始安装 \033[0m";
     wget -c https://gitee.com/huifeidemangguomao/yunzai-one-button/rawmaster/YZv3-amd.sh
    chmod +x YZv3-arm.sh
    ./YZv3-amd.sh
    echo -e "\033[36m执行完成\033[0m"
    exit 1
  fi