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
GATEWAY_CONFIG="./gateway_config.sh"
if [[ -f "$GATEWAY_CONFIG" ]]; then
    source "$GATEWAY_CONFIG"
    print_message "Configuration loaded from $GATEWAY_CONFIG"
else
    print_error "Configuration file not found: $GATEWAY_CONFIG"
    exit 1
fi

# Function to install applications/services
install_applications() {
    print_message "Installing applications and services..."
    
    # Base applications - always installed
    local base_apps="remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11"
    
    # Parse APPLICATION_LIST and install each application
    if [[ -n "$APPLICATION_LIST" ]]; then
        for app in $APPLICATION_LIST; do
            case $app in
                "remmina")
                    # Already included in base_apps
                    print_message "Remmina will be installed with base applications"
                    ;;
                "xrdp")
                    print_message "Installing xRDP server..."
                    sudo apt install -y xrdp
                    sudo systemctl enable xrdp
                    sudo ufw allow 3389/tcp comment "xRDP"
                    print_message "xRDP installed and configured"
                    ;;
                "vinagre")
                    print_message "Installing Vinagre VNC client..."
                    sudo apt install -y vinagre
                    ;;
                "krdc")
                    print_message "Installing KRDC remote desktop client..."
                    sudo apt install -y krdc
                    ;;
                "nomachine")
                    print_message "NoMachine requires manual installation - skipping automatic install"
                    print_warning "Download NoMachine from: https://www.nomachine.com/download"
                    ;;
                "anydesk")
                    print_message "Installing AnyDesk..."
                    wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add - 2>/dev/null || true
                    echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
                    sudo apt update
                    sudo apt install -y anydesk || print_warning "AnyDesk installation failed"
                    ;;
                "teamviewer")
                    print_message "TeamViewer requires manual installation - skipping automatic install"
                    print_warning "Download TeamViewer from: https://www.teamviewer.com/download/linux/"
                    ;;
                *)
                    print_message "Installing custom application: $app"
                    sudo apt install -y "$app" || print_warning "Failed to install $app"
                    ;;
            esac
        done
    fi
    
    # Install base applications
    print_message "Installing base remote desktop applications..."
    sudo apt install -y $base_apps
}

# Function to create application-specific routing rules
setup_application_routing() {
    if [[ -n "$APPLICATION_LIST" ]]; then
        print_message "Setting up application-specific routing..."
        
        for app in $APPLICATION_LIST; do
            case $app in
                "remmina"|"xrdp"|"vinagre"|"krdc")
                    print_message "Adding iptables mark rule for $app traffic to ${REMOTE_PC_IP}..."
                    # Mark traffic destined for the remote PC
                    sudo iptables -t mangle -A OUTPUT -d "${REMOTE_PC_IP}/32" -j MARK --set-mark 1
                    ;;
                *)
                    print_message "Generic routing setup for application: $app"
                    sudo iptables -t mangle -A OUTPUT -d "${REMOTE_PC_IP}/32" -j MARK --set-mark 1
                    ;;
            esac
        done
    else
        # Default Remmina rule for backward compatibility
        print_message "Adding default iptables mark rule for remote desktop traffic to ${REMOTE_PC_IP}..."
        sudo iptables -t mangle -A OUTPUT -d "${REMOTE_PC_IP}/32" -j MARK --set-mark 1
    fi
}

