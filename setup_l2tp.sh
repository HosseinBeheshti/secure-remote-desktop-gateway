#!/bin/bash

# L2TP/IPsec VPN Setup Script (One-time setup)
# This script installs packages and configures L2TP/IPsec client

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

# --- Validate L2TP Configuration ---
if [[ -z "$L2TP_SERVER_IP" || -z "$L2TP_USERNAME" || -z "$L2TP_PASSWORD" ]]; then
    print_error "L2TP configuration incomplete in $ENV_FILE"
    print_error "Required: L2TP_SERVER_IP, L2TP_USERNAME, L2TP_PASSWORD"
    exit 1
fi

# Get the routing table name for L2TP
L2TP_TABLE="vpn_l2tp"
L2TP_FWMARK="200"

print_message "=== Starting L2TP/IPsec VPN Setup ==="

# --- Install Required Packages ---
print_message "Installing L2TP/IPsec VPN client packages..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    strongswan \
    xl2tpd \
    network-manager-l2tp \
    iptables \
    netfilter-persistent \
    netcat-openbsd

# Install applications specified in VPN_APPS
if [[ -n "$VPN_APPS" ]]; then
    print_message "Installing VPN applications: $VPN_APPS"
    for app in $VPN_APPS; do
        case $app in
            "xrdp")
                print_message "Installing xRDP server..."
                apt-get install -y xrdp
                systemctl enable xrdp
                if command -v ufw &> /dev/null; then
                    ufw allow 3389/tcp comment "xRDP"
                else
                    print_warning "ufw not available, skipping firewall rule for xRDP"
                fi
                print_message "xRDP installed and configured"
                ;;
            "remmina")
                print_message "Installing Remmina..."
                apt-get install -y remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11
                ;;
            "vinagre")
                print_message "Installing Vinagre VNC client..."
                apt-get install -y vinagre
                ;;
            "krdc")
                print_message "Installing KRDC remote desktop client..."
                apt-get install -y krdc
                ;;
            "anydesk")
                print_message "Installing AnyDesk..."
                if command -v wget &> /dev/null; then
                    wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add - 2>/dev/null || true
                    echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
                    apt-get update
                    apt-get install -y anydesk || print_warning "AnyDesk installation failed"
                else
                    print_warning "wget not available, skipping AnyDesk installation"
                    print_message "Install wget first: apt-get install -y wget"
                fi
                ;;
            *)
                print_message "Installing custom application: $app"
                apt-get install -y "$app" || print_warning "Failed to install $app"
                ;;
        esac
    done
fi

# --- Configure strongSwan (IPsec) ---
print_message "Configuring strongSwan (IPsec)..."

# Backup original config
if [[ -f /etc/ipsec.conf && ! -f /etc/ipsec.conf.backup ]]; then
    cp /etc/ipsec.conf /etc/ipsec.conf.backup
fi

cat > /etc/ipsec.conf <<EOF
config setup
  charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
  strictcrlpolicy=no
  uniqueids=yes

conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev1
  authby=secret
  ike=aes128-sha256-modp1024,aes256-sha256-modp1024,aes128-sha1-modp1024,aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha256,aes256-sha256,aes128-sha1,aes256-sha1,3des-sha1!

conn l2tpvpn
  keyexchange=ikev1
  left=%defaultroute
  auto=add
  authby=secret
  type=transport
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=${L2TP_SERVER_IP}
  dpdaction=clear
  dpddelay=30s
  dpdtimeout=120s
  ike=aes128-sha256-modp1024,aes256-sha256-modp1024,aes128-sha1-modp1024,aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha256,aes256-sha256,aes128-sha1,aes256-sha1,3des-sha1!
EOF

cat > /etc/ipsec.secrets <<EOF
${L2TP_SERVER_IP} %any : PSK '${L2TP_IPSEC_PSK}'
EOF
chmod 600 /etc/ipsec.secrets

print_message "strongSwan configured."

# --- Configure xl2tpd (L2TP) ---
print_message "Configuring xl2tpd (L2TP)..."

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
auth file = /etc/xl2tpd/xl2tp-secrets

