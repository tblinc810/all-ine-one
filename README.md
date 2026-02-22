# Kolla-Ansible Network Configuration Tool

This repository contains `network.sh`, a specialized script designed to automate the complex networking requirements for **Kolla-Ansible OpenStack** deployments. 

It handles kernel optimization, interface persistence, and validation in a single pass.

---

## 🚀 Quick Start (All-In-One)

For a fresh installation on a new PC or server, simply run the script with sudo privileges:

```bash
sudo sh network.sh
```

**What this does:**
1.  **Optimizes Sysctl**: Sets ephemeral port ranges, file descriptors, and neighbor table thresholds.
2.  **Enables IP Forwarding**: Safely enables IPv4 routing required for Neutron.
3.  **Creates `dummy0`**: Deploys a dummy interface used for the Neutron external bridge.
4.  **Ensures Persistence**: Configures both **Netplan** and **Systemd** to ensure settings survive reboots.
5.  **Installs Dependencies**: Only runs `apt update` if `bridge-utils` or `net-tools` are missing.

---

## 🛠 Advanced Commands

The script supports explicit commands for lifecycle management:

| Command | Usage | Description |
| :--- | :--- | :--- |
| **Setup** | `sudo sh network.sh setup` | Explicitly runs the configuration routine. |
| **Show** | `sh network.sh show` | Displays interface status, forwarding state, and sysctl values. |
| **Remove** | `sudo sh network.sh remove` | Reverts all changes, deletes interfaces, and restores defaults. |

---

## 📋 System Validation

To verify your configuration at any time:
```bash
sh network.sh show
```

If the system is in its default state, the script will report:
> *No Kolla optimizations detected. System is using default kernel parameters.*

---

## 🔍 Troubleshooting

### Interface Missing After Reboot
If `dummy0` does not appear after a restart, check the persistence service:
```bash
sudo systemctl status dummy-dev.service
```

### APT Connection Errors
If you see connection warnings during setup, the script will automatically continue if the necessary packages (`bridge-utils`, `net-tools`) are already installed on your system.
