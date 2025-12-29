# Setting Up Sudo User for CHOM Deployment

For security best practices, CHOM deployment should use a dedicated sudo user with passwordless sudo instead of root.

## Why Not Root?

- **Security**: Limit exposure of root credentials
- **Audit Trail**: Better logging of actions performed
- **Best Practice**: Industry standard for production deployments
- **Principle of Least Privilege**: Only escalate when needed

## Quick Setup

### Option 1: Automated Setup (Recommended)

Run this on each VPS as root to create a deployment user:

```bash
# Run as root on your VPS
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh | bash
```

Or manually:

```bash
# SSH into your VPS as root
ssh root@your-vps-ip

# Download and run the setup script
wget https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh
chmod +x create-deploy-user.sh
./create-deploy-user.sh
```

### Option 2: Manual Setup

#### Step 1: Create Deployment User

```bash
# SSH into your VPS as root
ssh root@your-vps-ip

# Create user named 'deploy' (or your preferred name)
useradd -m -s /bin/bash deploy

# Set a strong password (REQUIRED for ssh-copy-id)
passwd deploy
# This password is needed when you run ssh-copy-id from your control machine
```

#### Step 2: Grant Sudo Privileges

```bash
# Add user to sudo group
usermod -aG sudo deploy

# Configure passwordless sudo
echo "deploy ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/deploy
chmod 0440 /etc/sudoers.d/deploy
```

#### Step 3: Configure SSH Key Authentication

On your **control machine** (where you run the deployment script):

```bash
# The deployment script will generate keys automatically at:
# chom/deploy/keys/chom_deploy_key

# Copy the public key to your VPS using ssh-copy-id (recommended):
ssh-copy-id -i keys/chom_deploy_key.pub deploy@your-vps-ip

# Or use your existing SSH key:
ssh-copy-id deploy@your-vps-ip

# You'll be prompted for the deploy user's password
# The script automatically sets proper permissions
```

**Note**: `ssh-copy-id` automatically handles:
- Creating the `.ssh` directory
- Setting correct permissions (700 for directory, 600 for authorized_keys)
- Appending the key (won't overwrite existing keys)

#### Step 4: Test Sudo Access

```bash
# SSH as deploy user
ssh deploy@your-vps-ip

# Test sudo without password
sudo whoami
# Should output: root (without asking for password)

# Test basic commands
sudo apt-get update
sudo systemctl status ssh

# Exit
exit
```

#### Step 5: (Optional) Disable Root SSH Login

For extra security, disable root SSH login:

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Change these lines:
PermitRootLogin no
PasswordAuthentication no

# Restart SSH
sudo systemctl restart sshd
```

**⚠️ Warning**: Only do this after verifying the deploy user works!

## Using with CHOM Deployment

### Update inventory.yaml

Edit `chom/deploy/configs/inventory.yaml`:

```yaml
observability:
  ip: "203.0.113.10"
  ssh_user: deploy  # Your sudo user (NOT root)
  ssh_port: 22
  hostname: "monitoring.example.com"

vpsmanager:
  ip: "203.0.113.20"
  ssh_user: deploy  # Your sudo user (NOT root)
  ssh_port: 22
  hostname: "manager.example.com"
```

### Deploy

The deployment script will automatically use `sudo` when needed:

```bash
./deploy-enhanced.sh all
```

The script internally runs commands like:
```bash
ssh deploy@vps-ip "sudo systemctl start prometheus"
```

## Verification Checklist

Before deploying, verify:

- [ ] Deployment user created on both VPS servers
- [ ] User has passwordless sudo configured
- [ ] SSH key authentication works
- [ ] Can SSH without password: `ssh deploy@vps-ip`
- [ ] Can run sudo commands: `ssh deploy@vps-ip "sudo whoami"`
- [ ] `inventory.yaml` updated with correct user
- [ ] SSH keys added to authorized_keys on both VPS

## Troubleshooting

### "Permission denied" when SSH-ing

```bash
# Check SSH key permissions on control machine
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Check authorized_keys on VPS
ssh deploy@vps-ip "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

### "sudo: a password is required"

```bash
# Verify sudoers file
sudo cat /etc/sudoers.d/deploy

# Should contain:
# deploy ALL=(ALL) NOPASSWD:ALL

# Check file permissions
ls -la /etc/sudoers.d/deploy
# Should be: -r--r----- (0440)
```

### User not in sudo group

```bash
# Add to sudo group
sudo usermod -aG sudo deploy

# Verify
groups deploy
# Should show: deploy sudo
```

### SSH key not working

```bash
# On VPS, check SSH logs
sudo tail -f /var/log/auth.log

# On control machine, try verbose SSH
ssh -v deploy@vps-ip
```

## Automated Setup Script

Create this script on your VPS to automate user creation:

```bash
#!/bin/bash
# create-deploy-user.sh

set -euo pipefail

USERNAME="${1:-deploy}"
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "Creating deployment user: $USERNAME"

# Create user
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "User $USERNAME created"
fi

# Set a password for initial SSH connection
echo "Set password for $USERNAME (needed for first ssh-copy-id):"
passwd "$USERNAME"

# Add to sudo group
usermod -aG sudo "$USERNAME"

# Configure passwordless sudo
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"
chmod 0440 /etc/sudoers.d/"$USERNAME"

# Create .ssh directory (ssh-copy-id will handle the rest)
mkdir -p /home/"$USERNAME"/.ssh
chmod 700 /home/"$USERNAME"/.ssh
chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

echo ""
echo "✓ User $USERNAME configured successfully!"
echo ""
echo "Next steps (from your control machine):"
echo "1. Copy your SSH key using:"
echo "   ssh-copy-id $USERNAME@$SERVER_IP"
echo ""
echo "2. Test SSH connection:"
echo "   ssh $USERNAME@$SERVER_IP"
echo ""
echo "3. Test sudo access:"
echo "   ssh $USERNAME@$SERVER_IP 'sudo whoami'"
echo ""
```

Save as `create-deploy-user.sh`, then run:

```bash
chmod +x create-deploy-user.sh
sudo ./create-deploy-user.sh deploy
```

## Security Best Practices

1. **Use SSH Keys Only**: Disable password authentication
2. **Strong Key**: Use RSA 4096 or Ed25519 keys
3. **Unique User**: Create a dedicated deployment user
4. **Firewall**: Limit SSH access to known IPs
5. **Fail2ban**: Install fail2ban to prevent brute force
6. **Audit Logs**: Regularly review sudo logs
7. **Key Rotation**: Rotate SSH keys periodically
8. **2FA** (Optional): Consider SSH 2FA for extra security

## Quick Reference

```bash
# On VPS (as root):
sudo useradd -m -s /bin/bash deploy
sudo usermod -aG sudo deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
sudo chmod 0440 /etc/sudoers.d/deploy
sudo passwd deploy  # Set password for ssh-copy-id

# On control machine:
ssh-copy-id deploy@vps-ip  # Will ask for password
ssh deploy@vps-ip "sudo whoami"  # Test (should output: root)
```

## Related Documentation

- **DEPLOYMENT-GUIDE.md** - Complete deployment procedure
- **README-ENHANCED.md** - Deployment script features
- **inventory.yaml** - Configuration example
