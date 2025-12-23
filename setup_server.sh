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

IFS=';' read -ra USER_ENTRIES <<< "$VNC_USERS"
for user_entry in "${USER_ENTRIES[@]}"; do
    IFS=':' read -r username password display resolution port <<< "$user_entry"
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
echo -e "2. For L2TP apps: Use run_l2tp.sh <app_name> from VNC session"
echo -e "3. For OpenVPN apps: Use run_ovpn.sh <app_name> from VNC session"
echo -e "4. Check service status: systemctl status vncserver-<username>@<display>.service"
echo ""
echo -e "${GREEN}Setup completed at $(date)${NC}"

exit 0