[lac l2tpvpn]
lns = ${L2TP_SERVER_IP}
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
require authentication = yes
name = ${L2TP_USERNAME}
EOF

cat > /etc/ppp/options.l2tpd.client <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-chap
noccp
noauth
mtu 1280
mru 1280
noipdefault
usepeerdns
debug
connect-delay 5000
name ${L2TP_USERNAME}
password ${L2TP_PASSWORD}
EOF
chmod 600 /etc/ppp/options.l2tpd.client

print_message "xl2tpd configured."

# --- Create ip-up.d script for routing ---
print_message "Creating PPP ip-up script for routing..."

cat > /etc/ppp/ip-up.d/route-l2tp-apps <<EOF
#!/bin/sh
set -x
exec &> /tmp/route-l2tp-apps.log

if [ "\$IFNAME" = "ppp0" ]; then
    # Get the VPN gateway from environment or use configured one
    VPN_GATEWAY="${L2TP_PPP_GATEWAY}"
    
    # Add default route to L2TP routing table
    ip route add default via "\$VPN_GATEWAY" dev ppp0 table $L2TP_TABLE 2>/dev/null || true
    
    # Add routing rule for marked traffic
    ip rule add fwmark $L2TP_FWMARK table $L2TP_TABLE 2>/dev/null || true
    
    # Add specific route for remote PC if configured
    if [ -n "${REMOTE_PC_IP}" ]; then
        ip route add ${REMOTE_PC_IP}/32 via "\$VPN_GATEWAY" dev ppp0 2>/dev/null || true
    fi
    
    # Flush routing cache
    ip route flush cache
    
    echo "L2TP routing configured for table $L2TP_TABLE"
else
    echo "Interface \$IFNAME is not ppp0. Exiting."
fi
exit 0
EOF
chmod +x /etc/ppp/ip-up.d/route-l2tp-apps

print_message "PPP routing script created."

# --- Configure Application Traffic Forwarding ---
print_message "Configuring application traffic forwarding..."

# Mark traffic for VPN apps when routing through L2TP
if [[ -n "$VPN_APPS" ]]; then
    for app in $VPN_APPS; do
        print_message "Setting up traffic marking for: $app"
        
        # Mark traffic destined to remote PC
        if [[ -n "$REMOTE_PC_IP" ]]; then
            iptables -t mangle -A OUTPUT -d "${REMOTE_PC_IP}/32" -j MARK --set-mark $L2TP_FWMARK 2>/dev/null || true
        fi
    done
fi

# Save iptables rules
print_message "Saving iptables rules..."
netfilter-persistent save

# --- Configure Firewall ---
print_message "Configuring firewall for L2TP..."
if command -v ufw &> /dev/null; then
    ufw allow 500/udp comment "IPsec"
    ufw allow 1701/udp comment "L2TP"
    ufw allow 4500/udp comment "IPsec NAT-T"
    print_message "Firewall rules added for L2TP/IPsec"
else
    print_warning "ufw not available, skipping firewall rules. Please configure manually:"
    print_warning "  Allow UDP ports: 500, 1701, 4500"
fi

# --- Load Kernel Modules ---
print_message "Loading kernel modules..."
modprobe pppol2tp 2>/dev/null || modprobe l2tp_ppp 2>/dev/null || print_warning "L2TP module loading failed"

# --- Enable Services ---
print_message "Enabling VPN services..."
systemctl enable strongswan-starter
systemctl enable xl2tpd

# Restart strongswan to load new configuration
print_message "Restarting strongSwan to load configuration..."
systemctl restart strongswan-starter
sleep 2

print_message "=== L2TP/IPsec VPN Setup Complete ==="
echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "To connect to VPN, run: ${GREEN}sudo ./run_vpn.sh${NC} (select L2TP when prompted)"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Server: $L2TP_SERVER_IP"
echo -e "  Username: $L2TP_USERNAME"
echo -e "  VPN Apps: $VPN_APPS"
echo -e "  Routing Table: $L2TP_TABLE"
echo ""

exit 0
