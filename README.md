# Secure Remote Desktop Gateway

Ubuntu/Debian server setup for VNC desktop with VPN-routed applications.

## Quick Start

1. **Configure** `workstation.env`
2. **Setup**: `sudo ./setup_server.sh`
3. **Connect VNC**: `vncviewer server-ip:5910`
4. **Run VPNs**: `sudo ./run_l2tp.sh` and/or `sudo ./run_ovpn.sh`

## Scripts

### Setup (one-time)
- `setup_server.sh` - Master setup (runs all setup scripts)
- `setup_vnc.sh` - VNC server and desktop
- `setup_virtual_router.sh` - VPN routing tables
- `setup_l2tp.sh` - L2TP/IPsec client
- `setup_ovpn.sh` - OpenVPN client

### Runtime
- `run_l2tp.sh` - Connect L2TP VPN
- `run_ovpn.sh` - Connect OpenVPN

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
L2TP_APPS="xrdp"  # Apps to route through L2TP

# OpenVPN
OVPN_CONFIG_PATH="/etc/openvpn/client/config.ovpn"
OVPN_APPS="remmina"  # Apps to route through OpenVPN
```

## Usage

### Setup
```bash
sudo ./setup_server.sh
```

### Daily Use
```bash
# Terminal 1: L2TP
sudo ./run_l2tp.sh

# Terminal 2: OpenVPN
sudo ./run_ovpn.sh

# Terminal 3: VNC
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
