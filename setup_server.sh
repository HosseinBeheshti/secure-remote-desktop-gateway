#!/bin/bash

# Master Setup Script for Secure Remote Desktop Gateway
# This script orchestrates all setup scripts in the correct order
# Run with: sudo ./setup_server.sh

# Exit on any error
set -e

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

# --- Load Configuration ---
print_message "Loading configuration from workstation.env..."
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"
print_message "Configuration loaded successfully."

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- Check if all required scripts exist ---
REQUIRED_SCRIPTS=("setup_vnc.sh" "setup_virtual_router.sh" "setup_l2tp.sh" "setup_ovpn.sh")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "./$script" ]]; then
        print_error "Required script not found: $script"
        exit 1
    fi
    # Make sure scripts are executable
    chmod +x "./$script"
done

# --- Main Execution ---
print_header "Starting Secure Remote Desktop Gateway Setup"

# Step 1: Setup VNC Server with Users
print_header "Step 1/4: Setting up VNC Server and Users"
./setup_vnc.sh
if [[ $? -ne 0 ]]; then
    print_error "VNC setup failed!"
    exit 1
fi
print_message "✓ VNC setup completed successfully"

# Step 2: Setup Virtual Router
print_header "Step 2/4: Setting up Virtual Router"
./setup_virtual_router.sh
if [[ $? -ne 0 ]]; then
    print_error "Virtual Router setup failed!"
    exit 1
fi
print_message "✓ Virtual Router setup completed successfully"

# Step 3: Setup L2TP VPN (if configured)
if [[ " $VPN_LIST " =~ " l2tp " ]]; then
    print_header "Step 3/4: Setting up L2TP VPN"
    ./setup_l2tp.sh
    if [[ $? -ne 0 ]]; then
        print_error "L2TP VPN setup failed!"
        exit 1
    fi
    print_message "✓ L2TP VPN setup completed successfully"
else
    print_warning "Step 3/4: L2TP VPN not in VPN_LIST, skipping..."
fi

# Step 4: Setup OpenVPN (if configured)
if [[ " $VPN_LIST " =~ " ovpn " ]]; then
    print_header "Step 4/4: Setting up OpenVPN"
    ./setup_ovpn.sh
    if [[ $? -ne 0 ]]; then
        print_error "OpenVPN setup failed!"
        exit 1
    fi
    print_message "✓ OpenVPN setup completed successfully"
else
    print_warning "Step 4/4: OpenVPN not in VPN_LIST, skipping..."
fi

# --- Final Summary ---
print_header "Setup Complete!"
echo -e "${GREEN}All components have been successfully installed and configured!${NC}\n"

echo -e "${YELLOW}Summary:${NC}"
echo -e "  ✓ VNC Server with users"
echo -e "  ✓ Virtual Router for VPN traffic"
if [[ " $VPN_LIST " =~ " l2tp " ]]; then
    echo -e "  ✓ L2TP VPN configured"
fi
if [[ " $VPN_LIST " =~ " ovpn " ]]; then
    echo -e "  ✓ OpenVPN configured"
fi
echo ""

# Display VNC user information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}VNC Connection Details:${NC}"
echo -e "-----------------------------------------------------"

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -n "$username" ]]; then
        echo -e "  ${GREEN}User:${NC}       $username"
        echo -e "  ${GREEN}Password:${NC}   [configured]"
        echo -e "  ${GREEN}Address:${NC}    $IP_ADDRESS:$port (Display :$display)"
        echo -e "  ${GREEN}Resolution:${NC} $resolution"
        echo ""
    fi
done

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Connect to VNC using the details above"
echo -e "2. Run VPN: ${GREEN}sudo ./run_vpn.sh${NC} (interactive selection of VPN type and apps)"
echo -e "3. Check service status: systemctl status vncserver-<username>@<display>.service"
echo ""

# --- Cleanup: Remove workstation.env from root ---
if [[ -f "/root/workstation.env" ]]; then
    print_message "Removing workstation.env from root directory for security..."
    rm -f /root/workstation.env
    print_message "✓ Configuration file cleaned up"
fi

echo -e "${GREEN}Setup completed at $(date)${NC}"

exit 0
