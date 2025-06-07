#!/bin/bash

# Exit on any error
set -e

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Source configuration file
CONFIG_FILE="./gateway_config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    print_message "Configuration loaded from $CONFIG_FILE"
else
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

print_message "Setting up VNC on Ubuntu 24.04..."

# Update system
print_message "Updating package lists..."
apt update

# Install required packages
print_message "Installing required packages..."
sudo apt install strongswan xl2tpd network-manager-l2tp iptables-persistent -y

# Install netfilter-persistent for persistent iptables rules
print_message "Installing netfilter-persistent..."
apt install -y netfilter-persistent

# Install desktop environment (XFCE) and D-Bus
print_message "Installing XFCE desktop environment and dependencies..."
apt install -y xfce4 xfce4-goodies dbus-x11 dbus

# Install TigerVNC server
print_message "Installing TigerVNC server..."
apt install -y tigervnc-standalone-server

# Install Remmina
print_message "Installing Remmina with RDP support..."
apt install -y remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11 libfreerdp-client2-2

# Setup user if not existing
print_message "Setting up user '$VNC_USER'..."
if ! id "$VNC_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$VNC_USER"
    print_message "User '$VNC_USER' created."
fi
echo "$VNC_USER:$VNC_PASSWORD" | chpasswd
usermod -aG sudo "$VNC_USER"
print_message "User '$VNC_USER' configured with necessary group memberships."

# Create D-Bus directory
mkdir -p /home/$VNC_USER/.dbus
chown -R $VNC_USER:$VNC_USER /home/$VNC_USER/.dbus

# Create XDG runtime directory
mkdir -p /run/user/$(id -u $VNC_USER)
chmod 700 /run/user/$(id -u $VNC_USER)
chown $VNC_USER:$VNC_USER /run/user/$(id -u $VNC_USER)

# Switch to the VNC user for VNC configuration
print_message "Setting up VNC server..."
su - "$VNC_USER" <<EOF
# Create VNC directory
mkdir -p ~/.vnc

# Set VNC password
echo "$VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Create xstartup file with D-Bus initialization
cat > ~/.vnc/xstartup << 'XSTART'
#!/bin/bash
# Fix D-Bus issues
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p \$XDG_RUNTIME_DIR
chmod 700 \$XDG_RUNTIME_DIR

# Start D-Bus daemon
if [ -x /usr/bin/dbus-launch ]; then
    eval \$(dbus-launch --sh-syntax)
    echo \$DBUS_SESSION_BUS_ADDRESS > ~/.dbus/session-bus-address
fi

# Unset problematic variables
unset SESSION_MANAGER
# We keep DBUS_SESSION_BUS_ADDRESS as we need it

# Start window manager
xrdb \$HOME/.Xresources 2>/dev/null || true
xsetroot -solid grey
exec startxfce4
XSTART
chmod +x ~/.vnc/xstartup

# First time setup of the VNC server
vncserver -localhost no

# Kill the server to update configuration
vncserver -kill :1
EOF

# Create systemd service file with D-Bus environment setup
print_message "Creating systemd service for VNC..."
cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=Start TigerVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=/home/$VNC_USER

# Environment setup for D-Bus
Environment="XDG_RUNTIME_DIR=/run/user/$(id -u $VNC_USER)"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $VNC_USER)/bus"

PIDFile=/home/$VNC_USER/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStartPre=-/bin/mkdir -p /run/user/$(id -u $VNC_USER)
ExecStartPre=-/bin/chmod 700 /run/user/$(id -u $VNC_USER)
ExecStartPre=-/bin/chown $VNC_USER:$VNC_USER /run/user/$(id -u $VNC_USER)
ExecStart=/usr/bin/vncserver -depth 24 -geometry $VNC_RESOLUTION -localhost no :%i
ExecStop=/usr/bin/vncserver -kill :%i

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start VNC service
print_message "Enabling and starting VNC service..."
systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl start vncserver@1.service

# Configure firewall
print_message "Configuring firewall..."
apt install -y ufw
ufw allow 5901/tcp comment "VNC Server"
ufw allow 22/tcp comment "SSH"
ufw --force enable

# Show connection information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_message "VNC setup complete!"

echo "-----------------------------------------------------"
echo "VNC Server Details:"
echo "  User: $VNC_USER"
echo "  Password: $VNC_PASSWORD (you should change this!)"
echo "  Address: $IP_ADDRESS:5901"
echo ""
echo "Connect using a VNC viewer like RealVNC, TigerVNC, or Remmina to:"
echo "  $IP_ADDRESS:5901"
echo ""
echo "-----------------------------------------------------"
echo "To check VNC service status: systemctl status vncserver@1.service"
echo "To restart VNC service: systemctl restart vncserver@1.service"
echo "To check VNC logs: cat /home/$VNC_USER/.vnc/*.log"
echo "If you encounter D-Bus issues, run: sudo systemctl restart vncserver@1.service"
echo "-----------------------------------------------------"

exit 0