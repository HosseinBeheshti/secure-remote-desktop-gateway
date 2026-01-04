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

# --- VNC User Setup Function ---
setup_vnc_user() {
    local USERNAME=$1
    local PASSWORD=$2
    local DISPLAY_NUM=$3
    local RESOLUTION=$4
    local PORT=$5

    print_message "--- Setting up VNC for user '$USERNAME' on port $PORT (display :$DISPLAY_NUM) ---"

    # 1. Create user if not exists
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash "$USERNAME"
        print_message "User '$USERNAME' created."
    fi
    printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    print_message "User '$USERNAME' configured with password and sudo privileges."

    # 2. Configure VNC for the user
    sudo -u "$USERNAME" bash <<EOFSU
mkdir -p ~/.vnc
printf '%s' '$PASSWORD' | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'XSTART'
#!/bin/sh
# This script is executed by the VNC server when a desktop session starts.
# It launches the XFCE desktop environment.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
[ -r \\\$HOME/.Xresources ] && xrdb \\\$HOME/.Xresources
exec startxfce4
XSTART

chmod +x ~/.vnc/xstartup

# --- VNC Initialization ---
# Forcefully kill any existing VNC server for this display to ensure a clean state.
vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true
sleep 1

# Initialize the VNC server once to create necessary files.
vncserver -rfbport $PORT :$DISPLAY_NUM

# Wait a moment for the server to create its PID file before killing it.
sleep 2

# Kill the temporary server. The systemd service will manage the permanent one.
vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true
EOFSU
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
ExecStart=/usr/bin/vncserver -depth 24 -geometry $RESOLUTION -localhost no -rfbport $PORT :%i
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

    # Add a check to see if the service is active
    sleep 3 # Give the service a moment to stabilize
    if ! systemctl is-active --quiet vncserver-$USERNAME@$DISPLAY_NUM.service; then
        print_error "VNC service for '$USERNAME' failed to start. Please check the logs with:"
        echo "journalctl -xeu vncserver-$USERNAME@$DISPLAY_NUM.service"
        exit 1
    fi

    # 5. Configure firewall
    ufw allow "$PORT/tcp" comment "VNC for $USERNAME"
    print_message "Firewall rule added for port $PORT."
}

# --- Main Script ---

print_message "=== Starting VNC Server Setup ==="

# System Update and Package Installation
print_message "Updating package lists..."
apt-get update

print_message "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    vim \
    tigervnc-standalone-server \
    ufw \
    firefox

# Setup Firewall
print_message "Configuring basic firewall rules..."
ufw allow 22/tcp comment "SSH"
ufw --force enable
print_message "Firewall is active."

# Parse VNC users and setup each user
print_message "Setting up VNC users from configuration..."
if [[ -z "$VNC_USER_COUNT" ]]; then
    print_error "VNC_USER_COUNT not defined in $ENV_FILE"
    exit 1
fi

# Loop through each user based on VNC_USER_COUNT
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    # Get user variables dynamically
    username_var="VNCUSER${i}_USERNAME"
    password_var="VNCUSER${i}_PASSWORD"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    password="${!password_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -z "$username" || -z "$password" || -z "$display" || -z "$resolution" || -z "$port" ]]; then
        print_warning "Skipping user $i: incomplete configuration"
        continue
    fi
    
    setup_vnc_user "$username" "$password" "$display" "$resolution" "$port"
done

# --- Additional Applications Installation ---
# Install additional applications for each VNC user with sudo access
install_additional_apps_for_users() {
    print_message "Installing additional applications for VNC users..."
    
    if [[ -z "$ADDITIONAL_APPS" ]]; then
        print_message "No additional applications specified."
        return
    fi
    
    # Get the first VNC user to run installations
    first_username_var="VNCUSER1_USERNAME"
    first_password_var="VNCUSER1_PASSWORD"
    first_username="${!first_username_var}"
    first_password="${!first_password_var}"
    
    if [[ -z "$first_username" ]]; then
        print_error "No VNC user found to install applications"
        return
    fi
    
    print_message "Installing applications as user: $first_username"
    
    for app in $ADDITIONAL_APPS; do
        case $app in
            docker)
                print_message "Installing Docker Engine..."
                sudo -u "$first_username" bash <<EOFDOCKER
# Install prerequisites
echo '$first_password' | sudo -S apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
echo '$first_password' | sudo -S install -m 0755 -d /etc/apt/keyrings
echo '$first_password' | sudo -S sh -c 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
echo '$first_password' | sudo -S chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo '$first_password' | sudo -S sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list'

# Install Docker Engine and Docker Compose
echo '$first_password' | sudo -S apt-get update
echo '$first_password' | sudo -S apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
EOFDOCKER
                
                # Add all VNC users to docker group
                for ((i=1; i<=VNC_USER_COUNT; i++)); do
                    username_var="VNCUSER${i}_USERNAME"
                    username="${!username_var}"
                    if [[ -n "$username" ]]; then
                        usermod -aG docker "$username" 2>/dev/null || true
                    fi
                done
                
                print_message "Docker installed successfully."
                ;;
            
            vscode)
                print_message "Installing VS Code..."
                sudo -u "$first_username" bash <<EOFVSCODE
# Install dependencies
echo '$first_password' | sudo -S apt-get install -y software-properties-common apt-transport-https wget

# Add Microsoft GPG key
echo '$first_password' | sudo -S sh -c 'wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg'

# Add VS Code repository
echo '$first_password' | sudo -S sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'

# Install VS Code
echo '$first_password' | sudo -S apt-get update
echo '$first_password' | sudo -S apt-get install -y code
EOFVSCODE
                
                print_message "VS Code installed successfully."
                ;;
            
            google-chrome-stable)
                print_message "Installing Google Chrome..."
                sudo -u "$first_username" bash <<EOFCHROME
# Download and add Google Chrome signing key
echo '$first_password' | sudo -S sh -c 'wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -'

# Add Google Chrome repository
echo '$first_password' | sudo -S sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list'

# Install Google Chrome
echo '$first_password' | sudo -S apt-get update
echo '$first_password' | sudo -S apt-get install -y google-chrome-stable
EOFCHROME
                
                print_message "Google Chrome installed successfully."
                ;;
            
            *)
                # Install regular packages
                print_message "Installing $app..."
                sudo -u "$first_username" bash -c "echo '$first_password' | sudo -S apt-get install -y $app" || print_warning "Failed to install $app"
                ;;
        esac
    done
    
    print_message "Additional applications installation complete."
}

# Install additional applications (runs as VNC user with sudo)
install_additional_apps_for_users

# Final Information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_message "=== VNC Server Setup Complete ==="
echo -e "-----------------------------------------------------"
echo -e "${YELLOW}VNC User Connection Details:${NC}"
echo ""

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    password_var="VNCUSER${i}_PASSWORD"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    password="${!password_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -n "$username" ]]; then
        echo -e "  ${GREEN}User:${NC}       $username"
        echo -e "  ${GREEN}Password:${NC}   $password"
        echo -e "  ${GREEN}Address:${NC}    $IP_ADDRESS:$port (Display :$display)"
        echo -e "  ${GREEN}Resolution:${NC} $resolution"
        echo ""
    fi
done

echo -e "-----------------------------------------------------"
echo -e "To check service status for a user, run:"
echo -e "  systemctl status vncserver-<username>@<display>.service"
echo -e "-----------------------------------------------------"

exit 0
