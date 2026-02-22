#!/bin/bash

# ==============================================================================
# Kolla-Ansible Full Stack Deployment Orchestrator (2025.2 Stable)
# ==============================================================================

set -e

# --- Configuration ---
KOLLA_ETC="/etc/kolla"
VENV_PATH="/opt/.venv"
SCRIPTS_DIR=$(pwd)
OPENSTACK_DIR="$SCRIPTS_DIR/openstack"

# --- Status Function ---
show_status() {
    echo "--- Deployment Environment Status ---"
    
    echo "Network Interfaces:"
    ip -brief addr show
    echo ""

    echo -n "Network Script: "
    [ -f "$SCRIPTS_DIR/network.sh" ] && echo "Found" || echo "Missing"
    
    echo -n "Docker Script:  "
    [ -f "$SCRIPTS_DIR/docker.sh" ] && echo "Found" || echo "Missing"

    echo -n "Ansible:        "
    [ -f "$VENV_PATH/bin/ansible" ] && "$VENV_PATH/bin/ansible" --version | head -n 1 || echo "Not installed"

    echo -n "Kolla-Ansible:  "
    [ -f "$VENV_PATH/bin/kolla-ansible" ] && echo "Installed (2025.2 Stable)" || echo "Not installed"

    echo -n "Kolla Config:   "
    [ -d "$KOLLA_ETC" ] && echo "Directory exists ($KOLLA_ETC)" || echo "Not found"
    
    echo -n "OpenStack CLI:  "
    [ -f "$VENV_PATH/bin/openstack" ] && echo "Installed" || echo "Not installed"

    echo ""
}

# --- All-In-One High Level Setup ---
run_full_environment() {
    echo "--- Initiating Full Environment Setup ---"
    
    # 0. Clean old build artifacts
    clean_temporary_files

    # 1. Run Network Setup
    if [ -f "$SCRIPTS_DIR/network.sh" ]; then
        echo "Executing Network Configuration..."
        sudo sh "$SCRIPTS_DIR/network.sh" setup
    else
        echo "Error: network.sh not found in $SCRIPTS_DIR"
        exit 1
    fi

    # 2. Run Docker Setup
    if [ -f "$SCRIPTS_DIR/docker.sh" ]; then
        echo "Executing Docker Configuration..."
        sudo sh "$SCRIPTS_DIR/docker.sh" setup
    else
        echo "Error: docker.sh not found in $SCRIPTS_DIR"
        exit 1
    fi

    # 3. Create OpenStack Workspace
    echo "--- Current Infrastructure Snapshot (ip a) ---"
    ip a
    echo ""

    mkdir -p "$OPENSTACK_DIR"
    
    # 4. Install Kolla Dependencies and Stack
    install_kolla_stack

    # 5. Final Deployment Phases
    configure_globals
    run_deploy
}

# --- Kolla Stack Installation ---
install_kolla_stack() {
    echo "--- Installing Kolla-Ansible (Stable 2025.2) ---"

    echo "Installing system build dependencies..."
    sudo apt update
    sudo apt install -y git python3-dev libffi-dev gcc libssl-dev libdbus-1-dev libdbus-glib-1-dev python3-venv

    echo "Creating Python Virtual Environment ($VENV_PATH)..."
    sudo mkdir -p "$VENV_PATH"
    sudo chown $USER:$USER "$VENV_PATH"
    python3 -m venv "$VENV_PATH"

    echo "Updating pip and installing Python dependencies..."
    "$VENV_PATH/bin/pip" install -U pip
    "$VENV_PATH/bin/pip" install -U docker dbus-python
    "$VENV_PATH/bin/pip" install git+https://opendev.org/openstack/kolla-ansible@stable/2025.2

    echo "Configuring Kolla directories..."
    sudo mkdir -p "$KOLLA_ETC"
    sudo chown $USER:$USER "$KOLLA_ETC"

    echo "Copying configuration files and inventory..."
    cp -r "$VENV_PATH/share/kolla-ansible/etc_examples/kolla/"* "$KOLLA_ETC/"
    cp "$VENV_PATH/share/kolla-ansible/ansible/inventory/all-in-one" "$OPENSTACK_DIR/all-in-one"

    echo "Modifying all-in-one inventory for local deployment..."
    # Ensure localhost uses the virtualenv's python, direct local connection, and explicit become
    sed -i "s/^localhost.*/localhost ansible_connection=local ansible_python_interpreter=$VENV_PATH\/bin\/python3 ansible_become=true/g" "$OPENSTACK_DIR/all-in-one"

    echo "Updating PATH to include virtual environment..."
    export PATH="$VENV_PATH/bin:$PATH"

    echo "Running Kolla-Ansible Dependency Installer..."
    kolla-ansible install-deps

    echo "Generating Kolla passwords..."
    kolla-genpwd

    echo "Linking binaries to /usr/local/bin for global access..."
    sudo ln -sf "$VENV_PATH/bin/ansible" /usr/local/bin/ansible
    sudo ln -sf "$VENV_PATH/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy
    sudo ln -sf "$VENV_PATH/bin/ansible-inventory" /usr/local/bin/ansible-inventory
    sudo ln -sf "$VENV_PATH/bin/kolla-ansible" /usr/local/bin/kolla-ansible
    sudo ln -sf "$VENV_PATH/bin/kolla-genpwd" /usr/local/bin/kolla-genpwd
    sudo ln -sf "$VENV_PATH/bin/ansible-playbook" /usr/local/bin/ansible-playbook

    echo "Patching Nova scheduler PID logic..."
    NOVA_PATCH_FILE="$VENV_PATH/share/kolla-ansible/ansible/roles/nova/tasks/refresh_scheduler_cell_cache.yml"
    if [ -f "$NOVA_PATCH_FILE" ]; then
        # Replacing the complex kill -HUP command with a cleaner exec pkill command
        sed -i 's/shell: "kill -HUP.*nova_scheduler.*"/shell: "{{ kolla_container_engine }} exec nova_scheduler pkill -HUP -f nova-scheduler"/g' "$NOVA_PATCH_FILE"
        echo "Patch applied successfully to Nova role."
    fi

    echo "--- Kolla-Ansible Stack Ready ---"
}

