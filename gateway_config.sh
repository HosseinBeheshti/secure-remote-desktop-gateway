#!/bin/bash

# Network Configuration
export SERVER_PUBLIC_IP="YOUR_SERVER_PUBLIC_IP"
export VPN_SERVER_PUBLIC_IP="YOUR_VPN_SERVER_PUBLIC_IP"
export VPN_PPP_GATEWAY_IP="192.168.150.1"
export REMOTE_PC_IP="YOUR_REMOTE_PC_IP"  # IP of the remote PC

# VNC Server Settings
export VNC_USER="vncuser"
export VNC_PORT="5901"
export VNC_PASSWORD="change_this_password"
export VNC_RESOLUTION="1920x1080"

# VPN Authentication
export IPSEC_PSK="YOUR_IPSEC_PSK"
export VPN_USERNAME="vpn_username"
export VPN_PASSWORD="vpn_password"
