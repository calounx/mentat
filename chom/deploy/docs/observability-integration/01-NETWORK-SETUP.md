# Observability Integration - Network Setup Guide

## Overview

This guide provides comprehensive instructions for establishing secure network connectivity between the Observability Stack (mentat) and CHOM Application (landsraad) for metrics collection and log shipping.

**Servers:**
- **mentat** (Observability): `51.254.139.78` (mentat.arewel.com)
- **landsraad** (CHOM): `51.77.150.96` (landsraad.arewel.com)

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Internet                              │
└──────────────┬──────────────────────────┬──────────────────┘
               │                          │
    ┌──────────▼─────────┐      ┌─────────▼──────────┐
    │ mentat.arewel.com  │      │landsraad.arewel.com│
    │  51.254.139.78     │      │  51.77.150.96      │
    ├────────────────────┤      ├────────────────────┤
    │                    │      │                    │
    │ Observability      │      │ CHOM Application   │
    │ - Prometheus       │◄─────┤ - Node Exporter    │
    │ - Loki             │◄─────┤ - PHP-FPM Exporter │
    │ - Grafana          │◄─────┤ - Nginx Exporter   │
    │ - AlertManager     │◄─────┤ - MySQL Exporter   │
    │                    │◄─────┤ - Redis Exporter   │
    └────────────────────┘      │ - Alloy Agent      │
                                │                    │
                                └────────────────────┘
```

## Phase 1: Connectivity Testing

### Step 1.1: Run Connectivity Test Script

Execute the comprehensive connectivity test from both servers:

```bash
# On mentat or landsraad
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/connectivity-test.sh

# With verbose output for debugging
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/connectivity-test.sh --verbose

# Test specific target
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/connectivity-test.sh --target 51.254.139.78
```

### Step 1.2: Verify Basic Connectivity

Test Layer 3 connectivity:

```bash
# Ping test (ICMP)
ping -c 5 51.254.139.78  # From landsraad to mentat
ping -c 5 51.77.150.96   # From mentat to landsraad

# Expected output: 0% packet loss, reasonable latency
```

### Step 1.3: DNS Resolution Verification

```bash
# Forward resolution
nslookup mentat.arewel.com
nslookup landsraad.arewel.com

# Reverse resolution
nslookup 51.254.139.78
nslookup 51.77.150.96

# Expected: Correct IP addresses and hostnames
```

### Step 1.4: Check Existing Network Configuration

```bash
# View network interfaces
ip addr show
ip link show

# View routing table
ip route show
ip route show table all

# Check for any existing firewall rules
sudo ufw status
sudo iptables -L -n -v | head -50

# Test connectivity to key ports
timeout 5 bash -c "echo > /dev/tcp/51.254.139.78/9090"  # Prometheus
timeout 5 bash -c "echo > /dev/tcp/51.77.150.96/9100"   # Node Exporter
```

## Phase 2: Firewall Configuration

### Step 2.1: Understanding the Security Model

The firewall rules implement **least privilege** principles:

1. **Default Deny**: All incoming traffic is denied by default
2. **Whitelist Model**: Only explicitly allowed ports/IPs are permitted
3. **Bidirectional Rules**: Different rules for each direction (pull vs push)

### Step 2.2: Configure Firewall on mentat (Observability)

**Incoming Rules (Allows Prometheus to scrape from landsraad):**

```bash
# Run firewall setup with auto-detection
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/setup-firewall.sh --role mentat

# Or do it manually:
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access
sudo ufw limit 22/tcp

# Allow scraping from CHOM server
sudo ufw allow from 51.77.150.96 to any port 9090 proto tcp comment 'Prometheus API from CHOM'
sudo ufw allow from 51.77.150.96 to any port 9009 proto tcp comment 'Prometheus Remote Write from CHOM'
sudo ufw allow from 51.77.150.96 to any port 3100 proto tcp comment 'Loki Log Ingestion from CHOM'
sudo ufw allow from 51.77.150.96 to any port 9100 proto tcp comment 'Node Exporter from CHOM'

# Grafana (public access for dashboards)
sudo ufw allow 3000/tcp

# Enable firewall
sudo ufw enable
```

### Step 2.3: Configure Firewall on landsraad (CHOM)

**Incoming Rules (Allows mentat to scrape metrics):**

```bash
# Run firewall setup with auto-detection
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/setup-firewall.sh --role landsraad

# Or do it manually:
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access
sudo ufw limit 22/tcp

# HTTP/HTTPS for application
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Allow Prometheus scraping from observability server
sudo ufw allow from 51.254.139.78 to any port 9100 proto tcp comment 'Node Exporter - Prometheus scrape'
sudo ufw allow from 51.254.139.78 to any port 9253 proto tcp comment 'PHP-FPM Exporter'
sudo ufw allow from 51.254.139.78 to any port 9113 proto tcp comment 'Nginx Exporter'
sudo ufw allow from 51.254.139.78 to any port 9121 proto tcp comment 'Redis Exporter'
sudo ufw allow from 51.254.139.78 to any port 9104 proto tcp comment 'MySQL Exporter'
sudo ufw allow from 51.254.139.78 to any port 8080 proto tcp comment 'CHOM App Metrics'

