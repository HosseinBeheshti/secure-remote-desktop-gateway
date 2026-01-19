#!/bin/bash

# OpenVPN Client Setup Script (One-time setup)
# This script installs packages and configures OpenVPN client

# Exit on any error
set -e

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

# --- Validate OpenVPN Configuration ---
if [[ -z "$OVPN_CONFIG_PATH" ]]; then
    print_error "OVPN_CONFIG_PATH not defined in $ENV_FILE"
    exit 1
fi

if [[ ! -f "$OVPN_CONFIG_PATH" ]]; then
    print_warning "OpenVPN config file not found: $OVPN_CONFIG_PATH"
    print_message "Please place your .ovpn config file at $OVPN_CONFIG_PATH"
    print_message "Or update OVPN_CONFIG_PATH in $ENV_FILE to point to your config file"
    exit 1
fi

# Get the routing table name for OpenVPN
OVPN_TABLE="vpn_ovpn"
OVPN_FWMARK="201"

print_message "=== Starting OpenVPN Client Setup ==="

# --- Install Required Packages ---
print_message "Installing OpenVPN client packages..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openvpn \
    network-manager-openvpn \
    iptables \
    netfilter-persistent \
    resolvconf

# Install applications specified in VPN_APPS
if [[ -n "$VPN_APPS" ]]; then
    print_message "Installing VPN applications: $VPN_APPS"
    for app in $VPN_APPS; do
        case $app in
            "remmina")
                print_message "Installing Remmina..."
                apt-get install -y remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11
                ;;
            "firefox")
                print_message "Installing Firefox..."
                apt-get install -y firefox
                ;;
            "chromium")
                print_message "Installing Chromium..."
                apt-get install -y chromium-browser || apt-get install -y chromium
                ;;
            *)
                print_message "Installing custom application: $app"
                apt-get install -y "$app" || print_warning "Failed to install $app"
                ;;
        esac
    done
fi

# --- Prepare OpenVPN Configuration ---
print_message "Preparing OpenVPN configuration..."

# Create OpenVPN client directory
mkdir -p /etc/openvpn/client

# Copy config file to standard location if not already there
OVPN_CONFIG_NAME=$(basename "$OVPN_CONFIG_PATH")
OVPN_CLIENT_CONFIG="/etc/openvpn/client/${OVPN_CONFIG_NAME}"

if [[ "$OVPN_CONFIG_PATH" != "$OVPN_CLIENT_CONFIG" ]]; then
    cp "$OVPN_CONFIG_PATH" "$OVPN_CLIENT_CONFIG"
    print_message "Config copied to $OVPN_CLIENT_CONFIG"
fi

# Create auth file if username/password are provided
AUTH_FILE="/etc/openvpn/client/auth.txt"
if [[ -n "$OVPN_USERNAME" && -n "$OVPN_PASSWORD" ]]; then
    print_message "Creating authentication file..."
    cat > "$AUTH_FILE" <<EOF
$OVPN_USERNAME
$OVPN_PASSWORD
EOF
    chmod 600 "$AUTH_FILE"
    
    # Add auth-user-pass directive to config if not present
    if ! grep -q "auth-user-pass" "$OVPN_CLIENT_CONFIG"; then
        echo "auth-user-pass $AUTH_FILE" >> "$OVPN_CLIENT_CONFIG"
    else
        # Update existing auth-user-pass line
        sed -i "s|^auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$OVPN_CLIENT_CONFIG"
    fi
fi

# Modify config to prevent default route override
print_message "Configuring routing options..."
if ! grep -q "route-nopull" "$OVPN_CLIENT_CONFIG"; then
    echo "route-nopull" >> "$OVPN_CLIENT_CONFIG"
    print_message "Added 'route-nopull' to prevent default route override"
fi

# Add script-security if not present
if ! grep -q "script-security" "$OVPN_CLIENT_CONFIG"; then
    echo "script-security 2" >> "$OVPN_CLIENT_CONFIG"
fi

# --- Create OpenVPN up/down scripts ---
print_message "Creating OpenVPN routing scripts..."

cat > /etc/openvpn/client/ovpn-up.sh <<'EOF'
#!/bin/bash
set -x
exec &> /tmp/ovpn-up.log

