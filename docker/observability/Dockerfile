# ============================================================================
# CHOM Observability Stack - Debian 13 Host
# ============================================================================
# This Dockerfile creates a production-like observability host with:
# - Prometheus (metrics database)
# - Loki (log aggregation)
# - Tempo (distributed tracing)
# - Grafana (visualization)
# - Alertmanager (alert routing)
# - Alloy (OpenTelemetry collector)
# - Node Exporter (system metrics)
# ============================================================================

FROM debian:13-slim

LABEL maintainer="CHOM Team"
LABEL description="CHOM Observability Stack - Monitoring and Logging"
LABEL version="1.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PROMETHEUS_VERSION=3.0.1 \
    LOKI_VERSION=3.3.1 \
    TEMPO_VERSION=2.6.1 \
    GRAFANA_VERSION=11.4.0 \
    ALERTMANAGER_VERSION=0.28.1 \
    ALLOY_VERSION=1.5.1 \
    NODE_EXPORTER_VERSION=1.8.2 \
    PROMETHEUS_USER=prometheus \
    LOKI_USER=loki \
    GRAFANA_USER=grafana

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    tar \
    gzip \
    adduser \
    libfontconfig1 \
    tzdata \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Create non-root users for each service
# ============================================================================
RUN groupadd -r ${PROMETHEUS_USER} && useradd -r -g ${PROMETHEUS_USER} -s /bin/false ${PROMETHEUS_USER} && \
    groupadd -r ${LOKI_USER} && useradd -r -g ${LOKI_USER} -s /bin/false ${LOKI_USER} && \
    groupadd -r ${GRAFANA_USER} && useradd -r -g ${GRAFANA_USER} -s /bin/false ${GRAFANA_USER}

# ============================================================================
# Install Prometheus
# ============================================================================
RUN wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    tar -xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && \
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/ && \
    mkdir -p /etc/prometheus && \
    (test -d prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles && mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus/ || true) && \
    (test -d prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries && mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/ || true) && \
    rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64* && \
    mkdir -p /var/lib/prometheus && \
    chmod -R 777 /var/lib/prometheus /etc/prometheus

# ============================================================================
# Install Alertmanager
# ============================================================================
RUN wget https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz && \
    tar -xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz && \
    mv alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/ && \
    mv alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool /usr/local/bin/ && \
    rm -rf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64* && \
    mkdir -p /var/lib/alertmanager /etc/alertmanager && \
    chmod -R 777 /var/lib/alertmanager /etc/alertmanager

# ============================================================================
# Install Node Exporter
# ============================================================================
RUN wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && \
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# ============================================================================
# Install Loki
# ============================================================================
RUN wget https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip && \
    apt-get update && apt-get install -y --no-install-recommends unzip && \
    unzip loki-linux-amd64.zip && \
    mv loki-linux-amd64 /usr/local/bin/loki && \
    chmod +x /usr/local/bin/loki && \
    rm loki-linux-amd64.zip && \
    mkdir -p /var/lib/loki /etc/loki /loki/chunks /loki/rules /loki/compactor && \
    chmod -R 777 /loki && \
    apt-get remove -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Tempo
# ============================================================================
RUN wget https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz && \
    tar -xzf tempo_${TEMPO_VERSION}_linux_amd64.tar.gz && \
    mv tempo /usr/local/bin/ && \
    rm tempo_${TEMPO_VERSION}_linux_amd64.tar.gz && \
    mkdir -p /var/lib/tempo/traces /var/lib/tempo/generator/wal /etc/tempo && \
    chmod -R 777 /var/lib/tempo

# ============================================================================
# Install Grafana
# ============================================================================
RUN wget https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz && \
    tar -xzf grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz && \
    mv grafana-v${GRAFANA_VERSION} /usr/share/grafana && \
    rm grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz && \
    mkdir -p /var/lib/grafana /var/log/grafana /etc/grafana/provisioning/{dashboards,datasources,notifiers,plugins} && \
    chmod -R 777 /var/lib/grafana /var/log/grafana /etc/grafana /usr/share/grafana

# ============================================================================
# Install Grafana Alloy (OpenTelemetry Collector)
# ============================================================================
RUN wget https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-linux-amd64.zip && \
    apt-get update && apt-get install -y --no-install-recommends unzip && \
    unzip alloy-linux-amd64.zip && \
    mv alloy-linux-amd64 /usr/local/bin/alloy && \
    chmod +x /usr/local/bin/alloy && \
    rm alloy-linux-amd64.zip && \
    mkdir -p /etc/alloy /var/lib/alloy && \
    chmod -R 777 /etc/alloy /var/lib/alloy && \
    apt-get remove -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Configure Supervisor to manage all services
# ============================================================================
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ============================================================================
# Expose ports
# ============================================================================
# Prometheus
EXPOSE 9090
# Alertmanager
EXPOSE 9093
# Node Exporter
EXPOSE 9100
# Loki
EXPOSE 3100
# Tempo
EXPOSE 3200 4317 4318
# Grafana
EXPOSE 3000

# ============================================================================
# Health check
# ============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9090/-/healthy && \
        curl -f http://localhost:3100/ready && \
        curl -f http://localhost:3000/api/health || exit 1

# ============================================================================
# Start supervisor
# ============================================================================
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