# Optional: Database/cache access from mentat
sudo ufw allow from 51.254.139.78 to any port 3306 proto tcp comment 'MySQL from mentat'
sudo ufw allow from 51.254.139.78 to any port 5432 proto tcp comment 'PostgreSQL from mentat'
sudo ufw allow from 51.254.139.78 to any port 6379 proto tcp comment 'Redis from mentat'

# Enable firewall
sudo ufw enable
```

### Step 2.4: Verify Firewall Rules

```bash
# View numbered rules
sudo ufw show numbered

# View status
sudo ufw status

# Test connectivity to each port
for port in 9090 9009 3100 9100 9253 9113; do
    echo "Testing port $port:"
    timeout 2 bash -c "echo > /dev/tcp/51.254.139.78/$port" && echo "  SUCCESS" || echo "  FAILED"
done
```

### Step 2.5: Firewall Troubleshooting

If connectivity tests fail after firewall configuration:

```bash
# Check if UFW is active
sudo ufw status

# View detailed UFW logs (if enabled)
sudo tail -f /var/log/ufw.log

# Check iptables rules directly
sudo iptables -L -n -v | grep -E "ACCEPT|REJECT"

# Temporarily allow all traffic for testing (CAUTION!)
sudo ufw default allow incoming
# Test connectivity
# Then restore security:
sudo ufw default deny incoming

# Reload UFW rules
sudo ufw reload

# Reset UFW (WARNING: removes all rules)
# sudo ufw reset
```

## Phase 3: Network Performance Analysis

### Step 3.1: Measure Latency

```bash
# Basic ping latency
ping -c 20 51.254.139.78

# Get min/avg/max/stddev statistics
ping -c 100 51.254.139.78 | tail -1

# Latency percentile analysis
for i in {1..100}; do ping -c 1 -W 1 51.254.139.78; done | grep time= | sed 's/.*time=//' | sort -n | tail -20
```

**Expected latency:** 1-50ms (same datacenter region)

### Step 3.2: Test Bandwidth

Using curl to estimate download speed:

```bash
# Download a large file and measure speed
time curl -O http://51.77.150.96/large-file.bin

# Upload speed test
time curl -T large-file.bin http://51.254.139.78/upload/
```

**Expected bandwidth:** 100+ Mbps (modern datacenter)

### Step 3.3: Trace Route

```bash
# Analyze network path to destination
traceroute -m 15 51.254.139.78

# Expected: 3-5 hops for same-region traffic
```

### Step 3.4: MTU (Maximum Transmission Unit) Testing

```bash
# Test MTU 1500 (standard Ethernet)
ping -M do -s 1472 51.254.139.78

# If fails, test smaller sizes
ping -M do -s 1000 51.254.139.78
ping -M do -s 500 51.254.139.78

# Expected: Should succeed with size 1472 (1500 - 28 byte IP/ICMP headers)
```

## Phase 4: Service Port Verification

### Required Ports by Function

| Service | Port | Protocol | Direction | Source | Purpose |
|---------|------|----------|-----------|--------|---------|
| Prometheus API | 9090 | TCP | Inbound (mentat) | landsraad | Metrics scraping |
| Prometheus Remote Write | 9009 | TCP | Inbound (mentat) | landsraad | Remote write push |
| Loki | 3100 | TCP | Inbound (mentat) | landsraad | Log ingestion |
| Node Exporter | 9100 | TCP | Inbound (landsraad) | mentat | System metrics |
| PHP-FPM Exporter | 9253 | TCP | Inbound (landsraad) | mentat | PHP metrics |
| Nginx Exporter | 9113 | TCP | Inbound (landsraad) | mentat | Web server metrics |
| Redis Exporter | 9121 | TCP | Inbound (landsraad) | mentat | Cache metrics |
| MySQL Exporter | 9104 | TCP | Inbound (landsraad) | mentat | Database metrics |
| CHOM App Metrics | 8080 | TCP | Inbound (landsraad) | mentat | Application metrics |
| Grafana | 3000 | TCP | Inbound (mentat) | Any | Dashboards |
| SSH | 22 | TCP | Inbound | Any | Remote access |
| HTTP | 80 | TCP | Inbound (landsraad) | Any | Web traffic |
| HTTPS | 443 | TCP | Inbound (landsraad) | Any | Secure web traffic |

### Step 4.1: Verify Service Listening Ports

On landsraad, verify exporters are listening:

```bash
# Check all listening ports
sudo ss -tlnp | grep LISTEN

# Expected output should show:
# - nginx on port 80, 443
# - PHP-FPM on port 9000
# - Node Exporter on port 9100
# - Other exporters on their respective ports
```

On mentat, verify observability stack ports:

```bash
# Check all listening ports
sudo ss -tlnp | grep LISTEN

