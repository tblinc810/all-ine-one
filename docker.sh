#!/bin/bash

# ==============================================================================
# Kolla-Ansible Docker Installation & Configuration Script
# ==============================================================================
# Purpose: Prepares a new PC/Server for Kolla-Ansible by installing and 
#          optimizing Docker Engine.
# ==============================================================================

set -e

# Detect the real user (if running with sudo)
REAL_USER=${SUDO_USER:-$USER}

# --- Status Functions ---
show_status() {
    echo "--- Docker System Status ---"
    if command -v docker >/dev/null 2>&1; then
        echo "Docker Version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'Service not responding')"
        echo "Service State: $(systemctl is-active docker)"
        echo "User '$REAL_USER' Group Membership: $(groups $REAL_USER | grep -o 'docker' || echo 'NOT in docker group')"
        echo "Socket Permissions: $(ls -l /var/run/docker.sock | awk '{print $1}')"
        
        echo ""
        echo "--- Kolla-Ansible Optimizations (daemon.json) ---"
        if [ -f /etc/docker/daemon.json ]; then
            cat /etc/docker/daemon.json
        else
            echo "No custom Docker daemon configuration found."
        fi
    else
        echo "Docker is not installed on this system."
    fi
    echo ""
}

# --- Setup Function ---
run_setup() {
    echo "--- Preparing Fresh Docker Installation ---"
    
    # 1. Install prerequisites
    echo "Installing system prerequisites..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg lsb-release

    # 2. Add Docker's official GPG key
    echo "Configuring Docker GPG Key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # 3. Setup the repository
    echo "Setting up Docker Apt repository..."
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    # 4. Install Docker Engine
    echo "Installing Docker Engine and Plugins..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 5. Service Management
    echo "Enabling and starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker

    # 6. User Permissions
    echo "Configuring permissions for user: $REAL_USER"
    if ! getent group docker > /dev/null; then
        sudo groupadd docker
    fi
    sudo usermod -aG docker "$REAL_USER"
    sudo chmod 666 /var/run/docker.sock

    # 7. Kolla-Ansible Optimizations
    echo "Applying Kolla-Ansible Docker optimizations (daemon.json)..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2"
}
EOF

    echo "Restarting Docker to finalize setup..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    echo "--- Docker Setup Complete ---"
    echo "IMPORTANT: As a new install, please run 'newgrp docker' or logout/login for permissions to take effect."
}

# --- Cleanup Function ---
run_remove() {
    echo "--- Removing Docker and All Data ---"
    
    # Silently stop and disable services only if they exist
    if systemctl list-unit-files | grep -q "docker.socket"; then
        sudo systemctl stop docker.socket >/dev/null 2>&1 || true
        sudo systemctl disable docker.socket >/dev/null 2>&1 || true
    fi

    if systemctl list-unit-files | grep -q "docker.service"; then
        sudo systemctl stop docker >/dev/null 2>&1 || true
        sudo systemctl disable docker >/dev/null 2>&1 || true
    fi

    echo "Removing custom configuration and data files..."
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo rm -f /etc/apt/keyrings/docker.asc
    sudo rm -rf /etc/docker
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd

    echo "Purging Docker packages (if present)..."
    PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    # Filter list to only include installed packages to prevent apt error messages
    INSTALLED_PACKAGES=$(dpkg-query -W -f='${Package} ' $PACKAGES 2>/dev/null || true)
    
    if [ ! -z "$INSTALLED_PACKAGES" ]; then
        sudo apt purge -y $INSTALLED_PACKAGES >/dev/null 2>&1 || true
        sudo apt autoremove -y >/dev/null 2>&1 || true
    else
        echo "No Docker packages found to purge."
    fi

    echo "Cleaning up network artifacts..."
    sudo ip link delete docker0 2>/dev/null || true
    
    echo "--- Removal Complete ---"
}

# --- Permission Fix Function ---
run_perms() {
    echo "--- Manually Fixing Docker Permissions ---"
    
    # Ensure group exists
    if ! getent group docker > /dev/null; then
        echo "Creating docker group..."
        sudo groupadd docker
    fi

    echo "Adding user $REAL_USER to docker group..."
    sudo usermod -aG docker "$REAL_USER"

    echo "Ensuring /var/run/docker.sock is writable..."
    if [ -S /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock
        echo "Socket permissions set to 666."
    else
        echo "Warning: Docker socket not found. Is Docker running?"
    fi

    echo "Fixing /etc/docker directory permissions..."
    sudo chown root:docker /etc/docker || true
    sudo chmod 750 /etc/docker || true
    
    echo "--- Permissions Fix Complete ---"
}

# --- Execution Logic ---
# Defaults to 'setup' (All-In-One behavior) if no argument is provided.
case "$1" in
    setup|install|all-in-one|"")
        run_setup
        show_status
        ;;
    show|status)
        show_status
        ;;
    perms|chmod)
        run_perms
        show_status
        ;;
    remove)
        run_remove
        show_status
        ;;
    *)
        echo "Usage: $0 {setup|show|remove|perms|all-in-one}"
        exit 1
        ;;
esac