# Troubleshooting function
run_diagnostics() {
    print_message "=== VPN and Application Connectivity Check ==="

    # 1. Check VPN status
    print_message "1. Checking VPN status..."
    if ! ip addr show | grep -q ppp0; then
        print_error "VPN interface ppp0 not found. VPN is disconnected."
        print_message "To reconnect VPN, run:"
        print_message "sudo ipsec restart && echo 'c l2tpvpn' | sudo tee /var/run/xl2tpd/l2tp-control"
        return 1
    else
        PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
        print_message "✓ VPN interface ppp0 is UP with IP: $PPP_LOCAL_IP"
    fi

    # 2. Check routing
    print_message "2. Checking routing tables..."
    print_message "Current routes:"
    ip route | grep -E "(default|ppp0|${REMOTE_PC_IP})" || print_warning "No VPN routes found"

    # 3. Check if target is reachable via VPN
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
            return 1
        fi
    fi

    # 4. Test RDP port
    print_message "4. Testing RDP port 3389..."
    if command -v nc >/dev/null 2>&1; then
        if nc -zv ${REMOTE_PC_IP} 3389 2>/dev/null; then
            print_message "✓ RDP port 3389 is open on ${REMOTE_PC_IP}"
        else
            print_warning "✗ RDP port 3389 is not accessible"
        fi
    else
        print_warning "netcat (nc) not installed - cannot test RDP port"
        sudo apt install -y netcat-openbsd
    fi

    # 5. Test applications
    print_message "5. Testing installed applications..."
    
    if [[ -n "$APPLICATION_LIST" ]]; then
        for app in $APPLICATION_LIST; do
            case $app in
                "remmina")
                    if command -v remmina >/dev/null 2>&1; then
                        print_message "✓ Remmina is installed and available"
                        print_message "To test Remmina: remmina -c rdp://${REMOTE_PC_IP}"
                    else
                        print_warning "✗ Remmina not found"
                    fi
                    ;;
                "xrdp")
                    if systemctl is-active --quiet xrdp; then
                        print_message "✓ xRDP service is running"
                        print_message "xRDP available on port 3389"
                    else
                        print_warning "✗ xRDP service is not running"
                        print_message "Start with: sudo systemctl start xrdp"
                    fi
                    ;;
                "vinagre")
                    if command -v vinagre >/dev/null 2>&1; then
                        print_message "✓ Vinagre is installed"
                        print_message "To test Vinagre: vinagre rdp://${REMOTE_PC_IP}"
                    else
                        print_warning "✗ Vinagre not found"
                    fi
                    ;;
                *)
                    if command -v "$app" >/dev/null 2>&1; then
                        print_message "✓ $app is installed and available"
                    else
                        print_warning "✗ $app not found in PATH"
                    fi
                    ;;
            esac
        done
    else
        # Default test for Remmina
        if command -v remmina >/dev/null 2>&1; then
            print_message "✓ Remmina is installed and available"
        else
            print_warning "✗ Remmina not found"
        fi
    fi

    print_message "=== Diagnostic Check Complete ==="
    print_message "Current VPN route to target:"
    ip route get ${REMOTE_PC_IP} 2>/dev/null || print_warning "No route found"

    print_message "Troubleshooting commands:"
    print_message "1. VPN status: ip addr show ppp0"
    print_message "2. Test connectivity: ping ${REMOTE_PC_IP}"
    print_message "3. Test RDP port: nc -zv ${REMOTE_PC_IP} 3389"
    print_message "4. Check IPsec: sudo ipsec statusall"
    print_message "5. Check xl2tpd: sudo journalctl -fu xl2tpd"
    
    return 0
}

# --- Main Script ---

print_message "--- Starting L2TP/IPsec VPN client setup with Application Support ---"

# Show configured applications
if [[ -n "$APPLICATION_LIST" ]]; then
    print_message "Applications to configure: $APPLICATION_LIST"
else
    print_message "No APPLICATION_LIST specified, using default (remmina)"
    APPLICATION_LIST="remmina"
fi

# --- Phase 1: File Creation ---

print_message "Configuring IP Forwarding..."
sudo sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
sudo sysctl -p

print_message "Creating Custom Routing Table 'vpn_apps'..."
if ! grep -q "vpn_apps" /etc/iproute2/rt_tables; then
    echo "200 vpn_apps" | sudo tee -a /etc/iproute2/rt_tables
fi

print_message "Configuring strongSwan (IPsec)..."
sudo mv /etc/ipsec.conf /etc/ipsec.conf.bak 2>/dev/null || true
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
  ike=aes128-sha256-modp1024,aes256-sha256-modp1024,aes128-sha1-modp1024,aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes128-sha256,aes256-sha256,aes128-sha1,aes256-sha1,3des-sha1!

conn l2tpvpn
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

[lac l2tpvpn]
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
# defaultroute commented out for policy routing
usepeerdns
debug
connect-delay 5000
name ${VPN_USERNAME}
password ${VPN_PASSWORD}
EOF"
sudo chmod 600 /etc/ppp/options.l2tpd.client

