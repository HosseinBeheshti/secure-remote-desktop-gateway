#!/bin/bash
# Simplified Remmina VPN troubleshooting script

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Source configuration file
GATEWAY_CONFIG="./gateway_config.sh"
if [[ -f "$GATEWAY_CONFIG" ]]; then
    source "$GATEWAY_CONFIG"
    print_message "Configuration loaded from $GATEWAY_CONFIG"
else
    print_error "Configuration file not found: $GATEWAY_CONFIG"
    exit 1
fi

print_message "=== Remmina VPN Route Check ==="

# 1. Check VPN status
print_message "1. Checking VPN status..."
if ! ip addr show | grep -q ppp0; then
    print_error "VPN interface ppp0 not found. VPN is disconnected."
    print_message "To reconnect VPN, run:"
    print_message "sudo ipsec restart && echo 'c l2tpvpn' | sudo tee /var/run/xl2tpd/l2tp-control"
    exit 1
else
    PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
    print_message "✓ VPN interface ppp0 is UP with IP: $PPP_LOCAL_IP"
fi

# 2. Check routing
print_message "2. Checking routing tables..."
print_message "Current routes:"
ip route | grep -E "(default|ppp0|${REMOTE_PC_IP})" || print_warning "No VPN routes found"

# Check if target is reachable via VPN
print_message "3. Testing connectivity to ${REMOTE_PC_IP}..."
if ping -c 2 -W 3 ${REMOTE_PC_IP} >/dev/null 2>&1; then
    print_message "✓ Target ${REMOTE_PC_IP} is reachable"
else
    print_warning "✗ Target ${REMOTE_PC_IP} is not reachable via current routing"
    
    # Add direct route via VPN
    print_message "Adding direct route via VPN..."
    PPP_GATEWAY=$(echo $PPP_LOCAL_IP | sed 's/\.[0-9]\+$/.1/')
    sudo ip route add ${REMOTE_PC_IP}/32 via $PPP_GATEWAY dev ppp0 2>/dev/null || true
    
    # Test again
    if ping -c 2 -W 3 ${REMOTE_PC_IP} >/dev/null 2>&1; then
        print_message "✓ Target is now reachable after adding route"
    else
        print_error "✗ Target still not reachable"
    fi
fi

# 4. Test RDP port
print_message "4. Testing RDP port 3389..."
if nc -zv ${REMOTE_PC_IP} 3389 2>/dev/null; then
    print_message "✓ RDP port 3389 is open on ${REMOTE_PC_IP}"
else
    print_warning "✗ RDP port 3389 is not accessible"
fi

# 5. Test Remmina connection
print_message "5. Testing Remmina connection..."
print_message "Attempting to connect to ${REMOTE_PC_IP} via RDP..."

# Create temporary Remmina connection
TEMP_PROFILE="/tmp/remmina_test_$(date +%s).remmina"
cat > "$TEMP_PROFILE" << EOF
[remmina]
password=
name=Test Connection
protocol=RDP
server=${REMOTE_PC_IP}:3389
username=${REMOTE_USERNAME}
domain=${REMOTE_DOMAIN}
resolution_mode=1
color_depth=32
sound=off
EOF

# Launch Remmina with temporary profile
print_message "Launching Remmina with test profile..."
remmina -c "$TEMP_PROFILE" &
REMMINA_PID=$!

# Wait a moment and check if Remmina is still running
sleep 3
if kill -0 $REMMINA_PID 2>/dev/null; then
    print_message "✓ Remmina launched successfully"
    print_message "Check if connection is working in the Remmina window"
else
    print_error "✗ Remmina failed to launch or connect"
fi

# Cleanup
rm -f "$TEMP_PROFILE"

print_message "=== Check Complete ==="
print_message "Current VPN route to target:"
ip route get ${REMOTE_PC_IP} 2>/dev/null || print_warning "No route found"

print_message "If connection fails, check:"
print_message "1. VPN is connected: ip addr show ppp0"
print_message "2. Target is reachable: ping ${REMOTE_PC_IP}"
print_message "3. RDP port is open: nc -zv ${REMOTE_PC_IP} 3389"
print_message "4. Credentials are correct in Remmina"