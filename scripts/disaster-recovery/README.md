# Disaster Recovery Scripts

Comprehensive disaster recovery and backup automation for the mentat infrastructure.

## Overview

This directory contains scripts and documentation for:

- **Offsite Backup**: Automated S3/B2/Wasabi backup uploads with encryption
- **Backup Verification**: Automated integrity checking and restore testing
- **Recovery Testing**: Regular DR drills to ensure procedures work
- **Monitoring Integration**: Prometheus metrics and alerting

## Quick Start

### 1. Initial Setup

```bash
# Install dependencies
apt-get install -y awscli gnupg tar gzip

# Configure S3 and encryption
cp backup-config.env.example backup-config.env
nano backup-config.env

# Setup GPG encryption
gpg --full-generate-key

# Test scripts
./backup-offsite.sh
./verify-backups.sh
./test-recovery.sh quick
```

### 2. Install Cron Jobs

```bash
# Add to root crontab
crontab -e

# Daily backups at 2 AM
0 2 * * * /opt/mentat/scripts/disaster-recovery/backup-offsite.sh

# Daily verification at 3 AM
0 3 * * * /opt/mentat/scripts/disaster-recovery/verify-backups.sh

# Weekly recovery test on Sunday at 4 AM
0 4 * * 0 /opt/mentat/scripts/disaster-recovery/test-recovery.sh database

# Monthly full test on 1st at 5 AM
0 5 1 * * /opt/mentat/scripts/disaster-recovery/test-recovery.sh full
```

## Files

### Scripts

- **backup-offsite.sh** - Upload backups to S3 with encryption
- **verify-backups.sh** - Verify backup integrity and perform restore tests
- **test-recovery.sh** - Automated DR testing and validation

### Documentation

- **SETUP.md** - Detailed setup and configuration guide
- **QUICK_REFERENCE.md** - Emergency procedures and commands
- **backup-config.env.example** - Configuration template

### Main Documentation

- **../../DISASTER_RECOVERY.md** - Complete disaster recovery runbook

## Usage

### Manual Backup

```bash
# Run offsite backup
./backup-offsite.sh

# Check status
echo $?  # 0 = success, 1 = failure
```

### Verify Backups

```bash
# Run verification
./verify-backups.sh

# View report
cat ../../reports/backup-verification/verification_*.txt | tail -50
```

### Test Recovery

```bash
# Quick test (database only)
./test-recovery.sh quick

# Database recovery test
./test-recovery.sh database

# Volume recovery test
./test-recovery.sh volumes

# Full recovery simulation
./test-recovery.sh full
```

## Configuration

### Environment Variables

Key configuration options in `backup-config.env`:

```bash
# S3 Configuration
S3_PROVIDER=s3              # s3, b2, wasabi, minio, custom
S3_BUCKET=mentat-backups
S3_REGION=us-east-1
S3_ACCESS_KEY=your-key
S3_SECRET_KEY=your-secret

# Encryption
BACKUP_ENCRYPTION_ENABLED=true
GPG_RECIPIENT=backup@arewel.com

# Retention
BACKUP_RETENTION_DAYS=30
BACKUP_FULL_RETENTION_DAYS=90

# Monitoring
METRICS_PUSHGATEWAY=http://mentat.arewel.com:9091
ALERT_EMAIL=admin@arewel.com
```

### Supported S3 Providers

- **AWS S3** - Amazon Web Services
- **Backblaze B2** - Cost-effective alternative
- **Wasabi** - Fast object storage
- **MinIO** - Self-hosted S3-compatible storage
- **Custom** - Any S3-compatible service

## Monitoring

### Metrics Exposed

All scripts push metrics to Prometheus Pushgateway:

```promql
# Offsite backup status (0 = failed, 1 = success)
backup_offsite_last_run_status

# Last backup timestamp
backup_offsite_last_run_timestamp

# Backup duration (seconds)
backup_offsite_last_run_duration_seconds

# Bytes uploaded
backup_offsite_last_run_bytes

# Verification results
backup_verification_passed
backup_verification_failed
backup_verification_warnings

# DR test results
dr_test_passed
dr_test_failed
dr_last_test_timestamp
```

