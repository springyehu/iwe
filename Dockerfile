# 阶段 1: 获取 QEMU 静态二进制文件
# Alpine 镜像本身不含 qemu, 我们需要从其他地方获取或者直接在 Alpine 中安装
# 这里我们选择在 Alpine 中直接安装
FROM alpine:latest AS qemu-builder
RUN apk add --no-cache qemu-x86_64

# --------------------------------------------------

# 阶段 2: 最终的 Alpine 镜像
FROM alpine:latest

# 从构建器阶段复制 QEMU 静态模拟器
COPY --from=qemu-builder /usr/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static

# 安装依赖项
# Alpine 的包名和 Ubuntu 不同
# tzdata 用于时区设置
# redis, supervisor, mariadb, mariadb-client, curl, ca-certificates 是核心服务
# shadow 用于 useradd/groupadd
# coreutils 提供 `chown` 等基本命令
RUN apk add --no-cache \
    tzdata \
    redis \
    supervisor \
    mariadb \
    mariadb-client \
    curl \
    ca-certificates \
    shadow \
    coreutils

# 设置时区为亚洲/上海
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone
RUN mkdir -p /etc/supervisor/conf.d

# --- Supervisor 配置 ---
# (这部分无需修改，保持原样)
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
LABEL maintainer="spring"
WORKDIR /app
COPY iwechat-src/myapp /app/myapp
COPY iwechat-src/assets /app/assets
COPY iwechat-src/static /app/static
RUN chmod +x /app/myapp

EXPOSE 8849
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
