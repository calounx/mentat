# Secrets Management

This directory stores sensitive credentials for the observability stack. **Files in this directory are gitignored and will never be committed to version control.**

## Security Model

The secrets system uses a defense-in-depth approach:

1. **File System Permissions**: Secrets stored with 0600 permissions (owner read/write only)
2. **Optional Encryption**: Support for age/gpg encryption at rest
3. **Environment Variable Override**: Secrets can be provided via environment variables
4. **systemd Credentials**: Native systemd credential management for services (Debian 13+)
5. **No Process Exposure**: Secrets never passed as command-line arguments

## Quick Start

### Initialize Secrets

Run the initialization script to generate all required secrets:

```bash
cd /home/calounx/repositories/mentat/observability-stack
sudo ./scripts/init-secrets.sh
```

This will:
- Generate secure random passwords for all services
- Store them in `secrets/` with proper permissions
- Optionally encrypt them with age/gpg
- Create secret references for use in configs

### Manual Secret Creation

To manually create a secret:

```bash
# Generate a random password
openssl rand -base64 32 > secrets/smtp_password
chmod 600 secrets/smtp_password

# Or set a specific password
echo "my-secure-password" > secrets/grafana_admin_password
chmod 600 secrets/grafana_admin_password
```

## Secret Files

The following secrets are used by the observability stack:

| Secret File | Purpose | Used By |
|-------------|---------|---------|
| `smtp_password` | SMTP authentication for email alerts | Alertmanager |
| `grafana_admin_password` | Grafana admin user password | Grafana |
| `prometheus_basic_auth_password` | HTTP basic auth for Prometheus API | Nginx, Promtail |
| `loki_basic_auth_password` | HTTP basic auth for Loki API | Nginx, Promtail |
| `mysqld_exporter_password` | MySQL exporter database password | mysqld_exporter (per-host) |

## Usage in Configurations

### In global.yaml

Use secret references instead of plaintext:

```yaml
smtp:
  password: ${SECRET:smtp_password}

grafana:
  admin_password: ${SECRET:grafana_admin_password}
```

### In Shell Scripts

The common.sh library provides the `resolve_secret()` function:

```bash
source scripts/lib/common.sh

# Resolve a secret (tries environment variable, then file)
SMTP_PASS=$(resolve_secret "smtp_password")

# Use it in your script
configure_smtp "$SMTP_PASS"
```

### Environment Variable Override

Secrets can be overridden via environment variables (useful for CI/CD):

```bash
export OBSERVABILITY_SECRET_SMTP_PASSWORD="my-smtp-key"
./scripts/setup-observability.sh
```

The naming convention is: `OBSERVABILITY_SECRET_<secret_name_uppercase>`

## Encryption

For additional security, secrets can be encrypted at rest using age or gpg.

### Using age (recommended)

```bash
# Generate an age key (do this once)
age-keygen -o ~/.config/age/observability-key.txt

# Encrypt a secret
cat secrets/smtp_password | age -r $(age-keygen -y ~/.config/age/observability-key.txt) > secrets/smtp_password.age
rm secrets/smtp_password

# Decrypt when needed
age -d -i ~/.config/age/observability-key.txt secrets/smtp_password.age > secrets/smtp_password
```

### Using GPG

```bash
# Encrypt with GPG
gpg --encrypt --recipient your-email@example.com secrets/smtp_password

# Decrypt
gpg --decrypt secrets/smtp_password.gpg > secrets/smtp_password
```

## systemd Credentials (Debian 13+)

For production deployments on Debian 13+, use native systemd credentials:

```bash
# Encrypt credential for systemd
systemd-creds encrypt --name=smtp-password - < secrets/smtp_password > /etc/credstore.encrypted/smtp-password

# Service file automatically decrypts and loads
[Service]
LoadCredential=smtp-password:/etc/credstore.encrypted/smtp-password
Environment=SMTP_PASSWORD=%d/smtp-password
```

## Secret Rotation

To rotate a secret:

1. Generate new secret:
   ```bash
   openssl rand -base64 32 > secrets/smtp_password.new
   ```

2. Update the service configuration to use the new secret

3. Restart affected services:
   ```bash
   systemctl restart alertmanager
   ```

4. Replace old secret:
   ```bash
   mv secrets/smtp_password.new secrets/smtp_password
   chmod 600 secrets/smtp_password
   ```

5. Verify services are working with new secret

## Backup Considerations

Secrets are NOT stored in git. You must back them up separately:

### Encrypted Backup

```bash
# Create encrypted backup
tar -czf - secrets/ | age -r $(cat ~/.config/age/pubkey.txt) > observability-secrets-$(date +%Y%m%d).tar.gz.age

# Restore
age -d -i ~/.config/age/key.txt observability-secrets-20250101.tar.gz.age | tar -xzf -
```

### Password Manager

For small deployments, store secrets in a password manager:
- 1Password: Use secure notes or items with custom fields
- Bitwarden: Use secure notes with secret names as field labels
- KeePassXC: Create an entry per secret with attachments

## Security Best Practices

1. **Never commit secrets to git** - The .gitignore is configured to prevent this
2. **Use strong passwords** - Minimum 32 characters for automated secrets
3. **Limit access** - Only root and service users should access secrets/
4. **Encrypt backups** - Always encrypt secret backups
5. **Rotate regularly** - Change secrets every 90 days minimum
6. **Audit access** - Monitor who accesses secret files
7. **Use environment variables in CI/CD** - Don't store secrets in CI config files
8. **Enable disk encryption** - Use LUKS/dm-crypt for the secrets directory

## Troubleshooting

### Secret not found error

```
[ERROR] Secret not found: smtp_password
```

Solution: Create the secret file or set the environment variable:
```bash
echo "your-password" > secrets/smtp_password
chmod 600 secrets/smtp_password
```

### Permission denied

```
[ERROR] Cannot read secret file: Permission denied
```

Solution: Fix permissions:
```bash
sudo chmod 600 secrets/*
sudo chown root:root secrets/*
```

### Service fails to start after secret rotation

1. Check the new secret is valid:
   ```bash
   cat secrets/smtp_password
   ```

2. Verify service configuration was updated:
   ```bash
   systemctl status alertmanager
   journalctl -u alertmanager -n 50
   ```

3. Test the secret manually (e.g., SMTP):
   ```bash
   curl --user "username:$(cat secrets/smtp_password)" smtp://smtp-relay.brevo.com:587
   ```

## Migration from Plaintext

See `docs/SECRETS.md` for detailed migration instructions from plaintext configs.
