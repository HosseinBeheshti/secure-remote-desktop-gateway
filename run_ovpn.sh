#!/bin/bash

# OpenVPN Connection Script
# Establishes OpenVPN connection and disconnects on exit

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Load Configuration ---
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- Validate OpenVPN Configuration ---
if [[ -z "$OVPN_CONFIG_PATH" ]]; then
    print_error "OVPN_CONFIG_PATH not defined in $ENV_FILE"
    exit 1
fi

OVPN_CONFIG_NAME=$(basename "$OVPN_CONFIG_PATH")
OVPN_CLIENT_CONFIG="/etc/openvpn/client/${OVPN_CONFIG_NAME}"

if [[ ! -f "$OVPN_CLIENT_CONFIG" ]]; then
    print_error "OpenVPN config file not found: $OVPN_CLIENT_CONFIG"
    print_error "Run setup_ovpn.sh first"
    exit 1
fi

# Get the routing table name for OpenVPN
OVPN_TABLE="vpn_ovpn"
OVPN_FWMARK="201"

# --- Cleanup Function ---
cleanup() {
    print_message "Disconnecting OpenVPN..."
    
    # Kill OpenVPN process
    if [[ -n "$OVPN_PID" ]] && kill -0 "$OVPN_PID" 2>/dev/null; then
        kill "$OVPN_PID" 2>/dev/null || true
        wait "$OVPN_PID" 2>/dev/null || true
    fi
    
    # Clean up routing rules
    ip rule del fwmark $OVPN_FWMARK table $OVPN_TABLE 2>/dev/null || true
    ip route flush table $OVPN_TABLE 2>/dev/null || true
    ip route flush cache 2>/dev/null || true
    
    print_message "OpenVPN disconnected."
    exit 0
}

# Set trap to disconnect on exit
trap cleanup EXIT INT TERM

# --- Start OpenVPN ---
print_message "Starting OpenVPN connection..."
print_message "Config: $OVPN_CLIENT_CONFIG"

# Start OpenVPN in background
openvpn --config "$OVPN_CLIENT_CONFIG" --daemon ovpn-client --writepid /tmp/ovpn-client.pid

# Get PID
sleep 2
if [[ -f /tmp/ovpn-client.pid ]]; then
    OVPN_PID=$(cat /tmp/ovpn-client.pid)
else
    print_error "Failed to start OpenVPN"
    exit 1
fi

# Wait for connection
print_message "Waiting for OpenVPN connection..."
for i in {1..20}; do
    if ip addr show | grep -q tun0; then
        print_message "VPN interface tun0 is UP!"
        break
    fi
    sleep 1
done

# --- Verify Connection ---
if ip addr show | grep -q tun0; then
    TUN_IP=$(ip addr show tun0 | grep -oP 'inet \K[0-9.]+' | head -n1)
    print_message "=== OpenVPN Connected Successfully ==="
    echo ""
    echo -e "${YELLOW}VPN Interface:${NC} tun0"
    echo -e "${YELLOW}Local IP:${NC} $TUN_IP"
    echo -e "${YELLOW}Config:${NC} $OVPN_CONFIG_PATH"
    echo -e "${YELLOW}Routing Table:${NC} $OVPN_TABLE"
    echo -e "${YELLOW}Applications:${NC} $OVPN_APPS"
    echo ""
    
    # Test connectivity
    print_message "Testing external connectivity..."
    if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_message "✓ Internet is reachable through VPN"
    else
        print_warning "✗ Internet connectivity test failed"
    fi
    
    echo ""
    echo -e "${GREEN}VPN is active and will disconnect when you close this terminal${NC}"
    echo -e "Press ${YELLOW}Ctrl+C${NC} to disconnect and exit"
    echo ""
    echo -e "${GREEN}Useful Commands (in another terminal):${NC}"
    echo -e "  Check VPN status: ${GREEN}ip addr show tun0${NC}"
    echo -e "  Check routing: ${GREEN}ip route show table $OVPN_TABLE${NC}"
    echo -e "  View logs: ${GREEN}tail -f /tmp/ovpn-up.log${NC}"
    
    if [[ -n "$OVPN_APPS" ]]; then
        echo ""
        echo -e "${GREEN}Run apps through VPN:${NC}"
        for app in $OVPN_APPS; do
            echo -e "  ${GREEN}${app}-vpn${NC}"
        done
    fi
    echo ""
    
    # Keep the script running and monitor connection
    while kill -0 "$OVPN_PID" 2>/dev/null && ip addr show | grep -q tun0; do
        sleep 5
    done
    
    print_warning "VPN connection lost!"
else
    print_error "VPN connection failed!"
    print_error "Check config: $OVPN_CLIENT_CONFIG"
    print_error "Check logs: tail -f /tmp/ovpn-up.log"
    exit 1
fi

exit 0
