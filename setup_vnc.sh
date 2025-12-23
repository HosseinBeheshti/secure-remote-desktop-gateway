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
    su - "$USERNAME" bash <<EOFSU
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
    ufw

# Setup Firewall
print_message "Configuring basic firewall rules..."
ufw allow 22/tcp comment "SSH"
ufw --force enable
print_message "Firewall is active."

# --- Additional Applications Installation ---
install_additional_apps() {
    print_message "Installing additional applications..."
    
    if [[ -z "$ADDITIONAL_APPS" ]]; then
        print_message "No additional applications specified."
        return
    fi
    
    for app in $ADDITIONAL_APPS; do
        case $app in
            docker)
                print_message "Installing Docker Engine..."
                # Install prerequisites
                apt-get install -y ca-certificates curl gnupg
                
                # Add Docker's official GPG key
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                
                # Set up the Docker repository
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                  tee /etc/apt/sources.list.d/docker.list > /dev/null
                
                # Install Docker Engine and Docker Compose
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                
                # Add VNC users to docker group
                if [[ -n "$VNC_USERS" ]]; then
                    IFS=';' read -ra USER_ENTRIES <<< "$VNC_USERS"
                    for user_entry in "${USER_ENTRIES[@]}"; do
                        IFS=':' read -r username _ _ _ _ <<< "$user_entry"
                        if [[ -n "$username" ]]; then
                            usermod -aG docker "$username" 2>/dev/null || true
                        fi
                    done
                fi
                
                print_message "Docker installed successfully."
                ;;
            
            vscode)
                print_message "Installing VS Code..."
                # Install dependencies
                apt-get install -y software-properties-common apt-transport-https wget
                
                # Add Microsoft GPG key
                wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/packages.microsoft.gpg
                
                # Add VS Code repository
                echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                  tee /etc/apt/sources.list.d/vscode.list > /dev/null
                
                # Install VS Code
                apt-get update
                apt-get install -y code
                
                print_message "VS Code installed successfully."
                ;;
            
            google-chrome-stable)
                print_message "Installing Google Chrome..."
                # Download and add Google Chrome signing key
                wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
                
                # Add Google Chrome repository
                echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
                
                # Install Google Chrome
                apt-get update
                apt-get install -y google-chrome-stable
                
                print_message "Google Chrome installed successfully."
                ;;
            
            *)
                # Install regular packages
                print_message "Installing $app..."
                apt-get install -y "$app" || print_warning "Failed to install $app"
                ;;
        esac
    done
    
    print_message "Additional applications installation complete."
}

# Install additional applications
install_additional_apps

# Parse VNC_USERS and setup each user
print_message "Setting up VNC users from configuration..."
if [[ -z "$VNC_USERS" ]]; then
    print_error "VNC_USERS not defined in $ENV_FILE"
    exit 1
fi

# Split users by semicolon
IFS=';' read -ra USER_ENTRIES <<< "$VNC_USERS"
for user_entry in "${USER_ENTRIES[@]}"; do
    # Split user details by colon: username:password:display:resolution:port
    IFS=':' read -r username password display resolution port <<< "$user_entry"
    
    if [[ -z "$username" || -z "$password" || -z "$display" || -z "$resolution" || -z "$port" ]]; then
        print_warning "Skipping invalid user entry: $user_entry"
        continue
    fi
    
    setup_vnc_user "$username" "$password" "$display" "$resolution" "$port"
done

# Final Information
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_message "=== VNC Server Setup Complete ==="
echo -e "-----------------------------------------------------"
echo -e "${YELLOW}VNC User Connection Details:${NC}"
echo ""

IFS=';' read -ra USER_ENTRIES <<< "$VNC_USERS"
for user_entry in "${USER_ENTRIES[@]}"; do
    IFS=':' read -r username password display resolution port <<< "$user_entry"
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
