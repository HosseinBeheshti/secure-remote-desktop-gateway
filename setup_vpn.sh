#!/bin/bash

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Source configuration file
gateway-config="./gateway-config.sh"
if [[ -f "$GATEWAY_CONFIG" ]]; then
    source "$GATEWAY_CONFIG"
    print_message "Configuration loaded from $GATEWAY_CONFIG"
else
    print_error "Configuration file not found: $GATEWAY_CONFIG"
    exit 1
fi

# --- Script Start ---

print_message "--- Starting L2TP/IPsec VPN client setup with Policy Routing for Remmina ---"

# --- Phase 1: File Creation ---

print_message "Configuring IP Forwarding..."
sudo sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
sudo sysctl -p

print_message "Creating Custom Routing Table 'vpn_remmina'..."
echo "200 vpn_remmina" | sudo tee -a /etc/iproute2/rt_tables

print_message "Configuring strongSwan (IPsec)..."
sudo mv /etc/ipsec.conf /etc/ipsec.conf.bak || true # Backup existing
sudo bash -c "cat > /etc/ipsec.conf <<EOF
config setup
  charondebug=\"ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2\"
  strictcrlpolicy=no
  uniqueids=yes

conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev1
  authby=secret
  # Try more common IKE/ESP proposals
  ike=aes128-sha256-modp1024,aes256-sha256-modp1024,aes128-sha1-modp1024,aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha256,aes256-sha256-modp1024,aes128-sha1,aes256-sha1,3des-sha1!

conn calnex
  keyexchange=ikev1
  left=%defaultroute
  auto=start
  authby=secret
  type=transport
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=${VPN_SERVER_PUBLIC_IP}
  dpdaction=clear
  dpddelay=30s
  dpdtimeout=120s
  # Force specific IKE/ESP proposals for this connection
  ike=aes128-sha256-modp1024,aes256-sha256-modp1024,aes128-sha1-modp1024,aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha256,aes256-sha256,aes128-sha1,aes256-sha1,3des-sha1!
EOF"

sudo bash -c "cat > /etc/ipsec.secrets <<EOF

${VPN_SERVER_PUBLIC_IP} %any : PSK '${IPSEC_PSK}'
EOF"
sudo chmod 600 /etc/ipsec.secrets

print_message "Configuring xl2tpd (L2TP)..."
sudo bash -c "cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
auth file = /etc/xl2tpd/xl2tp-secrets

[lac calnex]
lns = ${VPN_SERVER_PUBLIC_IP}
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
require authentication = yes
name = ${VPN_USERNAME}
EOF"

sudo bash -c "cat > /etc/ppp/options.l2tpd.client <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-chap
noccp
noauth
mtu 1280
mru 1280
noipdefault
# defaultroute # This line must be commented out for policy routing
usepeerdns
debug
connect-delay 5000
name ${VPN_USERNAME}
password ${VPN_PASSWORD}
EOF"
sudo chmod 600 /etc/ppp/options.l2tpd.client

print_message "Creating 'ip-up.d' script for policy routing..."
sudo bash -c "cat > /etc/ppp/ip-up.d/route-remmina-vpn <<EOF
#!/bin/sh
# This script adds a specific route to the 'vpn_remmina' table when ppp0 connects.
# It does NOT set the default route.

# Debugging
set -x
exec &> /tmp/route-remmina-vpn.log # Redirect all output to a log file

