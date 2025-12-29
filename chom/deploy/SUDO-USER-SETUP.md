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

# Set a strong password (optional, since we'll use SSH keys)
passwd deploy
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
# The deployment script will generate keys automatically
# But you can also use your existing key:

# Copy your public key to the VPS
ssh-copy-id deploy@your-vps-ip

# Or manually:
cat ~/.ssh/id_rsa.pub | ssh deploy@your-vps-ip "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

On the **VPS**, set correct permissions:

```bash
# As the deploy user
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

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

echo "Creating deployment user: $USERNAME"

# Create user
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    echo "User $USERNAME created"
fi

# Add to sudo group
usermod -aG sudo "$USERNAME"

# Configure passwordless sudo
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"
chmod 0440 /etc/sudoers.d/"$USERNAME"

# Create .ssh directory
mkdir -p /home/"$USERNAME"/.ssh
chmod 700 /home/"$USERNAME"/.ssh
touch /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

echo ""
echo "✓ User $USERNAME configured successfully!"
echo ""
echo "Next steps:"
echo "1. Add your SSH public key to /home/$USERNAME/.ssh/authorized_keys"
echo "2. Test: ssh $USERNAME@<this-server-ip>"
echo "3. Test sudo: ssh $USERNAME@<this-server-ip> 'sudo whoami'"
echo ""
echo "Add your public key now? (paste it below, then press Ctrl+D)"
cat >> /home/"$USERNAME"/.ssh/authorized_keys
chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh/authorized_keys

echo ""
echo "✓ SSH key added! Test the connection:"
echo "  ssh $USERNAME@<this-server-ip>"
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
# Create user
sudo useradd -m -s /bin/bash deploy

# Add to sudo with passwordless
sudo usermod -aG sudo deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
sudo chmod 0440 /etc/sudoers.d/deploy

# Setup SSH
ssh-copy-id deploy@vps-ip

# Test
ssh deploy@vps-ip "sudo whoami"
```

## Related Documentation

- **DEPLOYMENT-GUIDE.md** - Complete deployment procedure
- **README-ENHANCED.md** - Deployment script features
- **inventory.yaml** - Configuration example
