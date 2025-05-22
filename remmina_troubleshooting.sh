#!/bin/bash
# Troubleshooting script for Remmina connection issues

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Source configuration file
GATEWAY_CONFIG="./gateway-config.sh"
if [[ -f "$GATEWAY_CONFIG" ]]; then
    source "$GATEWAY_CONFIG"
    print_message "Configuration loaded from $GATEWAY_CONFIG"
else
    print_error "Configuration file not found: $GATEWAY_CONFIG"
    exit 1
fi

print_warning "⚠️ WARNING: This script modifies network routing."
print_warning "There is a risk of disconnecting your current VNC session."
print_warning "Make sure you have an alternative way to access this machine if VNC disconnects."
read -p "Press ENTER to continue or CTRL+C to abort..."

print_message "=== Remmina Connection Troubleshooting ==="

# Save VNC server IP to prevent disconnection
VNC_SERVER_IP=$(who | grep -oP '\(\K[0-9.]+(?=\))')
if [[ -n "$VNC_SERVER_IP" ]]; then
    print_message "Detected VNC connection from $VNC_SERVER_IP - will preserve this connection"
fi

# 1. Check VPN status
print_message "1. Checking VPN status..."
if ! ip addr show | grep -q ppp0; then
    print_error "VPN interface ppp0 not found. VPN might be disconnected."
    print_message "Try: sudo ipsec restart && echo 'c l2tpvpn' | sudo tee /var/run/xl2tpd/l2tp-control"
    exit 1
else
    print_message "VPN interface ppp0 exists."
fi

# 2. Check routing
print_message "2. Checking routing tables..."
print_message "Main routing table:"
ip route

print_message "VPN routing table:"
if ! sudo ip route show table vpn_remmina; then
    print_warning "VPN routing table is empty or doesn't exist"
    
    # Add specific route for the remote target
    print_message "Adding direct route to remote PC..."
    PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
    PPP_GATEWAY=$(echo $PPP_LOCAL_IP | sed 's/\.[0-9]\+$/.1/')
    sudo ip route add ${REMOTE_PC_IP}/32 via $PPP_GATEWAY dev ppp0
    
    # Try adding the routing rules again - ONLY for the specific remote PC
    print_message "Adding targeted policy routing rules..."
    sudo ip route add default via $PPP_GATEWAY dev ppp0 table vpn_remmina
    
    # Add rules ONLY for traffic to the remote PC, not all traffic
    sudo ip rule add to ${REMOTE_PC_IP}/32 table vpn_remmina
    
    # Preserve VNC connection if detected
    if [[ -n "$VNC_SERVER_IP" ]]; then
        print_message "Adding exception for VNC traffic from $VNC_SERVER_IP"
        sudo ip rule add from $VNC_SERVER_IP lookup main pref 10
    fi
    
    sudo ip route flush cache
fi

# 3. Check IP rules
print_message "3. Checking IP rules..."
sudo ip rule list

# 4. Check firewall rules
print_message "4. Checking firewall rules..."
sudo iptables -L OUTPUT -v
sudo iptables -t mangle -L OUTPUT -v

# 5. Try direct route (for RDP target only, not all traffic)
print_message "5. Adding direct route to ${REMOTE_PC_IP}..."
PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
PPP_GATEWAY=$(echo $PPP_LOCAL_IP | sed 's/\.[0-9]\+$/.1/')
sudo ip route add ${REMOTE_PC_IP}/32 via $PPP_GATEWAY dev ppp0 || true

# 6. Check connectivity
print_message "6. Testing connectivity to ${REMOTE_PC_IP}..."
echo "Ping test (might fail if ICMP is blocked):"
ping -c 4 ${REMOTE_PC_IP}

echo "Traceroute test:"
traceroute ${REMOTE_PC_IP}

echo "Port scan (checking if RDP port 3389 is open):"
nc -zv ${REMOTE_PC_IP} 3389 || print_warning "RDP port 3389 is not reachable"

# 7. Add rules for destination IP only
print_message "7. Adding specific rule for destination IP..."
sudo ip rule add to ${REMOTE_PC_IP}/32 table vpn_remmina
sudo ip route flush cache

print_message "=== Troubleshooting complete ==="
print_message "Try connecting with Remmina again."
print_message "If still not working, inspect traffic with:"
print_message "sudo tcpdump -i ppp0 host ${REMOTE_PC_IP} -nn"

print_warning "If your VNC session disconnected, reconnect and run:"
print_message "sudo ip rule del to ${REMOTE_PC_IP}/32 table vpn_remmina"
print_message "sudo ip route flush cache"