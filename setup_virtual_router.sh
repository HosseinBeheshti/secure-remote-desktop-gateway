#!/bin/bash

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

# --- Main Script ---

print_message "=== Setting up Virtual Routers for VPN Traffic Forwarding ==="

# Enable IP forwarding
print_message "Enabling IP forwarding..."
sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
sed -i '/^#net.ipv6.conf.all.forwarding=1/s/^#//' /etc/sysctl.conf
sysctl -p

# Backup rt_tables if not already backed up
if [[ ! -f /etc/iproute2/rt_tables.backup ]]; then
    print_message "Backing up original rt_tables..."
    cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.backup
fi

# Parse VPN list
if [[ -z "$VPN_LIST" ]]; then
    print_error "VPN_LIST not defined in $ENV_FILE"
    exit 1
fi

print_message "Configured VPN types: $VPN_LIST"

# Convert VPN_LIST to array
IFS=' ' read -ra VPN_ARRAY <<< "$VPN_LIST"
VPN_COUNT=${#VPN_ARRAY[@]}

print_message "Number of VPNs to configure: $VPN_COUNT"

# Starting table number
TABLE_NUM=${VR_TABLE_START:-200}

# Create routing tables for each VPN
for vpn_type in "${VPN_ARRAY[@]}"; do
    TABLE_NAME="vpn_${vpn_type}"
    
    print_message "Creating routing table '$TABLE_NAME' with ID $TABLE_NUM..."
    
    # Check if table already exists
    if grep -q "^$TABLE_NUM[[:space:]]*$TABLE_NAME" /etc/iproute2/rt_tables; then
        print_warning "Routing table '$TABLE_NAME' already exists, skipping..."
    else
        echo "$TABLE_NUM $TABLE_NAME" >> /etc/iproute2/rt_tables
        print_message "Routing table '$TABLE_NAME' created with ID $TABLE_NUM"
    fi
    
    # Create fwmark for this VPN (same as table number for simplicity)
    FWMARK=$TABLE_NUM
    print_message "VPN '$vpn_type' will use fwmark $FWMARK and table $TABLE_NAME"
    
    # Increment table number for next VPN
    TABLE_NUM=$((TABLE_NUM + 1))
done

# Install required networking tools
print_message "Installing required networking tools..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iproute2 \
    iptables \
    iptables-persistent \
    netfilter-persistent

# Display configured routing tables
print_message "=== Configured Routing Tables ==="
echo ""
grep "^[0-9].*vpn_" /etc/iproute2/rt_tables || print_warning "No VPN routing tables found"
echo ""

# Create helper script to show routing table status
print_message "Creating routing table status script..."
cat > /usr/local/bin/show-vpn-routes.sh << 'EOF'
#!/bin/bash
# Script to display VPN routing tables status

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== VPN Routing Tables Status ===${NC}\n"

# Find all VPN routing tables
VPN_TABLES=$(grep "^[0-9].*vpn_" /etc/iproute2/rt_tables | awk '{print $2}')

if [[ -z "$VPN_TABLES" ]]; then
    echo "No VPN routing tables configured."
    exit 0
fi

for table in $VPN_TABLES; do
    echo -e "${YELLOW}Table: $table${NC}"
    ip route show table $table 2>/dev/null || echo "  (empty)"
    echo ""
done

echo -e "${GREEN}=== Routing Rules ===${NC}"
ip rule show | grep -E "fwmark|lookup vpn_" || echo "No VPN routing rules configured"
echo ""

echo -e "${GREEN}=== Active VPN Interfaces ===${NC}"
ip addr show | grep -E "^[0-9]+: (ppp|tun|wg)" || echo "No VPN interfaces found"
EOF

chmod +x /usr/local/bin/show-vpn-routes.sh
print_message "Helper script created: /usr/local/bin/show-vpn-routes.sh"

# Summary
print_message "=== Virtual Router Setup Complete ==="
echo ""
echo -e "${YELLOW}Configured VPNs:${NC} ${GREEN}$VPN_LIST${NC}"
echo -e "${YELLOW}Number of routing tables:${NC} ${GREEN}$VPN_COUNT${NC}"
echo -e "${YELLOW}Table ID range:${NC} ${GREEN}${VR_TABLE_START:-200}-$((TABLE_NUM-1))${NC}"
echo ""
echo -e "To view routing tables: ${GREEN}show-vpn-routes.sh${NC}"
echo -e "To view all tables: ${GREEN}cat /etc/iproute2/rt_tables${NC}"
echo -e "To view specific table routes: ${GREEN}ip route show table vpn_<type>${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Run ${GREEN}run_l2tp.sh${NC} to configure L2TP VPN"
echo -e "  2. Run ${GREEN}run_ovpn.sh${NC} to configure OpenVPN"
echo ""

exit 0
