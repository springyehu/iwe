FROM alpine:latest AS qemu-builder
RUN apk add --no-cache qemu-x86_64

# --------------------------------------------------

# 阶段 2: 最终的 Alpine 镜像
FROM alpine:latest

# 从构建器阶段复制 QEMU 静态模拟器
COPY --from=qemu-builder /usr/bin/qemu-x86_64 /usr/bin/qemu-x86_64-static

# 2. 修改：使用 apk 替换 apt-get，并调整包名
# Set timezone to Asia/Shanghai
RUN apk update && apk add --no-cache tzdata && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# Install curl, ca-certificates, redis, supervisor and mariadb
# 注意：Alpine 中的包名与 Ubuntu 不同
RUN apk update && apk add --no-cache curl ca-certificates redis supervisor mariadb mariadb-client

# 创建 supervisor 配置目录 (此部分保持不变)
RUN mkdir -p /etc/supervisor/conf.d

# 创建 supervisord.conf 配置文件 (此部分保持不变)
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo 'loglevel=warn' >> /etc/supervisor/supervisord.conf && \
    echo '[unix_http_server]' >> /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# Add supervisor config for redis (此部分保持不变)
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stderr_logfile=/var/log/redis.err.log' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stdout_logfile=/var/log/redis.out.log' >> /etc/supervisor/conf.d/01_redis.conf

# Add supervisor config for mariadb (此部分保持不变)
# 注意：mysqld_safe 在 alpine 中也可用
RUN echo '[program:mariadb]' > /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'command=/usr/bin/mysqld_safe --datadir=/var/lib/mysql' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stderr_logfile=/var/log/mariadb.err.log' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stdout_logfile=/var/log/mariadb.out.log' >> /etc/supervisor/conf.d/02_mariadb.conf

# Add supervisor config for myapp
# 3. 关键修改：在 myapp 的启动命令前加入 qemu-x86_64-static
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/usr/bin/qemu-x86_64-static /app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_events_enabled=true' >> /etc/supervisor/conf.d/99_myapp.conf

# 4. 修改：适配 Alpine 的 MariaDB 初始化方式
# Alpine 没有 'service' 命令，且需要手动初始化数据库目录
RUN mkdir -p /run/mysqld && \
    chown -R mysql:mysql /run/mysqld && \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql && \
    mysqld_safe --datadir=/var/lib/mysql --nowatch & \
    sleep 5 && \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678'; FLUSH PRIVILEGES;" && \
    mysql -u root -p'Iwe@12345678' -e "CREATE DATABASE iwedb;" && \
    mysqladmin -u root -p'Iwe@12345678' shutdown

# 以下部分完全保持不变
LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8

WORKDIR /app
COPY iwechat-src/myapp /app/myapp
COPY iwechat-src/assets /app/assets
COPY iwechat-src/static /app/static
RUN chmod +x /app/myapp

EXPOSE 8849
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
