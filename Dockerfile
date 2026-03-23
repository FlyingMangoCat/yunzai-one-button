FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV NODE_VERSION=20.x

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    vim \
    nano \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libatspi2.0-0 \
    libgtk-3-0 \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python3.10
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.10 python3.10-venv python3.10-dev && \
    rm -rf /var/lib/apt/lists/*

# 安装 ffmpeg
RUN apt-get update && \
    apt-get install -y ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 安装 Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 安装 Redis
RUN apt-get update && \
    apt-get install -y redis-server && \
    rm -rf /var/lib/apt/lists/*

# 安装 Chromium
RUN apt-get update && \
    apt-get install -y chromium-browser && \
    rm -rf /var/lib/apt/lists/*

# 设置 Chrome/Chromium 路径
ENV CHROME_BIN=/usr/bin/chromium-browser
ENV CHROME_PATH=/usr/bin/chromium-browser

# 创建工作目录
WORKDIR /app

# 安装全局 npm 包
RUN npm install -g pnpm && \
    npm install -g cnpm --registry=https://registry.npmmirror.com

# 复制启动脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 暴露端口
EXPOSE 5700

# 设置入口点
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# 默认命令
CMD ["node", "app"]
