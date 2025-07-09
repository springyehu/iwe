# 使用多阶段构建来获取 qemu-static
FROM --platform=linux/amd64 ubuntu:22.04 as qemu_builder
RUN apt-get update && apt-get install -y qemu-user-static

# 最终的 arm64 镜像
FROM --platform=linux/arm64 ubuntu:22.04

# --- QEMU 和 x86_64 环境设置 ---
COPY --from=qemu_builder /usr/bin/qemu-x86_64-static /usr/bin/
RUN apt-get update && apt-get install -y gpg && dpkg --add-architecture amd64 && apt-get update

# 安装 myapp 所需的 x86_64 动态链接库
# !!! 这是最关键的一步，请用 `ldd myapp` 命令确认依赖并按需添加 !!!
RUN apt-get install -y --no-install-recommends \
    libc6:amd64 \
    libstdc++6:amd64 \
    libgcc-s1:amd64
# 如果 ldd myapp 显示需要其他库，例如 libssl.so，则需要添加 libssl3:amd64 等

# --- 原生 arm64 环境设置 ---
# Set timezone
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install native arm64 dependencies
RUN apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    redis-server \
    supervisor \
    mariadb-server-10.6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Supervisor 配置 (与之前基本相同) ---
RUN mkdir -p /etc/supervisor/conf.d

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
# 注意: 在构建时启动服务不是最佳实践，但为了与原版保持一致暂不修改
RUN service mariadb start && \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678'; FLUSH PRIVILEGES;" && \
    mysql -u root -pIwe@12345678 -e "CREATE DATABASE iwedb;"

# --- 应用文件 ---
LABEL maintainer="wanano"
ENV LANG=C.UTF-8

WORKDIR /app

# 从构建上下文中名为 iwechat-src 的目录复制文件
COPY iwechat-src/myapp /app/myapp
COPY iwechat-src/assets /app/assets
COPY iwechat-src/static /app/static

RUN chmod +x /app/myapp

EXPOSE 8849
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
