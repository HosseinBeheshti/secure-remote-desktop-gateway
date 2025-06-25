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

# --- VNC User Setup Function ---
setup_vnc_user() {
    local USERNAME=$1
    local PASSWORD=$2
    local DISPLAY_NUM=$3
    local RESOLUTION=$4
    local PORT=$((5900 + DISPLAY_NUM))

    print_message "--- Setting up VNC for user '$USERNAME' on port $PORT (display :$DISPLAY_NUM) ---"

    # 1. Create user if not exists
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash "$USERNAME"
        print_message "User '$USERNAME' created."
    fi
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    print_message "User '$USERNAME' configured with password and sudo privileges."

    # 2. Configure VNC for the user
    su - "$USERNAME" <<EOF
mkdir -p /home/$USERNAME/.vnc
echo "$PASSWORD" | vncpasswd -f > /home/$USERNAME/.vnc/passwd
chmod 600 /home/$USERNAME/.vnc/passwd

cat > /home/$USERNAME/.vnc/xstartup << 'XSTART'
#!/bin/bash
xrdb \$HOME/.Xresources
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
startxfce4 &
XSTART

chmod +x /home/$USERNAME/.vnc/xstartup
EOF
    print_message "VNC configured for user '$USERNAME'."

    # 3. Create systemd service file for the user
    print_message "Creating systemd service for '$USERNAME'..."
    cat > /etc/systemd/system/vncserver-$USERNAME@.service << EOF
[Unit]
Description=TigerVNC server for user $USERNAME
After=syslog.target network.target

[Service]
Type=forking
User=$USERNAME
Group=$USERNAME
WorkingDirectory=/home/$USERNAME

PIDFile=/home/$USERNAME/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry $RESOLUTION -localhost no :%i
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 4. Enable and start the service
    systemctl daemon-reload
    systemctl enable vncserver-$USERNAME@$DISPLAY_NUM.service
    systemctl restart vncserver-$USERNAME@$DISPLAY_NUM.service
    print_message "VNC service for '$USERNAME' enabled and started."

    # 5. Configure firewall
    ufw allow "$PORT/tcp" comment "VNC for $USERNAME"
    print_message "Firewall rule added for port $PORT."
}

# --- Main Script ---

# 1. Source configuration
print_message "Loading configuration..."
CONFIG_FILE="./gateway_config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    print_message "Configuration loaded from $CONFIG_FILE"
else
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# 2. System Update and Package Installation
print_message "Updating package lists..."
apt-get update

print_message "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    strongswan \
    xl2tpd \
    network-manager-l2tp \
    iptables-persistent \
    netfilter-persistent \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    tigervnc-standalone-server \
    remmina \
    remmina-plugin-rdp \
    remmina-plugin-vnc \
    freerdp2-x11 \
    ufw

# 3. Setup Firewall
print_message "Configuring basic firewall rules..."
ufw allow 22/tcp comment "SSH"
ufw --force enable
print_message "Firewall is active."

# 4. Setup VNC Users based on config
setup_vnc_user "$GATEWAY_USER" "$GATEWAY_PASSWORD" "$GATEWAY_VNC_DISPLAY" "$GATEWAY_VNC_RESOLUTION"
setup_vnc_user "$VNC_USER" "$VNC_PASSWORD" "$VNC_DISPLAY" "$VNC_RESOLUTION"

# 5. Final Information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_message "--- Secure Remote Desktop Gateway Setup Complete ---"
echo -e "-----------------------------------------------------"
echo -e "${YELLOW}Gateway User Connection Details:${NC}"
echo -e "  User:      ${GREEN}$GATEWAY_USER${NC}"
echo -e "  Password:  ${GREEN}$GATEWAY_PASSWORD${NC}"
echo -e "  Address:   ${GREEN}$IP_ADDRESS:$((5900 + GATEWAY_VNC_DISPLAY))${NC} (Display :$GATEWAY_VNC_DISPLAY)"
echo -e ""
echo -e "${YELLOW}VNC User Connection Details:${NC}"
echo -e "  User:      ${GREEN}$VNC_USER${NC}"
echo -e "  Password:  ${GREEN}$VNC_PASSWORD${NC}"
echo -e "  Address:   ${GREEN}$IP_ADDRESS:$((5900 + VNC_DISPLAY))${NC} (Display :$VNC_DISPLAY)"
echo -e "-----------------------------------------------------"
echo -e "To check service status, run:"
echo -e "  systemctl status vncserver-$GATEWAY_USER@$GATEWAY_VNC_DISPLAY.service"
echo -e "  systemctl status vncserver-$VNC_USER@$VNC_DISPLAY.service"
echo -e "-----------------------------------------------------"

exit 0