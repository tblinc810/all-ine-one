Kolla-Ansible OpenStack Deployment Tools
========================================

This directory contains a specialized set of scripts designed to completely automate the complex requirements for **Kolla-Ansible OpenStack** deployments on fresh Ubuntu server environments (specifically tailored for the 2025.2 Stable release).

--- Scripts Overview ---

1. `deployment.sh` (The Main Orchestrator)
------------------------------------------
This is the master script. It calls the other required scripts, sets up the virtual environment, configures Kolla-Ansible, and runs the entire OpenStack deployment.
*   **Action**: Installs the **Stable 2025.2** branch of Kolla-Ansible from git.
*   **Result**: Creates an isolated Python virtual environment at `/opt/.venv`, initializes `/etc/kolla/`, generates a secure OpenStack Admin password, auto-detects networking, installs system dependencies (like LVM for Cinder and Octavia certs), and automatically deploys all enabled OpenStack services.

2. `network.sh` (Networking Engine)
-----------------------------------
Handles kernel optimizations and the creation of persistent networking interfaces required by OpenStack (Neutron).
*   **Action**: Optimizes Sysctl, enables IP Forwarding, and creates a persistent `dummy0` interface to handle external traffic routing.

3. `docker.sh` (Container Engine)
---------------------------------
Installs and optimizes Docker explicitly for OpenStack workloads.
*   **Action**: Installs Docker Engine, enforces the `overlay2` storage driver, sets aggressive log size limits, and configures Docker to restart automatically.

4. `tunnel.sh` (Cloudflare Tunnel Exposer)
------------------------------------------
Automates the process of exposing your private OpenStack Horizon Dashboard securely to a public domain via Cloudflare Tunnels (cloudflared).
*   **Action**: Installs the latest `cloudflared` binary, prompts you to log in to Cloudflare, creates a secure tunnel to your OpenStack internal VIP, manages kernel inotify limits for stability, and configures `cloudflared` to run completely in the background as a systemd service.

--- Quick Start (Full Setup) ---

To prepare and deploy a completely fresh system in one command:

    sh deployment.sh

Workflow executed:
1.  **Preparation**: Runs `network.sh` and `docker.sh` behind the scenes.
2.  **Environment Setup**: Installs Kolla-Ansible 2025.2 Stable in `/opt/.venv`.
3.  **Service Configuration**: Configures `globals.yml` to enable a massive suite of services (Aodh, Cinder, Nova, Skyline, Zun, Octavia, Heat, Manila, Magnum, Ironic, etc.).
4.  **Deployment**: 
    - `bootstrap-servers`
    - Cinder LVM, Octavia Certificates, and Ironic config initialization
    - `prechecks`
    - `deploy` (Full cluster rollout - takes 30-45 minutes)
5.  **Initialization**: 
    - Installs `python-openstackclient`.
    - Generates and displays the Horizon Admin URL and auto-generated OpenStack Admin Password.

--- Advanced Commands ---

Each script supports specific commands for manual modular control:

* `sh deployment.sh all-in-one` - Runs everything.
* `sh deployment.sh install-stack` - Installs Python venv and Kolla config without running deployment.
* `sh deployment.sh deploy` - Runs just the Kolla-Ansible deployment phase.
* `sh deployment.sh remove` - Uninstalls and safely cleans up all OpenStack containers, networks, and configuration files.
* `sh deployment.sh status` - Displays the status of your tools and network interfaces.
* `sh tunnel.sh` - Interactive script to bind Horizon to a public domain via Cloudflare.

--- Validation & Post-Deployment ---

Check your deployment host's health any time by running:
    sh deployment.sh status
    sh network.sh show
    sh docker.sh show

Once deployment is complete, your OpenStack Horizon Dashboard will be accessible via the exact IP address and password provided at the end of the script log.

If you want to access Horizon remotely over the internet, run:
    sh tunnel.sh

To interact with the OpenStack CLI locally:
    source /etc/kolla/admin-openrc.sh
    openstack server list
