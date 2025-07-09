#!/bin/bash

# --- Gateway User (for managing the server and VPN) ---
# This user has full sudo access and is intended for server administration.
export GATEWAY_USER="gateway"
export GATEWAY_PASSWORD="change_this_strong_password"
export GATEWAY_VNC_PORT="5910"
export GATEWAY_VNC_DISPLAY="1"
export GATEWAY_VNC_RESOLUTION="1920x1080"

# --- VNC User (for general remote desktop use) ---
# This user is for standard remote desktop access.
export VNC_USER="vncuser"
export VNC_PASSWORD="change_this_password_too"
export VNC_PORT="5911"
export VNC_DISPLAY="2"
export VNC_RESOLUTION="1920x1080"

# --- VPN Configuration ---
export SERVER_PUBLIC_IP="YOUR_SERVER_PUBLIC_IP"
export VPN_SERVER_PUBLIC_IP="YOUR_VPN_SERVER_PUBLIC_IP"
export VPN_PPP_GATEWAY_IP="192.168.150.1"
export REMOTE_PC_IP="YOUR_REMOTE_PC_IP"
export IPSEC_PSK="YOUR_IPSEC_PSK"
export VPN_USERNAME="vpn_username"
export VPN_PASSWORD="vpn_password"