if [ \"\$IFNAME\" = \"ppp0\" ]; then
    VPN_GATEWAY=\"${VPN_PPP_GATEWAY_IP}\"
    
    # Add the default route for the custom table
    ip route add default via \"\$VPN_GATEWAY\" dev ppp0 table vpn_remmina
    
    # Add the rule to use the custom table for traffic originating from the Hetzner server
    ip rule add from ${SERVER_PUBLIC_IP} table vpn_remmina

    # Flush cache to ensure the new rule is applied
    ip route flush cache
else
    echo "Interface \$IFNAME is not ppp0. Exiting."
fi
exit 0
EOF"
sudo chmod +x /etc/ppp/ip-up.d/route-remmina-vpn

# --- Phase 2: Firewall & Services ---

print_message "Firewall Configuration (Remember to also configure Hetzner Cloud Console Firewall!)"

echo "Configuring firewall rules..."
sudo ufw allow 22/tcp # Ensure SSH is allowed
sudo ufw allow 500/udp
sudo ufw allow 1701/udp
sudo ufw allow 4500/udp
sudo ufw allow esp # This handles IP Protocol 50

# Check if netfilter-persistent is installed
if ! command -v netfilter-persistent &> /dev/null; then
    print_message "netfilter-persistent is not installed. Installing..."
    sudo apt install -y netfilter-persistent
fi

# Uncomment the line below ONLY if you want to enable UFW now.
# sudo ufw enable

print_message "Loading Kernel Modules for L2TP..."
# Try loading the module with a more generic name
sudo modprobe pppol2tp

# Check if pppol2tp module is loaded
if lsmod | grep -q pppol2tp; then
    print_message "pppol2tp module loaded successfully."
else
    print_warning "Failed to load pppol2tp module. Trying alternatives..."
    
    # Try installing extra modules and headers
    sudo apt install -y linux-modules-extra-$(uname -r) linux-headers-$(uname -r)
    
    # Try different module names
    for module in pppol2tp l2tp_ppp; do
        sudo modprobe $module
        if lsmod | grep -q $module; then
            print_message "$module module loaded successfully."
            break
        fi
    done
    
    # Final check
    if ! lsmod | grep -q "pppol2tp\|l2tp_ppp"; then
        print_warning "Failed to load any L2TP modules. Consider kernel upgrade."
        print_warning "Continuing but VPN functionality may be limited."
    fi
fi



print_message "Restarting strongSwan and xl2tpd services..."
sudo systemctl restart strongswan-starter
sudo systemctl restart xl2tpd

# --- Phase 3: Establish VPN & Configure Policy Routing ---

print_message "Initiating VPN Tunnel..."
sudo ipsec up calnex
echo "c calnex" | sudo tee /var/run/xl2tpd/l2tp-control

print_message "Adding iptables mark rule for Remmina traffic (to ${REMOTE_PC_IP})..."
sudo iptables -t mangle -A OUTPUT -d "${REMOTE_PC_IP}/32" -j MARK --set-mark 1

print_message "Saving iptables rules for persistence across reboots..."
# Check if netfilter-persistent is installed
if command -v netfilter-persistent &> /dev/null; then
    print_message "netfilter-persistent is installed. Saving iptables rules..."
    sudo netfilter-persistent save
else
    print_warning "netfilter-persistent not found. Skipping iptables save."
    print_warning "Please install netfilter-persistent to persist iptables rules across reboots."
fi


# Try to display the routing table with error handling
if sudo ip route list table vpn_remmina 2>/dev/null; then
    print_message "Routing table exists and is shown above."
else
    print_warning "Routing table 'vpn_remmina' exists but has no routes."
    print_message "Manually adding initial route to ensure table exists..."
    
    # Get ppp0 interface status
    if ip addr show | grep -q ppp0; then
        print_message "ppp0 interface exists, determining gateway..."
        
        # Get the local IP address assigned to ppp0
        PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
        
        # Determine the remote endpoint (gateway) for ppp0
        # In PPP, typically if local IP is x.x.x.2, the gateway is x.x.x.1
        if [[ ! -z "$PPP_LOCAL_IP" ]]; then
            print_message "Local PPP IP: $PPP_LOCAL_IP"
            # Extract the first three octets and add .1 for the gateway
            PPP_GATEWAY=$(echo $PPP_LOCAL_IP | sed 's/\.[0-9]\+$/.1/')
            
            print_message "Using detected PPP gateway: $PPP_GATEWAY"
            
            # Try to add the routes with the detected gateway
            sudo ip route add default via $PPP_GATEWAY dev ppp0 table vpn_remmina
            sudo ip rule add from ${SERVER_PUBLIC_IP} table vpn_remmina
            sudo ip route flush cache
            
            # Show the routing table again
            print_message "Updated routing table:"
            sudo ip route list table vpn_remmina
        else
            print_warning "Could not determine PPP IP address."
            print_message "Manual inspection required:"
            ip addr show ppp0
        fi
    else
        print_warning "ppp0 interface does not exist. VPN connection may not be established."
        print_message "Check VPN status with: sudo ipsec statusall"
    fi
fi

print_message "Remember to manually configure your Hetzner Cloud Firewall in their web console!"

print_message "--- Setup Complete ---"
print_message "Please verify the VPN connection and Remmina routing:"
print_message "1. Check IPsec status: sudo ipsec statusall"
print_message "2. Check xl2tpd logs: sudo journalctl -fu xl2tpd"
print_message "3. Test Remmina connection to ${REMOTE_PC_IP}."
print_message "4. Verify Remmina traffic with tcpdump: sudo tcpdump -i any -nn -v host ${REMOTE_PC_IP}"
print_message "5. Verify other traffic: curl ifconfig.me (should NOT show VPN IP)"

# Check Remmina routing
print_message "Checking Remmina routing..."
if grep -q "vpn_remmina" /etc/iproute2/rt_tables; then
    print_message "Routing table 'vpn_remmina' is registered in rt_tables."
else
    print_warning "Routing table 'vpn_remmina' is not registered in rt_tables file."
    print_message "Adding routing table entry..."
    echo "200 vpn_remmina" | sudo tee -a /etc/iproute2/rt_tables
fi