# ============================================================================
# Debian 13 VPS Simulator
# ============================================================================
# Simulates a vanilla Debian 13 VPS for testing deployment scripts
# Services run natively via systemd (no Docker inside)
# ============================================================================

FROM debian:13-slim

LABEL maintainer="CHOM Team"
LABEL description="Debian 13 VPS Simulator for deployment testing"

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker

# Install systemd and essential packages (minimal VPS baseline)
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    dbus \
    # Essential tools present on any VPS
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    procps \
    sudo \
    openssh-server \
    # Network tools
    iproute2 \
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    # Editors
    vim \
    nano \
    # Build essentials for some installers
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Configure systemd for container use
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    rm -f $(ls | grep -v systemd-tmpfiles-setup) && \
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -f /lib/systemd/system/basic.target.wants/* && \
    rm -f /lib/systemd/system/anaconda.target.wants/* && \
    rm -f /lib/systemd/system/plymouth* && \
    rm -f /lib/systemd/system/systemd-update-utmp*

# Mask problematic units for container environment
RUN systemctl mask \
    dev-hugepages.mount \
    sys-fs-fuse-connections.mount \
    systemd-logind.service \
    getty.target \
    console-getty.service

# Enable SSH
RUN systemctl enable ssh

# Create deployment directory
RUN mkdir -p /opt/deployment

# Set working directory
WORKDIR /opt/deployment

# Expose common ports
EXPOSE 22 80 443

# Use systemd as init
STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup", "/run", "/run/lock"]

CMD ["/lib/systemd/systemd"]