### Prometheus Alerts

Alerts configured in:
```
../../observability-stack/modules/_core/backup_monitoring/alerts.yml
```

Key alerts:
- Backup job failed
- Backup not run in 24 hours
- Verification failures
- Storage capacity issues
- Encryption failures

## Recovery Procedures

### Emergency Database Restore

```bash
# 1. Download latest backup
aws s3 cp s3://mentat-backups/mysql/$(date +%Y-%m-%d)/latest.sql.gpg /tmp/

# 2. Decrypt
gpg --decrypt /tmp/latest.sql.gpg > /tmp/restore.sql

# 3. Restore
docker exec -i chom-mysql mysql -u root -p chom < /tmp/restore.sql
```

### Emergency Volume Restore

```bash
# 1. Download backup
aws s3 cp s3://mentat-backups/volumes/$(date +%Y-%m-%d)/backup.tar.gz.gpg /tmp/

# 2. Decrypt
gpg --decrypt /tmp/backup.tar.gz.gpg > /tmp/backup.tar.gz

# 3. Restore
docker run --rm \
    -v docker_app-storage:/data \
    -v /tmp:/backup \
    debian:12-slim \
    tar xzf /backup/backup.tar.gz -C /data
```

### Full System Recovery

See **DISASTER_RECOVERY.md** for complete procedures:
- VPS complete failure
- Database corruption
- Application data loss
- Security breach scenarios

## Testing

### Test Checklist

- [ ] Backups uploading to S3
- [ ] Encryption/decryption working
- [ ] Verification tests passing
- [ ] Database restore succeeds
- [ ] Volume restore succeeds
- [ ] Metrics being pushed
- [ ] Alerts configured
- [ ] Cron jobs running

### Monthly DR Drill

```bash
# Run full DR test
./test-recovery.sh full

# Review results
cat ../../reports/dr-tests/dr_test_*.txt | tail -100

# Update runbook with findings
```

## Troubleshooting

### Backup Upload Fails

```bash
# Check S3 connectivity
aws s3 ls s3://mentat-backups/

# Verify credentials
aws sts get-caller-identity

# Check logs
tail -100 /var/log/backups/offsite.log
```

### Encryption Fails

```bash
# Verify GPG key
gpg --list-keys backup@arewel.com

# Test encryption
echo "test" | gpg --encrypt --recipient backup@arewel.com | gpg --decrypt
```

### Restore Fails

```bash
# Verify backup integrity
gpg --decrypt backup.sql.gpg > backup.sql
head -20 backup.sql

# Check MySQL status
docker ps | grep mysql
docker logs chom-mysql
```

## Security

### Best Practices

1. **Encryption Keys**
   - Store GPG private keys offline
   - Use strong passphrases
   - Test key recovery regularly

2. **Access Control**
   - Restrict script execution to root
   - Use IAM roles with least privilege
   - Enable MFA on AWS account

3. **Configuration**
   - Never commit `backup-config.env` to git
   - Use 600 permissions on sensitive files
   - Rotate credentials regularly

4. **Monitoring**
   - Alert on backup failures
   - Monitor encryption status
   - Track backup age

## Support

### Documentation

- **Setup Guide**: SETUP.md
- **Quick Reference**: QUICK_REFERENCE.md
- **DR Runbook**: ../../DISASTER_RECOVERY.md

### Logs

- **Backup Logs**: /var/log/backups/offsite.log
- **Verification Logs**: /var/log/backups/verification.log
- **DR Test Logs**: /var/log/backups/dr-test.log

### Reports

- **Verification Reports**: ../../reports/backup-verification/
- **DR Test Reports**: ../../reports/dr-tests/

## Contributing

When updating DR scripts:

1. Test thoroughly in development
2. Update documentation
3. Run full DR drill
4. Update version numbers
5. Document changes in runbook

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-02 | Initial release with S3, encryption, verification, and testing |

## License

Internal use only - See LICENSE file in project root.

---

**Remember:** Regular testing is the key to successful disaster recovery!
