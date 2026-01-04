# Secure Remote Desktop Gateway

Ubuntu/Debian server setup for VNC desktop with VPN-routed applications.

## Quick Start

1. **Configure** `workstation.env`
2. **Setup**: `sudo ./setup_server.sh`
3. **Connect VNC**: `vncviewer server-ip:5910`
4. **Run VPN**: `sudo ./run_vpn.sh` (interactive selection)

## Scripts

### Setup (one-time)
- `setup_server.sh` - Master setup (runs all setup scripts)
- `setup_vnc.sh` - VNC server and desktop
- `setup_virtual_router.sh` - VPN routing tables
- `setup_l2tp.sh` - L2TP/IPsec client
- `setup_ovpn.sh` - OpenVPN client

### Runtime
- `run_vpn.sh` - Universal VPN connection manager (interactive selection)

## Configuration

Edit `workstation.env`:

```bash
# VNC users: username:password:display:resolution:port
VNC_USERS="gateway:pass:1:1920x1080:5910"

# VPN selection
VPN_LIST="l2tp ovpn"  # or "l2tp" or "ovpn"

# L2TP
L2TP_SERVER_IP="vpn.example.com"
L2TP_IPSEC_PSK="preshared-key"
L2TP_USERNAME="username"
L2TP_PASSWORD="password"

# OpenVPN
OVPN_CONFIG_PATH="/etc/openvpn/client/config.ovpn"

# VPN Applications - routed through selected VPN at runtime
VPN_APPS="xrdp remmina firefox vscode google-chrome-stable"
```

## Usage

### Setup
```bash
sudo ./setup_server.sh
```

### Daily Use
```bash
# Universal VPN manager
sudo ./run_vpn.sh
# - Select VPN type (L2TP or OpenVPN)
# - All apps in VPN_APPS will be routed through selected VPN
# - Press Ctrl+C to disconnect

# VNC
vncviewer server-ip:5910
```

### Verify
```bash
show-vpn-routes.sh
ip addr show ppp0 tun0
```

## Troubleshooting

```bash
# VNC
systemctl status vncserver-gateway@1
journalctl -xeu vncserver-gateway@1

# L2TP
sudo ipsec statusall
journalctl -xeu xl2tpd

# OpenVPN
systemctl status openvpn-client@config
journalctl -xeu openvpn-client@config
```
