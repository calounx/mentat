# -*- mode: ruby -*-
# vi: set ft=ruby :

# CHOM Test Environment - Vagrant Configuration
# This creates a two-VM setup mimicking the production infrastructure:
# - mentat (observability server)
# - landsraad (application server)

Vagrant.configure("2") do |config|
  # Base box - Debian 13 (Trixie) to match production
  # Note: Using Debian 12 (Bookworm) as Debian 13 may not be available in Vagrant Cloud
  config.vm.box = "debian/bookworm64"
  config.vm.box_version = ">= 12.0"

  # Common provisioning for both VMs
  config.vm.provision "shell", inline: <<-SHELL
    # Update system
    apt-get update
    apt-get upgrade -y

    # Install common dependencies
    apt-get install -y \
      curl \
      wget \
      git \
      vim \
      htop \
      net-tools \
      ufw \
      gnupg \
      lsb-release \
      ca-certificates \
      apt-transport-https \
      software-properties-common

    # Configure timezone
    timedatectl set-timezone UTC
  SHELL

  #############################################################################
  # MENTAT - Observability Server
  #############################################################################
  config.vm.define "mentat" do |mentat|
    mentat.vm.hostname = "mentat.local"
    mentat.vm.network "private_network", ip: "192.168.56.10"

    # Port forwarding for observability services
    mentat.vm.network "forwarded_port", guest: 9090, host: 9090, host_ip: "127.0.0.1"  # Prometheus
    mentat.vm.network "forwarded_port", guest: 3000, host: 3000, host_ip: "127.0.0.1"  # Grafana
    mentat.vm.network "forwarded_port", guest: 3100, host: 3100, host_ip: "127.0.0.1"  # Loki
    mentat.vm.network "forwarded_port", guest: 9093, host: 9093, host_ip: "127.0.0.1"  # AlertManager
    mentat.vm.network "forwarded_port", guest: 9100, host: 9101, host_ip: "127.0.0.1"  # Node Exporter

    # VM resources
    mentat.vm.provider "virtualbox" do |vb|
      vb.name = "chom-mentat"
      vb.memory = "2048"
      vb.cpus = 1
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end

    # Provision observability stack
    mentat.vm.provision "shell", inline: <<-SHELL
      echo "=== Setting up Mentat (Observability Server) ==="

      # Create deployment user
      if ! id -u stilgar &>/dev/null; then
        useradd -m -s /bin/bash stilgar
        echo "stilgar ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/stilgar
        mkdir -p /home/stilgar/.ssh
        chmod 700 /home/stilgar/.ssh
        chown -R stilgar:stilgar /home/stilgar/.ssh
      fi

      # Install Prometheus
      PROMETHEUS_VERSION="2.48.0"
      if [ ! -f /usr/local/bin/prometheus ]; then
        echo "Installing Prometheus ${PROMETHEUS_VERSION}..."
        wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
        tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
        cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
        cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
        mkdir -p /etc/prometheus /var/lib/prometheus
        cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus/
        cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/
        rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*

        # Create Prometheus user
        useradd --no-create-home --shell /bin/false prometheus || true
        chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
        chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
      fi

      # Install Node Exporter
      NODE_EXPORTER_VERSION="1.7.0"
      if [ ! -f /usr/local/bin/node_exporter ]; then
        echo "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."
        wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
        rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

        useradd --no-create-home --shell /bin/false node_exporter || true
        chown node_exporter:node_exporter /usr/local/bin/node_exporter
      fi

      # Install Loki
      LOKI_VERSION="2.9.3"
      if [ ! -f /usr/local/bin/loki ]; then
        echo "Installing Loki ${LOKI_VERSION}..."
        wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip
        unzip -o loki-linux-amd64.zip
        chmod +x loki-linux-amd64
        mv loki-linux-amd64 /usr/local/bin/loki
        rm loki-linux-amd64.zip

        mkdir -p /etc/loki /var/lib/loki
        useradd --no-create-home --shell /bin/false loki || true
        chown -R loki:loki /etc/loki /var/lib/loki
        chown loki:loki /usr/local/bin/loki
      fi

      # Install Promtail
      if [ ! -f /usr/local/bin/promtail ]; then
        echo "Installing Promtail ${LOKI_VERSION}..."
        wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-linux-amd64.zip
        unzip -o promtail-linux-amd64.zip
        chmod +x promtail-linux-amd64
        mv promtail-linux-amd64 /usr/local/bin/promtail
        rm promtail-linux-amd64.zip

        mkdir -p /etc/promtail
        useradd --no-create-home --shell /bin/false promtail || true
        chown promtail:promtail /usr/local/bin/promtail
      fi

      # Install Grafana
      GRAFANA_VERSION="11.3.0"
      if [ ! -f /usr/sbin/grafana-server ]; then
        echo "Installing Grafana ${GRAFANA_VERSION}..."
        wget -q https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb
        dpkg -i grafana_${GRAFANA_VERSION}_amd64.deb || apt-get install -f -y
        rm grafana_${GRAFANA_VERSION}_amd64.deb
        systemctl daemon-reload
      fi

      # Install AlertManager
      ALERTMANAGER_VERSION="0.26.0"
      if [ ! -f /usr/local/bin/alertmanager ]; then
        echo "Installing AlertManager ${ALERTMANAGER_VERSION}..."
        wget -q https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
        tar xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
        cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/
        cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool /usr/local/bin/
        mkdir -p /etc/alertmanager /var/lib/alertmanager
        rm -rf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64*

        useradd --no-create-home --shell /bin/false alertmanager || true
        chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
        chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
      fi

      echo "=== Mentat setup complete ==="
      echo "Access services at:"
      echo "  Prometheus:   http://localhost:9090"
      echo "  Grafana:      http://localhost:3000 (admin/admin)"
      echo "  Loki:         http://localhost:3100"
      echo "  AlertManager: http://localhost:9093"
    SHELL
  end

  #############################################################################
  # LANDSRAAD - Application Server
  #############################################################################
  config.vm.define "landsraad" do |landsraad|
    landsraad.vm.hostname = "landsraad.local"
    landsraad.vm.network "private_network", ip: "192.168.56.11"

    # Port forwarding for application services
    landsraad.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"     # Nginx HTTP
    landsraad.vm.network "forwarded_port", guest: 443, host: 8443, host_ip: "127.0.0.1"   # Nginx HTTPS
    landsraad.vm.network "forwarded_port", guest: 5432, host: 5432, host_ip: "127.0.0.1"  # PostgreSQL
    landsraad.vm.network "forwarded_port", guest: 6379, host: 6379, host_ip: "127.0.0.1"  # Redis
    landsraad.vm.network "forwarded_port", guest: 9100, host: 9102, host_ip: "127.0.0.1"  # Node Exporter

    # VM resources
    landsraad.vm.provider "virtualbox" do |vb|
      vb.name = "chom-landsraad"
      vb.memory = "4096"
      vb.cpus = 2
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end

    # Synced folder for development
    landsraad.vm.synced_folder ".", "/vagrant", type: "virtualbox"

    # Provision application stack
    landsraad.vm.provision "shell", inline: <<-SHELL
      echo "=== Setting up Landsraad (Application Server) ==="

      # Create deployment user
      if ! id -u stilgar &>/dev/null; then
        useradd -m -s /bin/bash stilgar
        echo "stilgar ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/stilgar
        mkdir -p /home/stilgar/.ssh
        chmod 700 /home/stilgar/.ssh
        chown -R stilgar:stilgar /home/stilgar/.ssh
      fi

      # Install PHP 8.2 and extensions
      echo "Installing PHP 8.2..."
      apt-get install -y lsb-release ca-certificates apt-transport-https software-properties-common
      curl -sSL https://packages.sury.org/php/README.txt | bash -x
      apt-get update
      apt-get install -y \
        php8.2 \
        php8.2-cli \
        php8.2-fpm \
        php8.2-pgsql \
        php8.2-sqlite3 \
        php8.2-redis \
        php8.2-mbstring \
        php8.2-xml \
        php8.2-curl \
        php8.2-zip \
        php8.2-gd \
        php8.2-intl \
        php8.2-bcmath

      # Install Composer
      if [ ! -f /usr/local/bin/composer ]; then
        echo "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
      fi

      # Install Node.js 20
      if [ ! -f /usr/bin/node ]; then
        echo "Installing Node.js 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
      fi

      # Install Nginx
      echo "Installing Nginx..."
      apt-get install -y nginx

      # Install PostgreSQL 15
      echo "Installing PostgreSQL 15..."
      apt-get install -y postgresql-15 postgresql-client-15

      # Install Redis
      echo "Installing Redis..."
      apt-get install -y redis-server

      # Install Supervisor (for queue workers)
      echo "Installing Supervisor..."
      apt-get install -y supervisor

      # Install Node Exporter
      NODE_EXPORTER_VERSION="1.7.0"
      if [ ! -f /usr/local/bin/node_exporter ]; then
        echo "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."
        wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
        rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

        useradd --no-create-home --shell /bin/false node_exporter || true
        chown node_exporter:node_exporter /usr/local/bin/node_exporter
      fi

      # Configure PostgreSQL for CHOM
      echo "Configuring PostgreSQL..."
      sudo -u postgres psql -c "CREATE DATABASE chom_test;" 2>/dev/null || true
      sudo -u postgres psql -c "CREATE USER chom_user WITH PASSWORD 'chom_password';" 2>/dev/null || true
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE chom_test TO chom_user;" 2>/dev/null || true

      # Configure Redis
      echo "Configuring Redis..."
      sed -i 's/^bind 127.0.0.1/bind 127.0.0.1 192.168.56.11/' /etc/redis/redis.conf
      systemctl restart redis-server

      # Configure PHP-FPM
      echo "Configuring PHP-FPM..."
      sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini
      systemctl restart php8.2-fpm

      # Configure Nginx
      echo "Configuring Nginx..."
      systemctl enable nginx
      systemctl start nginx

      echo "=== Landsraad setup complete ==="
      echo "Access services at:"
      echo "  Application:  http://localhost:8080"
      echo "  PostgreSQL:   localhost:5432 (chom_user/chom_password)"
      echo "  Redis:        localhost:6379"
    SHELL
  end

  #############################################################################
  # Post-provisioning message
  #############################################################################
  config.vm.post_up_message = <<-MESSAGE
    ╔═══════════════════════════════════════════════════════════════════════╗
    ║                 CHOM Test Environment Ready!                          ║
    ╚═══════════════════════════════════════════════════════════════════════╝

    Two VMs have been created:

    1. MENTAT (Observability Server) - 192.168.56.10
       - Prometheus:   http://localhost:9090
       - Grafana:      http://localhost:3000 (admin/admin)
       - Loki:         http://localhost:3100
       - AlertManager: http://localhost:9093

    2. LANDSRAAD (Application Server) - 192.168.56.11
       - HTTP:         http://localhost:8080
       - HTTPS:        https://localhost:8443
       - PostgreSQL:   localhost:5432 (chom_user/chom_password)
       - Redis:        localhost:6379

    Next steps:

    1. SSH into landsraad:
       $ vagrant ssh landsraad

    2. Set up the CHOM application:
       $ cd /vagrant
       $ cp .env.example .env
       $ composer install
       $ npm install
       $ php artisan key:generate
       $ php artisan migrate --seed
       $ npm run build

    3. Start the development server:
       $ php artisan serve --host=0.0.0.0

    4. Run tests:
       $ php artisan test

    For observability configuration, see: deploy/config/

    Enjoy testing CHOM!
  MESSAGE
end