# --- Globals Configuration ---
configure_globals() {
    echo "--- Detecting Network Configuration ---"
    
    # 1. Auto-detect logical management interface (with default route)
    DETECTED_MGMT=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    
    # Fallback to hardcoded if detection fails
    MGMT_INTERFACE=${DETECTED_MGMT:-"enp0s31f6"}
    EXT_INTERFACE="dummy0"
    
    echo "Using Management Interface: $MGMT_INTERFACE"
    
    # 2. Dynamic VIP Calculation (Aiming for .250 in the detected subnet)
    DETECTED_IP=$(ip -4 addr show "$MGMT_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "192.168.0.1")
    SUBNET=$(echo "$DETECTED_IP" | cut -d. -f1-3)
    INTERNAL_VIP="${SUBNET}.250"
    
    echo "Detected Subnet: ${SUBNET}.0/24"
    echo "Dynamic VIP: $INTERNAL_VIP"

    # 3. Verify interfaces
    if ! ip link show "$MGMT_INTERFACE" >/dev/null 2>&1; then
        echo "Error: Interface $MGMT_INTERFACE not found!"
        exit 1
    fi
    
    if ! ip link show "$EXT_INTERFACE" >/dev/null 2>&1; then
        echo "Interface $EXT_INTERFACE not found! Creating now..."
        sudo sh "$SCRIPTS_DIR/network.sh" setup
    fi

    echo "Capturing network snapshot for globals.yml..."
    NETWORK_SNAPSHOT=$(ip a)

    echo "--- Ensuring Persistent Passwordless Sudo ---"
    # Even if sudo -n true works now (due to cache), we want the file to exist for Ansible
    if [ ! -f "/etc/sudoers.d/$USER" ]; then
        echo "Creating sudoers entry for $USER..."
        echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER" >/dev/null
        sudo chmod 0440 "/etc/sudoers.d/$USER"
    fi

    echo "--- Configuring globals.yml for Service Deployment ---"

    # 4. Generate a clean globals.yml from the Kolla template
    if [ -f "$VENV_PATH/share/kolla-ansible/etc_examples/kolla/globals.yml" ]; then
        cp "$VENV_PATH/share/kolla-ansible/etc_examples/kolla/globals.yml" "$KOLLA_ETC/globals.yml"
    fi

    # Define services and networking in globals.yml
    cat >> "$KOLLA_ETC/globals.yml" <<EOF

# --- Environment Network Snapshot (Generated during setup) ---
$(echo "$NETWORK_SNAPSHOT" | sed 's/^/# /')

# --- Essential Network Config ---
kolla_internal_vip_address: "$INTERNAL_VIP"
network_interface: "$MGMT_INTERFACE"
neutron_external_interface: "$EXT_INTERFACE"
neutron_dns_domain: "openstacklocal."
kolla_base_distro: "ubuntu"
openstack_release: "2025.2"

# --- Custom Enabled Services ---
enable_aodh: "yes"
enable_barbican: "yes"
enable_bifrost: "yes"
enable_blazar: "yes"
enable_ceilometer: "yes"
enable_cinder: "yes"
enable_cloudkitty: "yes"
enable_cyborg: "yes"
enable_designate: "yes"
enable_glance: "yes"
enable_gnocchi: "yes"
enable_heat: "yes"
enable_horizon: "yes"
enable_ironic: "yes"
enable_keystone: "yes"
enable_kuryr: "yes"
enable_magnum: "yes"
enable_manila: "yes"
enable_masakari: "yes"
enable_mistral: "yes"
enable_neutron: "yes"
enable_nova: "yes"
enable_octavia: "yes"
enable_skyline: "yes"
enable_skyline_apiserver: "yes"
enable_skyline_console: "yes"
enable_tacker: "yes"
enable_trove: "yes"
enable_valkey: "yes"
enable_watcher: "yes"
enable_zun: "yes"

ironic_dnsmasq_dhcp_ranges:
  - range: "192.168.0.200,192.168.0.220"

enable_cinder_backend_lvm: "yes"

EOF

    echo "globals.yml updated with requested services."
}

# --- Actual Deployment Execution ---
run_deploy() {
    echo "--- Starting OpenStack Deployment (All-In-One) ---"
    cd "$OPENSTACK_DIR"

    echo "Updating PATH to include virtual environment..."
    export PATH="$VENV_PATH/bin:$PATH"

    echo "Bootstrapping servers..."
    kolla-ansible bootstrap-servers -i ./all-in-one

    echo "Preparing Ironic agent files to pass prechecks..."
    mkdir -p /etc/kolla/config/ironic
    touch /etc/kolla/config/ironic/ironic-agent.kernel
    touch /etc/kolla/config/ironic/ironic-agent.initramfs
    sudo chown -R $USER:$USER /etc/kolla/config

    echo "Preparing Cinder LVM volume group..."
    sudo apt-get update >/dev/null
    sudo apt-get install -y lvm2 >/dev/null
    if ! sudo vgs cinder-volumes >/dev/null 2>&1; then
        echo "Creating 20G loopback file for cinder-volumes..."
        sudo truncate -s 20G /opt/cinder-volumes.img
        LOOP_DEV=$(sudo losetup -f --show /opt/cinder-volumes.img)
        sudo pvcreate "$LOOP_DEV"
        sudo vgcreate cinder-volumes "$LOOP_DEV"
    fi

    echo "Generating Octavia certificates..."
    kolla-ansible octavia-certificates -i ./all-in-one

    echo "Preparing Zun CNI directory..."
    sudo mkdir -p /opt/cni/bin

    echo "Running prechecks..."
    kolla-ansible prechecks -i ./all-in-one

    echo "Executing deployment (this may take 20-40 minutes)..."
    kolla-ansible deploy -i ./all-in-one

    echo "Installing OpenStack CLI client..."
    pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/2025.2

    echo "Running post-deploy configuration..."
    kolla-ansible post-deploy -i ./all-in-one

    echo "Initializing OpenStack environment (init-runonce)..."
    if [ -f "$VENV_PATH/share/kolla-ansible/init-runonce" ]; then
        # Ensure the script is executable and run it
        /bin/bash "$VENV_PATH/share/kolla-ansible/init-runonce"
    fi

    echo "--- OpenStack Deployment Complete ---"

    echo ""
    echo "=================================================================="
    echo "OpenStack Dashboard (Horizon): http://$INTERNAL_VIP"
    echo "Admin Username: admin"
    echo -n "Admin Password: "
    sudo grep "^keystone_admin_password:" /etc/kolla/passwords.yml | awk '{print $2}'
    echo "=================================================================="
}

# --- Utility: Cleanup Temp Files ---
clean_temporary_files() {
    echo "Cleaning up temporary build artifacts in /tmp..."
    sudo rm -rf /tmp/pip-*
    sudo rm -rf /tmp/ansible-*
    sudo rm -rf /tmp/kolla-*
}

# --- Cleanup Function ---
run_remove() {
    echo "--- Removing Kolla-Ansible Deployment Environment ---"

    echo "Removing symbolic links..."
    sudo rm -f /usr/local/bin/ansible
    sudo rm -f /usr/local/bin/kolla-ansible
    sudo rm -f /usr/local/bin/ansible-playbook

    echo "Removing Kolla configuration (/etc/kolla)..."
    sudo rm -rf "$KOLLA_ETC"

    echo "Removing Virtual Environment ($VENV_PATH)..."
    sudo rm -rf "$VENV_PATH"

    echo "Removing OpenStack directory ($OPENSTACK_DIR)..."
    sudo rm -rf "$OPENSTACK_DIR"

    if [ -f "$SCRIPTS_DIR/docker.sh" ]; then
        sudo sh "$SCRIPTS_DIR/docker.sh" remove
    fi

    if [ -f "$SCRIPTS_DIR/network.sh" ]; then
        sudo sh "$SCRIPTS_DIR/network.sh" remove
    fi

    # Final cleanup of temp files
    clean_temporary_files

    echo "--- Removal Complete ---"
}

# --- Execution Logic ---
case "$1" in
    all-in-one|"")
        run_full_environment
        show_status
        ;;
    install-stack)
        install_kolla_stack
        show_status
        ;;
    deploy)
        configure_globals
        run_deploy
        show_status
        ;;
    remove)
        run_remove
        show_status
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {all-in-one|install-stack|deploy|remove|status}"
        exit 1
        ;;
esac