# Expected output should show:
# - Prometheus on port 9090
# - Loki on port 3100
# - Grafana on port 3000
# - AlertManager on port 9093
```

## Phase 5: DNS and SSL/TLS Verification

### Step 5.1: DNS Configuration

```bash
# Verify DNS TTL
dig mentat.arewel.com +noall +answer
dig landsraad.arewel.com +noall +answer

# Check DNS propagation globally
nslookup mentat.arewel.com 8.8.8.8
nslookup landsraad.arewel.com 8.8.8.8

# Expected: All queries return correct IPs
```

### Step 5.2: SSL/TLS Certificate Validation

```bash
# Check certificate validity
openssl s_client -servername mentat.arewel.com -connect 51.254.139.78:443 </dev/null | openssl x509 -noout -dates -subject

# Check certificate chain
openssl s_client -servername mentat.arewel.com -connect 51.254.139.78:443 </dev/null | openssl x509 -noout -text | grep -A5 "Subject:"

# Expected: Valid dates, correct subject, no certificate errors
```

## Phase 6: Documentation and Verification

### Step 6.1: Create Network Baseline

```bash
# Capture current network state
mkdir -p /var/log/network-baseline

# Save network configuration
ip addr show > /var/log/network-baseline/ip-addr.txt
ip route show > /var/log/network-baseline/ip-route.txt
netstat -tlnp > /var/log/network-baseline/netstat.txt
sudo ufw show numbered > /var/log/network-baseline/ufw-rules.txt

# Verify connectivity
bash connectivity-test.sh > /var/log/network-baseline/connectivity-test.log
```

### Step 6.2: Create Network Documentation

```bash
# Generate comprehensive network report
sudo bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/setup-firewall.sh --role mentat
```

Output includes network topology, firewall rules, and security configuration.

## Troubleshooting Guide

### Issue: Cannot ping remote server

```bash
# 1. Check if ping is blocked by firewall
sudo ufw allow from 51.77.150.96 to any port 0:65535

# 2. Check ICMP rules
sudo iptables -L -n | grep ICMP

# 3. Check if interface is up
ip link show
```

### Issue: Port connectivity fails

```bash
# 1. Verify service is listening
sudo ss -tlnp | grep :PORT_NUMBER

# 2. Check firewall rule exists
sudo ufw show numbered | grep PORT_NUMBER

# 3. Check iptables specifically
sudo iptables -L -n | grep PORT_NUMBER

# 4. Test with telnet/nc
nc -zv 51.254.139.78 9090  # If nc installed
telnet 51.254.139.78 9090   # If telnet installed
```

### Issue: DNS resolution fails

```bash
# 1. Check /etc/resolv.conf
cat /etc/resolv.conf

# 2. Try different DNS server
nslookup mentat.arewel.com 8.8.8.8
nslookup mentat.arewel.com 1.1.1.1

# 3. Flush DNS cache (if systemd-resolved)
sudo systemctl restart systemd-resolved

# 4. Check DNS packet capture
sudo tcpdump -i eth0 -n 'udp port 53'
```

### Issue: High latency

```bash
# 1. Check for packet loss
ping -c 100 51.254.139.78 | grep "received"

# 2. Trace route to identify bottleneck
traceroute -m 20 51.254.139.78

# 3. Check MTU
ping -M do -s 1472 51.254.139.78

# 4. Monitor network traffic
sudo iftop -i eth0
sudo nethogs
```

## Security Best Practices

1. **Always use firewall rules**: Never leave ports open to the internet unnecessarily
2. **Implement rate limiting**: Use `ufw limit` for SSH and other administrative ports
3. **Regular audits**: Periodically review firewall rules and remove unused ones
4. **Encrypt connections**: Use HTTPS/TLS for all observability communications
5. **Monitor rule changes**: Log all firewall modifications for compliance
6. **Segment networks**: Isolate observability traffic from other services
7. **Use specific IPs**: Always whitelist specific server IPs, never use 0.0.0.0

## Next Steps

After successful network connectivity verification, proceed to:

1. **Prometheus Configuration** (see `02-PROMETHEUS-CONFIG.md`)
2. **Log Shipping Setup** (see `03-LOG-SHIPPING.md`)
3. **Verification and Testing** (see `04-VERIFICATION.md`)

## Quick Reference Commands

```bash
# Run all connectivity tests
bash connectivity-test.sh --verbose

# Setup firewall with auto-detection
sudo bash setup-firewall.sh

# View firewall status
sudo ufw status numbered

# Test specific port
timeout 2 bash -c "echo > /dev/tcp/TARGET_IP/PORT"

# Monitor network traffic
sudo watch -n 1 'netstat -tlnp | grep LISTEN'

# Check service health
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3100/ready
```

## Additional Resources

- UFW Documentation: https://help.ubuntu.com/community/UFW
- iptables Guide: https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
- Network Debugging: https://www.digitalocean.com/community/tutorials/how-to-troubleshoot-linux-networking-issues
