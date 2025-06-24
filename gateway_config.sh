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

# Define VNC users and their configurations
VNC_USER1="vncuser1"
VNC_PASSWORD1="vnc123456"
VNC_PORT1="5901"
VNC_DISPLAY1="1"

VNC_USER2="vncuser2"
VNC_PASSWORD2="vnc789012"
VNC_PORT2="5902"
VNC_DISPLAY2="2"


# VPN Authentication
export IPSEC_PSK="YOUR_IPSEC_PSK"
export VPN_USERNAME="vpn_username"
export VPN_PASSWORD="vpn_password"
