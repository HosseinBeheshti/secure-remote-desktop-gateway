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
GATEWAY_CONFIG="./gateway-config.sh"
if [[ -f "$GATEWAY_CONFIG" ]]; then
    source "$GATEWAY_CONFIG"
    print_message "Configuration loaded from $GATEWAY_CONFIG"
else
    print_error "Configuration file not found: $GATEWAY_CONFIG"
    exit 1
fi

# Create Remmina profile directory if it doesn't exist
mkdir -p ~/.local/share/remmina/

# Create a unique profile name
PROFILE_NAME="${REMOTE_PC_NAME}_$(date +%s).remmina"

print_message "Creating Remmina profile for ${REMOTE_PC_NAME}..."

# Create the Remmina profile file
cat > ~/.local/share/remmina/${PROFILE_NAME} << EOF
[remmina]
disableclipboard=0
ssh_enabled=0
name=${REMOTE_PC_NAME}
protocol=RDP
server=${REMOTE_PC_IP}
username=${RDP_USERNAME}
password=${RDP_PASSWORD}
gateway_server=
gateway_username=
gateway_password=
colordepth=32
sound=off
microphone=off
viewmode=1
scale=1
quality=9
disablepasswordstoring=0
resolution=${RDP_RESOLUTION}
group=
disableautoreconnect=0
disableservercheck=0
drive=
shareprinter=0
security=
execpath=
disable_fastpath=0
cert_ignore=1
enable-autostart=0
console=0
noauth=0
glyph-cache=0
SSH_TUNNEL_LOOPBACK=0
EOF

print_message "Setting permissions on Remmina profile..."
chmod 600 ~/.local/share/remmina/${PROFILE_NAME}

print_message "Remmina profile created successfully!"
print_message "Profile location: ~/.local/share/remmina/${PROFILE_NAME}"

print_message "Launching Remmina with the new profile..."
remmina -c ~/.local/share/remmina/${PROFILE_NAME} &