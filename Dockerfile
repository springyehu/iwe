# 阶段 1: 使用多阶段构建来获取 qemu-static
FROM --platform=linux/amd64 ubuntu:22.04 AS qemu_builder
RUN apt-get update && apt-get install -y --no-install-recommends qemu-user-static && apt-get clean && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------

# 阶段 2: 最终的 arm64 镜像
FROM --platform=linux/arm64 ubuntu:22.04

# 从构建器阶段复制 QEMU 静态模拟器
COPY --from=qemu_builder /usr/bin/qemu-x86_64-static /usr/bin/

# 设置环境变量
# TZ: 设置时区
# LANG: 设置字符集
# DEBIAN_FRONTEND: 关键！设置为 noninteractive 以避免在 apt 安装过程中出现交互式提示
ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# 单一 RUN 层，用于安装所有依赖、配置多架构并清理
RUN \
    # 1. 更新包列表并安装原生 arm64 依赖
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    tzdata \
    redis-server \
    supervisor \
    mariadb-server-10.6 && \
    \
    # 2. 添加 amd64 架构
    dpkg --add-architecture amd64 && \
    \
    # 3. 再次更新，以获取 amd64 架构的包列表
    apt-get update && \
    \
    # 4. 安装 myapp 所需的 x86_64 (amd64) 动态链接库
    # !!! 这是最关键的一步，请用 `ldd myapp` 命令确认依赖并按需添加 !!!
    apt-get install -y --no-install-recommends \
    libc6:amd64 \
    libstdc++6:amd64 \
    libgcc-s1:amd64 && \
    # 如果 ldd myapp 显示需要其他库，例如 libssl.so，则需要添加 libssl3:amd64 等
    \
    # 5. 清理 apt 缓存，减小镜像体积
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    \
    # 6. 设置时区链接
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    \
    # 7. 创建 supervisor 目录
    mkdir -p /etc/supervisor/conf.d

# --- Supervisor 配置 ---
# supervisord.conf
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo 'loglevel=warn' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf
# redis.conf
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf
# mariadb.conf
RUN echo '[program:mariadb]' > /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'command=/usr/bin/mysqld_safe' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/02_mariadb.conf
# myapp.conf (使用 qemu 启动)
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
LABEL maintainer="spring"
WORKDIR /app
COPY iwechat-src/myapp /app/myapp
COPY iwechat-src/assets /app/assets
COPY iwechat-src/static /app/static
RUN chmod +x /app/myapp

EXPOSE 8849
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
