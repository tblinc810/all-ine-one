#!/bin/sh

# tunnel.sh
# Automates the setup of a Cloudflare Tunnel (cloudflared) to securely 
# expose the OpenStack Horizon Dashboard to a custom domain.

set -e

# Default Horizon VIP (Modify if your VIP is different)
HORIZON_URL="http://192.168.0.250"

echo "=== Cloudflare Tunnel Setup for OpenStack Horizon ==="

# 1. Install cloudflared if not present
if ! command -v cloudflared &> /dev/null; then
    echo "Installing cloudflared..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared.deb
    rm cloudflared.deb
else
    echo "cloudflared is already installed."
fi

echo ""
echo "--- Step 1: Authentication ---"
echo "You need to log into your Cloudflare account to authorize this tunnel."
echo "Running login command..."
cloudflared tunnel login

echo ""
echo "--- Step 2: Create Tunnel ---"
read -p "Enter a name for your new tunnel (e.g., openstack-tunnel): " TUNNEL_NAME

# Create the tunnel and extract the tunnel UUID
CREATED_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 || true)
echo "$CREATED_OUTPUT"
TUNNEL_UUID=$(echo "$CREATED_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1)

if [ -z "$TUNNEL_UUID" ]; then
    echo "Error: Failed to obtain Tunnel UUID. Tunnel may already exist."
    # Try to grab it from list
    TUNNEL_UUID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}' | head -n 1)
fi

echo "Tunnel UUID: $TUNNEL_UUID"

echo ""
echo "--- Step 3: Configure Routing ---"
read -p "Enter the Cloudflare domain/subdomain you want to use (e.g., dashboard.yourdomain.com): " CUSTOM_DOMAIN

echo "Routing $CUSTOM_DOMAIN to $TUNNEL_NAME..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$CUSTOM_DOMAIN"

# Generate config.yml
mkdir -p ~/.cloudflared
CONFIG_FILE="$HOME/.cloudflared/config.yml"

echo "Generating config.yml for $TUNNEL_NAME..."
cat <<EOF > "$CONFIG_FILE"
tunnel: $TUNNEL_UUID
credentials-file: /etc/cloudflared/$TUNNEL_UUID.json

ingress:
  - hostname: $CUSTOM_DOMAIN
    service: $HORIZON_URL
  - service: http_status:404
EOF

echo "Configuration saved to $CONFIG_FILE"

echo ""
echo "--- Step 4: Install and Start Service ---"

echo "Increasing inotify watch limits to prevent systemd failures..."
sudo sysctl -w fs.inotify.max_user_watches=524288 > /dev/null
sudo sysctl -w fs.inotify.max_user_instances=512 > /dev/null
grep -q "^fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf > /dev/null
grep -q "^fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf > /dev/null

echo "Preparing system directory..."
sudo mkdir -p /etc/cloudflared
sudo cp "$CONFIG_FILE" /etc/cloudflared/config.yml  2>/dev/null || true
sudo cp "/home/$USER/.cloudflared/$TUNNEL_UUID.json" /etc/cloudflared/ 2>/dev/null || true

echo "Installing cloudflared as a system service..."
sudo cloudflared service install || echo "Service may already be installed. Proceeding to restart..."

sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared

echo ""
echo "==========================================================="
echo "Cloudflare Tunnel Setup Complete!"
echo "Your OpenStack Dashboard should now be accessible at:"
echo "https://$CUSTOM_DOMAIN"
echo "==========================================================="