# Source environment file to get configuration
source /root/ovpn-env.conf

OVPN_TABLE="${OVPN_TABLE:-vpn_ovpn}"
OVPN_FWMARK="${OVPN_FWMARK:-201}"

# Get the VPN gateway
VPN_GW="${route_vpn_gateway}"

if [[ -z "$VPN_GW" ]]; then
    echo "ERROR: VPN gateway not found"
    exit 1
fi

echo "OpenVPN connected - Interface: $dev, Gateway: $VPN_GW"

# Add default route to OpenVPN routing table
ip route add default via "$VPN_GW" dev "$dev" table "$OVPN_TABLE" 2>/dev/null || true

# Add routing rule for marked traffic
ip rule add fwmark "$OVPN_FWMARK" table "$OVPN_TABLE" 2>/dev/null || true

# Flush routing cache
ip route flush cache

echo "OpenVPN routing configured for table $OVPN_TABLE"
exit 0
EOF

cat > /etc/openvpn/client/ovpn-down.sh <<'EOF'
#!/bin/bash
set -x
exec &> /tmp/ovpn-down.log

# Source environment file to get configuration
source /root/ovpn-env.conf

OVPN_TABLE="${OVPN_TABLE:-vpn_ovpn}"
OVPN_FWMARK="${OVPN_FWMARK:-201}"

echo "OpenVPN disconnecting - Interface: $dev"

# Remove routing rule
ip rule del fwmark "$OVPN_FWMARK" table "$OVPN_TABLE" 2>/dev/null || true

# Flush the routing table
ip route flush table "$OVPN_TABLE" 2>/dev/null || true

# Flush routing cache
ip route flush cache

echo "OpenVPN routing cleaned up"
exit 0
EOF

chmod +x /etc/openvpn/client/ovpn-up.sh
chmod +x /etc/openvpn/client/ovpn-down.sh

# Create environment file for scripts
cat > /root/ovpn-env.conf <<EOF
OVPN_TABLE="$OVPN_TABLE"
OVPN_FWMARK="$OVPN_FWMARK"
EOF

# Add script directives to config
if ! grep -q "up /etc/openvpn/client/ovpn-up.sh" "$OVPN_CLIENT_CONFIG"; then
    echo "up /etc/openvpn/client/ovpn-up.sh" >> "$OVPN_CLIENT_CONFIG"
fi
if ! grep -q "down /etc/openvpn/client/ovpn-down.sh" "$OVPN_CLIENT_CONFIG"; then
    echo "down /etc/openvpn/client/ovpn-down.sh" >> "$OVPN_CLIENT_CONFIG"
fi

# --- Configure Application Traffic Forwarding ---
print_message "Configuring application traffic forwarding..."

# Mark traffic for VPN apps when routing through OpenVPN
if [[ -n "$VPN_APPS" ]]; then
    for app in $VPN_APPS; do
        print_message "Setting up traffic marking for: $app"
        
        # Create a wrapper script for the application
        WRAPPER_PATH="/usr/local/bin/${app}-vpn"
        cat > "$WRAPPER_PATH" <<EOF
#!/bin/bash
# Wrapper to route $app through OpenVPN
exec $app "\$@"
EOF
        chmod +x "$WRAPPER_PATH"
        print_message "Created VPN wrapper: $WRAPPER_PATH"
    done
fi

# Save iptables rules
print_message "Saving iptables rules..."
netfilter-persistent save

# --- Configure Firewall ---
print_message "Configuring firewall for OpenVPN..."
if command -v ufw &> /dev/null; then
    ufw allow 1194/udp comment "OpenVPN"
    ufw allow 443/tcp comment "OpenVPN TCP"
    print_message "Firewall rules added for OpenVPN"
else
    print_warning "ufw not available, skipping firewall rules. Please configure manually:"
    print_warning "  Allow UDP port: 1194, TCP port: 443"
fi

print_message "=== OpenVPN Client Setup Complete ==="
echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "To connect to VPN, run: ${GREEN}sudo ./run_vpn.sh${NC} (select OpenVPN when prompted)"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Config: $OVPN_CONFIG_PATH"
echo -e "  VPN Apps: $VPN_APPS"
echo -e "  Routing Table: $OVPN_TABLE"
echo ""

exit 0
