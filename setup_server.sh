#!/bin/bash

# VNC Server Setup Script for Ubuntu 24.04
# This script sets up a complete VNC server with XFCE desktop

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

# --- Configuration ---
# Source configuration from gateway_config.sh
if [ -f "gateway_config.sh" ]; then
    source gateway_config.sh
    print_message "Configuration loaded from gateway_config.sh"
else
    print_error "Configuration file gateway_config.sh not found!"
    exit 1
fi

print_message "Setting up VNC Server on Ubuntu 24.04..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Update system
print_message "Updating package lists..."
apt update

# Install desktop environment (XFCE) - lightweight and stable
print_message "Installing XFCE desktop environment..."
apt install -y xfce4 xfce4-goodies

# Install VNC server and dependencies
print_message "Installing TightVNC server and dependencies..."
apt install -y tightvncserver xfonts-base dbus-x11

# Install additional useful packages
print_message "Installing additional packages..."
apt install -y firefox vim wget curl

# Create VNC user if doesn't exist
print_message "Setting up VNC user '$VNC_USER'..."
if ! id "$VNC_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$VNC_USER"
    print_message "User '$VNC_USER' created"
else
    print_message "User '$VNC_USER' already exists"
fi

# Set password for VNC user
echo "$VNC_USER:$VNC_PASSWORD" | chpasswd
usermod -aG sudo "$VNC_USER"

# Setup VNC for the user
print_message "Configuring VNC server..."
sudo -u "$VNC_USER" bash << EOF
# Create VNC directory
mkdir -p /home/$VNC_USER/.vnc

# Set VNC password
echo "$VNC_PASSWORD" | vncpasswd -f > /home/$VNC_USER/.vnc/passwd
chmod 600 /home/$VNC_USER/.vnc/passwd

# Create xstartup file
cat > /home/$VNC_USER/.vnc/xstartup << 'XSTART'
#!/bin/bash
xrdb \$HOME/.Xresources
startxfce4 &
XSTART

chmod +x /home/$VNC_USER/.vnc/xstartup

# Start VNC server once to create initial configuration
export USER="$VNC_USER"
export HOME="/home/$VNC_USER"
cd /home/$VNC_USER
tightvncserver :1 -geometry $VNC_RESOLUTION -depth 24
tightvncserver -kill :1
EOF

# Create systemd service file
print_message "Creating systemd service..."
cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=Start TightVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=/home/$VNC_USER

PIDFile=/home/$VNC_USER/.vnc/%H:%i.pid
ExecStartPre=-/bin/sh -c '/usr/bin/tightvncserver -kill :%i > /dev/null 2>&1 || :'
ExecStart=/usr/bin/tightvncserver -depth 24 -geometry $VNC_RESOLUTION :%i
ExecStop=/usr/bin/tightvncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

# Enable and start VNC service
print_message "Enabling and starting VNC service..."
systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl start vncserver@1.service

# Wait a moment for service to start
sleep 3

# Check service status
if systemctl is-active --quiet vncserver@1.service; then
    print_message "VNC service started successfully!"
else
    print_warning "VNC service may have issues. Checking status..."
    systemctl status vncserver@1.service --no-pager || true
    print_warning "Checking logs..."
    journalctl -u vncserver@1.service --no-pager | tail -10
    print_warning "Checking VNC log files..."
    ls -la /home/$VNC_USER/.vnc/ || true
    cat /home/$VNC_USER/.vnc/*.log 2>/dev/null || print_warning "No VNC log files found"
fi

# Configure firewall
print_message "Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow $VNC_PORT/tcp comment "VNC Server"
    ufw allow 22/tcp comment "SSH"
    ufw --force enable
else
    print_warning "UFW not found, please configure firewall manually"
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Create connection script for user
cat > /home/$VNC_USER/connect_info.txt << EOF
VNC Server Connection Information
================================

Server IP: $SERVER_IP
VNC Port: $VNC_PORT
Full Address: $SERVER_IP:$VNC_PORT
Username: $VNC_USER
Password: $VNC_PASSWORD

VNC Clients you can use:
- RealVNC Viewer
- TightVNC Viewer  
- Remmina (Linux)
- VNC Viewer (built into many systems)

To connect:
1. Open your VNC client
2. Enter: $SERVER_IP:$VNC_PORT (or $SERVER_IP:1)
3. Enter password when prompted: $VNC_PASSWORD

Useful Commands:
- Check VNC status: sudo systemctl status vncserver@1.service
- Restart VNC: sudo systemctl restart vncserver@1.service
- Stop VNC: sudo systemctl stop vncserver@1.service
- Start VNC: sudo systemctl start vncserver@1.service
- View VNC logs: ls -la ~/.vnc/ && cat ~/.vnc/*.log
EOF

chown $VNC_USER:$VNC_USER /home/$VNC_USER/connect_info.txt

# Display final information
print_message "VNC Server setup completed successfully!"
echo ""
echo "=================================================="
echo "           VNC SERVER SETUP COMPLETE"
echo "=================================================="
echo ""
echo "🖥️  Server Details:"
echo "   IP Address: $SERVER_IP"
echo "   VNC Port: $VNC_PORT"
echo "   Full Address: $SERVER_IP:$VNC_PORT"
echo ""
echo "👤 User Credentials:"
echo "   Username: $VNC_USER"
echo "   Password: $VNC_PASSWORD"
echo ""
echo "🔧 Service Management:"
echo "   Status: sudo systemctl status vncserver@1.service"
echo "   Restart: sudo systemctl restart vncserver@1.service"
echo "   Logs: sudo journalctl -u vncserver@1.service"
echo ""
echo "📋 Connection info saved to: /home/$VNC_USER/connect_info.txt"
echo ""
echo "🚀 Ready to connect with any VNC client!"
echo "=================================================="

# Final service status check
print_message "Final service status check..."
if systemctl is-active --quiet vncserver@1.service; then
    echo "✅ VNC service is running"
else
    echo "❌ VNC service is not running - check logs with:"
    echo "   sudo systemctl status vncserver@1.service"
    echo "   sudo journalctl -u vncserver@1.service"
fi

exit 0