print_message "Creating 'ip-up.d' script for policy routing..."
sudo bash -c "cat > /etc/ppp/ip-up.d/route-apps-vpn <<EOF
#!/bin/sh
set -x
exec &> /tmp/route-apps-vpn.log

if [ \"\\\$IFNAME\" = \"ppp0\" ]; then
    VPN_GATEWAY=\"${VPN_PPP_GATEWAY_IP}\"
    
    # Add the default route for the custom table
    ip route add default via \"\\\$VPN_GATEWAY\" dev ppp0 table vpn_apps
    
    # Add the rule to use the custom table for marked traffic
    ip rule add fwmark 1 table vpn_apps
    
    # Add specific route for remote PC
    ip route add ${REMOTE_PC_IP}/32 via \"\\\$VPN_GATEWAY\" dev ppp0

    # Flush cache
    ip route flush cache
else
    echo "Interface \\\$IFNAME is not ppp0. Exiting."
fi
exit 0
EOF"
sudo chmod +x /etc/ppp/ip-up.d/route-apps-vpn

# --- Phase 2: Install Applications ---
install_applications

# --- Phase 3: Firewall & Services ---
print_message "Configuring firewall rules..."
sudo ufw allow 22/tcp comment "SSH"
sudo ufw allow 500/udp comment "IPsec"
sudo ufw allow 1701/udp comment "L2TP"
sudo ufw allow 4500/udp comment "IPsec NAT-T"

# Install netfilter-persistent if not present
if ! command -v netfilter-persistent &> /dev/null; then
    print_message "Installing netfilter-persistent..."
    sudo apt install -y netfilter-persistent
fi

print_message "Loading Kernel Modules for L2TP..."
sudo modprobe pppol2tp || sudo modprobe l2tp_ppp || print_warning "L2TP module loading failed"

print_message "Restarting services..."
sudo systemctl restart strongswan-starter
sudo systemctl restart xl2tpd

# --- Phase 4: Establish VPN & Configure Routing ---
print_message "Initiating VPN Tunnel..."
sudo ipsec up l2tpvpn
sleep 2
echo "c l2tpvpn" | sudo tee /var/run/xl2tpd/l2tp-control

# Wait for VPN to establish
sleep 5

# Set up application routing
setup_application_routing

print_message "Saving iptables rules..."
if command -v netfilter-persistent &> /dev/null; then
    sudo netfilter-persistent save
fi

# Configure routing table if VPN is up
if ip addr show | grep -q ppp0; then
    print_message "VPN is up, configuring routing table..."
    PPP_LOCAL_IP=$(ip addr show ppp0 | grep -oP 'inet \K[0-9.]+')
    if [[ ! -z "$PPP_LOCAL_IP" ]]; then
        PPP_GATEWAY=$(echo $PPP_LOCAL_IP | sed 's/\.[0-9]\+$/.1/')
        sudo ip route add default via $PPP_GATEWAY dev ppp0 table vpn_apps 2>/dev/null || true
        sudo ip rule add fwmark 1 table vpn_apps 2>/dev/null || true
        sudo ip route flush cache
    fi
fi

# --- Phase 5: Run Diagnostics ---
print_message "Running connectivity diagnostics..."
run_diagnostics

# --- Final Information ---
print_message "--- Setup Complete ---"
print_message "Configured Applications: $APPLICATION_LIST"
print_message "Target Remote PC: $REMOTE_PC_IP"

print_message "Verification Steps:"
print_message "1. Check VPN: sudo ipsec statusall"
print_message "2. Check routing: ip route list table vpn_apps"
print_message "3. Test connectivity: ping $REMOTE_PC_IP"

if echo "$APPLICATION_LIST" | grep -q "remmina"; then
    print_message "4. Test Remmina: remmina -c rdp://$REMOTE_PC_IP"
fi

if echo "$APPLICATION_LIST" | grep -q "xrdp"; then
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    print_message "4. xRDP available at: $IP_ADDRESS:3389"
fi

print_message "To re-run diagnostics: $0 --diagnose"

# Handle diagnostic-only mode
if [[ "$1" == "--diagnose" ]]; then
    run_diagnostics
    exit $?
fi

exit 0