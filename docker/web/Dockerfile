# ============================================================================
# CHOM Web Application Stack - Debian 13 Host
# ============================================================================
# This Dockerfile creates a production-like web application host with:
# - Nginx (web server)
# - PHP 8.4-FPM (Laravel runtime)
# - MySQL 8.0 (database)
# - Redis 7+ (cache/queue)
# - Laravel CHOM application
# - Queue worker & Scheduler
# - Alloy agent (metrics/logs shipper)
# - Exporters (node, nginx, mysql, php-fpm)
# ============================================================================

FROM debian:13-slim

LABEL maintainer="CHOM Team"
LABEL description="CHOM Web Application Stack - Laravel SaaS Platform"
LABEL version="1.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=8.4 \
    NODE_VERSION=20 \
    COMPOSER_VERSION=2.7.1 \
    ALLOY_VERSION=1.5.1 \
    NGINX_EXPORTER_VERSION=1.3.0 \
    MYSQL_EXPORTER_VERSION=0.16.0 \
    PHPFPM_EXPORTER_VERSION=2.2.0 \
    NODE_EXPORTER_VERSION=1.8.2 \
    APP_USER=www-data \
    APP_PATH=/var/www/chom

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    tar \
    gzip \
    unzip \
    git \
    supervisor \
    cron \
    lsb-release \
    gnupg2 \
    procps \
    vim \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Nginx
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install PHP and extensions from Debian 13 native packages
# ============================================================================
# Debian 13 (Trixie) ships with PHP 8.2 in its default repositories
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-fpm \
    php-cli \
    php-common \
    php-mysql \
    php-pgsql \
    php-sqlite3 \
    php-redis \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-zip \
    php-bcmath \
    php-intl \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install MariaDB 10.11 (MySQL compatible, from Debian repos)
# ============================================================================
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Redis
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Node.js and npm
# ============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g npm@latest && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Composer
# ============================================================================
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin \
    --filename=composer \
    --version=${COMPOSER_VERSION}

# ============================================================================
# Install Exporters
# ============================================================================
# Node Exporter
RUN wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && \
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# Nginx Exporter
RUN wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz && \
    tar -xzf nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz && \
    mv nginx-prometheus-exporter /usr/local/bin/ && \
    rm nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz

# MySQL Exporter
RUN wget https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQL_EXPORTER_VERSION}/mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar -xzf mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    mv mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-amd64/mysqld_exporter /usr/local/bin/ && \
    rm -rf mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-amd64*

# PHP-FPM Exporter
RUN wget https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64 && \
    mv php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64 /usr/local/bin/php-fpm_exporter && \
    chmod +x /usr/local/bin/php-fpm_exporter

# ============================================================================
# Install Grafana Alloy (metrics/logs shipper)
# ============================================================================
RUN wget https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-linux-amd64.zip && \
    apt-get update && apt-get install -y --no-install-recommends unzip && \
    unzip alloy-linux-amd64.zip && \
    mv alloy-linux-amd64 /usr/local/bin/alloy && \
    chmod +x /usr/local/bin/alloy && \
    rm alloy-linux-amd64.zip && \
    mkdir -p /etc/alloy /var/lib/alloy && \
    apt-get remove -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Configure PHP-FPM
# ============================================================================
RUN mkdir -p /run/php && \
    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/${PHP_VERSION}/fpm/php.ini && \
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' /etc/php/${PHP_VERSION}/fpm/php.ini && \
    sed -i 's/post_max_size = 8M/post_max_size = 100M/' /etc/php/${PHP_VERSION}/fpm/php.ini && \
    sed -i 's/memory_limit = 128M/memory_limit = 512M/' /etc/php/${PHP_VERSION}/fpm/php.ini && \
    sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/${PHP_VERSION}/fpm/php.ini

# Enable PHP-FPM status page for monitoring
RUN echo 'pm.status_path = /status' >> /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
    echo 'ping.path = /ping' >> /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf

# Copy custom PHP-FPM configuration
COPY php/php-fpm.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
COPY php/php.ini /etc/php/${PHP_VERSION}/fpm/conf.d/99-custom.ini

# ============================================================================
# Configure Nginx
# ============================================================================
# Remove default site
RUN rm -f /etc/nginx/sites-enabled/default

# Copy custom Nginx configuration
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/chom.conf /etc/nginx/sites-available/chom.conf
RUN ln -s /etc/nginx/sites-available/chom.conf /etc/nginx/sites-enabled/chom.conf

# Enable Nginx stub_status for monitoring
RUN echo 'server { listen 8080; location /stub_status { stub_status; } }' > /etc/nginx/sites-available/status.conf && \
    ln -s /etc/nginx/sites-available/status.conf /etc/nginx/sites-enabled/status.conf

# ============================================================================
# Configure MySQL
# ============================================================================
RUN mkdir -p /var/run/mysqld && \
    chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

COPY mysql/my.cnf /etc/mysql/conf.d/custom.cnf

# ============================================================================
# Configure Redis
# ============================================================================
RUN sed -i 's/bind 127.0.0.1 ::1/bind 0.0.0.0/' /etc/redis/redis.conf && \
    sed -i 's/# maxmemory <bytes>/maxmemory 256mb/' /etc/redis/redis.conf && \
    sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

# ============================================================================
# Set up application directory
# ============================================================================
RUN mkdir -p ${APP_PATH} && \
    chown -R ${APP_USER}:${APP_USER} ${APP_PATH}

WORKDIR ${APP_PATH}

# ============================================================================
# Configure Supervisor
# ============================================================================
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ============================================================================
# Copy initialization scripts
# ============================================================================
COPY scripts/init-app.sh /usr/local/bin/init-app.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/init-app.sh /usr/local/bin/healthcheck.sh

# ============================================================================
# Expose ports
# ============================================================================
# Nginx HTTP
EXPOSE 80
# Nginx HTTPS
EXPOSE 443
# MySQL
EXPOSE 3306
# Redis
EXPOSE 6379
# Node Exporter
EXPOSE 9100
# Nginx Exporter
EXPOSE 9113
# MySQL Exporter
EXPOSE 9104
# PHP-FPM Exporter
EXPOSE 9253
# Alloy
EXPOSE 12345

# ============================================================================
# Health check
# ============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh || exit 1

# ============================================================================
# Entry point - init-app.sh handles supervisor startup
# ============================================================================
CMD ["/usr/local/bin/init-app.sh"]
