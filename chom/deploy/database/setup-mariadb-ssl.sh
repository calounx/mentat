#!/bin/bash
################################################################################
# MariaDB SSL/TLS Certificate Setup Script
# Generates self-signed certificates for encrypted database connections
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SSL_DIR="${SSL_DIR:-/etc/mysql/ssl}"
CERT_DAYS="${CERT_DAYS:-3650}"  # 10 years
CERT_COUNTRY="${CERT_COUNTRY:-US}"
CERT_STATE="${CERT_STATE:-State}"
CERT_CITY="${CERT_CITY:-City}"
CERT_ORG="${CERT_ORG:-CHOM}"
CERT_OU="${CERT_OU:-Database}"
CERT_CN="${CERT_CN:-$(hostname -f)}"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       MariaDB SSL/TLS Certificate Setup                      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Create SSL directory
echo -e "${BLUE}[1/7]${NC} Creating SSL directory..."
mkdir -p "$SSL_DIR"
chmod 755 "$SSL_DIR"
echo -e "${GREEN}✓ Directory created: ${SSL_DIR}${NC}"
echo

# Generate CA key
echo -e "${BLUE}[2/7]${NC} Generating Certificate Authority (CA) key..."
openssl genrsa 4096 > "${SSL_DIR}/ca-key.pem" 2>/dev/null
chmod 600 "${SSL_DIR}/ca-key.pem"
echo -e "${GREEN}✓ CA key generated${NC}"
echo

# Generate CA certificate
echo -e "${BLUE}[3/7]${NC} Generating CA certificate..."
openssl req -new -x509 -nodes -days "$CERT_DAYS" \
    -key "${SSL_DIR}/ca-key.pem" \
    -out "${SSL_DIR}/ca-cert.pem" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${CERT_CN}-CA" \
    2>/dev/null
chmod 644 "${SSL_DIR}/ca-cert.pem"
echo -e "${GREEN}✓ CA certificate generated${NC}"
echo

# Generate server key
echo -e "${BLUE}[4/7]${NC} Generating server key..."
openssl req -newkey rsa:4096 -days "$CERT_DAYS" -nodes \
    -keyout "${SSL_DIR}/server-key.pem" \
    -out "${SSL_DIR}/server-req.pem" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${CERT_CN}" \
    2>/dev/null
chmod 600 "${SSL_DIR}/server-key.pem"
echo -e "${GREEN}✓ Server key generated${NC}"
echo

# Generate server certificate
echo -e "${BLUE}[5/7]${NC} Generating server certificate..."
openssl x509 -req -in "${SSL_DIR}/server-req.pem" -days "$CERT_DAYS" \
    -CA "${SSL_DIR}/ca-cert.pem" \
    -CAkey "${SSL_DIR}/ca-key.pem" \
    -set_serial 01 \
    -out "${SSL_DIR}/server-cert.pem" \
    2>/dev/null
chmod 644 "${SSL_DIR}/server-cert.pem"
rm -f "${SSL_DIR}/server-req.pem"
echo -e "${GREEN}✓ Server certificate generated${NC}"
echo

# Generate client key and certificate
echo -e "${BLUE}[6/7]${NC} Generating client key and certificate..."
openssl req -newkey rsa:4096 -days "$CERT_DAYS" -nodes \
    -keyout "${SSL_DIR}/client-key.pem" \
    -out "${SSL_DIR}/client-req.pem" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${CERT_CN}-client" \
    2>/dev/null

openssl x509 -req -in "${SSL_DIR}/client-req.pem" -days "$CERT_DAYS" \
    -CA "${SSL_DIR}/ca-cert.pem" \
    -CAkey "${SSL_DIR}/ca-key.pem" \
    -set_serial 02 \
    -out "${SSL_DIR}/client-cert.pem" \
    2>/dev/null

chmod 600 "${SSL_DIR}/client-key.pem"
chmod 644 "${SSL_DIR}/client-cert.pem"
rm -f "${SSL_DIR}/client-req.pem"
echo -e "${GREEN}✓ Client certificates generated${NC}"
echo

# Set ownership
echo -e "${BLUE}[7/7]${NC} Setting permissions..."
chown -R mysql:mysql "$SSL_DIR"
echo -e "${GREEN}✓ Permissions set${NC}"
echo

# Verify certificates
echo -e "${BLUE}Verifying certificates...${NC}"
openssl verify -CAfile "${SSL_DIR}/ca-cert.pem" "${SSL_DIR}/server-cert.pem" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Server certificate verified${NC}"
else
    echo -e "${RED}✗ Server certificate verification failed${NC}"
    exit 1
fi

openssl verify -CAfile "${SSL_DIR}/ca-cert.pem" "${SSL_DIR}/client-cert.pem" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Client certificate verified${NC}"
else
    echo -e "${RED}✗ Client certificate verification failed${NC}"
    exit 1
fi
echo

# Display certificate information
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Certificate Details:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "Location: ${SSL_DIR}"
echo "Valid for: ${CERT_DAYS} days (~$((CERT_DAYS/365)) years)"
echo
echo "CA Certificate:"
openssl x509 -in "${SSL_DIR}/ca-cert.pem" -noout -subject -dates
echo
echo "Server Certificate:"
openssl x509 -in "${SSL_DIR}/server-cert.pem" -noout -subject -dates
echo
echo "Client Certificate:"
openssl x509 -in "${SSL_DIR}/client-cert.pem" -noout -subject -dates
echo

# Generate configuration snippet
cat > "${SSL_DIR}/mariadb-ssl-config.cnf" <<EOF
# Add these lines to /etc/mysql/mariadb.conf.d/50-server.cnf or my.cnf

[mysqld]
# SSL/TLS Configuration
require_secure_transport = ON
ssl-ca   = ${SSL_DIR}/ca-cert.pem
ssl-cert = ${SSL_DIR}/server-cert.pem
ssl-key  = ${SSL_DIR}/server-key.pem
ssl-cipher = 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384'
tls-version = 'TLSv1.2,TLSv1.3'

[client]
ssl-ca   = ${SSL_DIR}/ca-cert.pem
ssl-cert = ${SSL_DIR}/client-cert.pem
ssl-key  = ${SSL_DIR}/client-key.pem
EOF

echo -e "${GREEN}✓ Configuration snippet saved to: ${SSL_DIR}/mariadb-ssl-config.cnf${NC}"
echo

# Next steps
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "1. Apply MariaDB configuration:"
echo "   cp ${SSL_DIR}/mariadb-ssl-config.cnf /etc/mysql/mariadb.conf.d/60-ssl.cnf"
echo
echo "2. Restart MariaDB:"
echo "   systemctl restart mariadb"
echo
echo "3. Verify SSL is enabled:"
echo "   mysql -e \"SHOW VARIABLES LIKE '%ssl%';\""
echo
echo "4. Test SSL connection:"
echo "   mysql -h localhost -u root -p --ssl-ca=${SSL_DIR}/ca-cert.pem"
echo
echo "5. For Laravel .env, add:"
echo "   MYSQL_ATTR_SSL_CA=${SSL_DIR}/ca-cert.pem"
echo "   MYSQL_ATTR_SSL_VERIFY_SERVER_CERT=false"
echo
echo "6. Require SSL for database users:"
echo "   ALTER USER 'chom'@'%' REQUIRE SSL;"
echo "   FLUSH PRIVILEGES;"
echo
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}SSL/TLS certificates generated successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
