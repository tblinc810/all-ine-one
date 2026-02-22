#!/bin/bash

# ==============================================================================
# Kolla-Ansible Network Configuration & Validation Script
# ==============================================================================
# Purpose: Prepares system for Kolla-Ansible All-In-One or Multinode deployments.
# ==============================================================================

set -e

# --- Status Functions ---
show_status() {
    echo "--- Current Network Status ---"
    ip -brief addr show
    echo ""
    echo "--- Kolla Interface Detection ---"
    ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'
    echo ""
    echo "--- IP Forwarding Status ---"
    sysctl net.ipv4.ip_forward
    echo ""
    echo "--- Kolla Custom Sysctl Parameters ---"
    if [ -f /etc/sysctl.d/60-kolla-network.conf ]; then
        cat /etc/sysctl.d/60-kolla-network.conf
    else
        echo "No Kolla optimizations detected. System is using default kernel parameters."
    fi
}

# --- Setup Function ---
run_setup() {
    echo "--- Checking Network Interfaces ---"
    ip -brief addr show

    echo "--- Optimizing Network Kernel Parameters (sysctl) ---"
    sudo tee /etc/sysctl.d/60-kolla-network.conf <<EOF
# Increase the range of ephemeral ports
net.ipv4.ip_local_port_range = 1024 65535

# Increase the maximum number of open file descriptors
fs.file-max = 6553500

# Increase maximum queued connections
net.core.somaxconn = 10000

# Increase the maximum number of neighbor table entries for mesh
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
EOF

    sudo sysctl --system

    echo "--- Configuring IP Forwarding ---"
    sudo sysctl -w net.ipv4.ip_forward=1

    echo "--- Creating Dummy Network Interface (dummy0) ---"
    if [ -d "/etc/netplan" ]; then
        echo "Configuring Netplan for dummy0..."
        sudo tee /etc/netplan/99-kolla-dummy.yaml <<EOF
network:
  version: 2
  ethernets:
    dummy0:
      critical: true
      dhcp4: false
      dhcp6: false
EOF
        sudo chmod 600 /etc/netplan/99-kolla-dummy.yaml
        sudo netplan apply || echo "Netplan apply failed, trying alternative methods..."
    fi

    echo "Configuring systemd service for dummy0..."
    sudo tee /etc/systemd/system/dummy-dev.service <<EOF
[Unit]
Description=Kolla-Ansible Dummy Network Interface
After=network.target

[Service]
Type=oneshot
ExecStartPre=-/sbin/modprobe dummy
ExecStart=-/sbin/ip link add dummy0 type dummy
ExecStart=/sbin/ip link set dummy0 up
ExecStop=/sbin/ip link delete dummy0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable dummy-dev.service
    sudo systemctl start dummy-dev.service
    echo "dummy-dev.service configured and started."

    echo "--- Checking for Bridge-utils and Net-tools ---"
    if dpkg -s bridge-utils net-tools >/dev/null 2>&1; then
        echo "Required packages are already installed."
    else
        echo "Installing missing packages..."
        sudo apt update || echo "Warning: apt update failed, attempting install anyway..."
        sudo apt install -y bridge-utils net-tools
    fi

    echo "--- Network Setup Suggestions ---"
    echo "Kolla-Ansible requires at least two interfaces (one for management, one for external/neutron)."
    echo "Current interfaces detected:"
    ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'

    echo "--- Network Configuration Complete ---"
}

# --- Cleanup Function ---
run_remove() {
    echo "--- Removing Kolla-Ansible Network Configuration ---"

    echo "Stopping and disabling dummy-dev.service..."
    sudo systemctl stop dummy-dev.service || true
    sudo systemctl disable dummy-dev.service || true
    sudo rm -f /etc/systemd/system/dummy-dev.service
    sudo systemctl daemon-reload

    if [ -f /etc/netplan/99-kolla-dummy.yaml ]; then
        echo "Removing Netplan configuration for dummy0..."
        sudo rm -f /etc/netplan/99-kolla-dummy.yaml
        sudo netplan apply || echo "Netplan apply failed (expected if dummy0 was already gone)."
    fi

    echo "Deleting dummy0 interface (if it exists)..."
    sudo ip link delete dummy0 2>/dev/null || true

    echo "Removing sysctl optimizations..."
    sudo rm -f /etc/sysctl.d/60-kolla-network.conf
    sudo sysctl --system

    echo "Disabling IP forwarding (setting to 0)..."
    sudo sysctl -w net.ipv4.ip_forward=0

    echo "--- Removal Complete ---"
}

# --- Execution Logic ---
# Defaults to 'setup' (All-In-One behavior) if no argument is provided.
case "$1" in
    setup|all-in-one|"")
        run_setup
        show_status
        ;;
    show)
        show_status
        ;;
    remove)
        run_remove
        show_status
        ;;
    *)
        echo "Usage: $0 {setup|show|remove|all-in-one}"
        exit 1
        ;;
esac
