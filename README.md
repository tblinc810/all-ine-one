# Kolla-Ansible OpenStack Deployment Tools

This repository contains a specialized set of scripts designed to automate the complex requirements for **Kolla-Ansible OpenStack** deployments on fresh PC/Server environments.

## 🚀 Scripts Overview

### 1. `deployment.sh` (The Orchestrator)
This is the main entry point. It calls the other scripts and prepares the high-level Kolla-Ansible stack.
*   **Action**: Installs the **Stable 2025.2** branch from source.
*   **Result**: Creates an `openstack` folder, initializes `/etc/kolla/`, and generates passwords.

### 2. `network.sh` (Networking Engine)
Handles kernel optimizations and the creation of persistent interfaces.
*   **Action**: Optimizes Sysctl, enables IP Forwarding, and creates a persistent `dummy0` interface.

### 3. `docker.sh` (Container Engine)
Installs and optimizes Docker explicitly for OpenStack workloads.
*   **Action**: Installs Docker Engine, enforces `overlay2`, and sets log limits.

---

## 🏎 Quick Start (Full Setup)

To prepare a completely fresh system in one command:

```bash
sh deployment.sh
```

**Workflow executed:**
1.  **Preparation**: Runs `network.sh` and `docker.sh`.
2.  **Environment Setup**: Installs Kolla-Ansible 2025.2 Stable in `/opt/.venv`.
3.  **Service Configuration**: Configures `globals.yml` to enable a massive suite of services (Aodh, Cinder, Nova, Skyline, Zun, etc.).
4.  **Deployment**: 
    -   `bootstrap-servers`
    -   `prechecks`
    -   `deploy` (Full cluster rollout)
5.  **Initialization**: 
    -   Installs `python-openstackclient`.
    -   `post-deploy` logic.
    -   `init-runonce` to create default flavors and images.

---

## 🛠 Advanced Commands

Each script supports specific commands for manual control:

| Command | Usage | Description |
| :--- | :--- | :--- |
| **Setup** | `sh <script>.sh setup` | Explicitly runs the configuration routine. |
| **Show** | `sh <script>.sh show` | Displays the current status of that component. |
| **Perms** | `sh <script>.sh perms` | Manually fixes permissions (NICs or Docker socket). |
| **Remove** | `sh <script>.sh remove` | Cleans up and reverts changes for that component. |

---

## 📋 Validation

Check your environment any time with:
```bash
sh deployment.sh status
sh network.sh show
sh docker.sh show
```

---

## 🔍 Troubleshooting

*   **Permissions**: If Docker commands fail without sudo, run `newgrp docker`.
*   **Reboots**: Interfaces created by `network.sh` are persistent. If they go missing, check `systemctl status dummy-dev.service`.
