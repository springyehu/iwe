# 阶段 1: 使用多阶段构建来获取 qemu-static
FROM --platform=linux/amd64 ubuntu:22.04 AS qemu_builder
RUN apt-get update && apt-get install -y --no-install-recommends qemu-user-static && apt-get clean && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------

# 阶段 2: 最终的 arm64 镜像
FROM --platform=linux/arm64 ubuntu:22.04

# 从构建器阶段复制 QEMU 静态模拟器
COPY --from=qemu_builder /usr/bin/qemu-x86_64-static /usr/bin/

# 设置环境变量
ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# --- 关键修复：重写软件源以支持多架构 ---
RUN echo "deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list

# --- 统一的安装、配置和清理层 ---
RUN \
    # 1. 更新包列表并添加 amd64 架构
    apt-get update && \
    dpkg --add-architecture amd64 && \
    \
    # 2. 再次更新，现在 apt 会从新源获取 arm64 和 amd64 的列表
    apt-get update && \
    \
    # 3. 安装所有依赖包
    apt-get install -y --no-install-recommends \
    # 原生 arm64 包
    ca-certificates \
    curl \
    gnupg \
    tzdata \
    redis-server \
    supervisor \
    mariadb-server-10.6 \
    # 外来 amd64 包
    libc6:amd64 \
    libstdc++6:amd64 \
    libgcc-s1:amd64 && \
    \
    # 4. 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    \
    # 5. 其他配置
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    mkdir -p /etc/supervisor/conf.d

# --- Supervisor 配置 (保持不变) ---
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo 'loglevel=warn' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf
RUN echo '[program:mariadb]' > /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'command=/usr/bin/mysqld_safe' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/02_mariadb.conf
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/usr/bin/qemu-x86_64-static /app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf

# --- 数据库初始化 ---
RUN service mariadb start && \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678'; FLUSH PRIVILEGES;" && \
    mysql -u root -pIwe@12345678 -e "CREATE DATABASE iwedb;"

# --- 应用文件 ---
LABEL maintainer="exthirteen"
WORKDIR /app
COPY iwechat-src/myapp /app/myapp
COPY iwechat-src/assets /app/assets
COPY iwechat-src/static /app/static
RUN chmod +x /app/myapp

EXPOSE 8849
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
