# Usage Guide - Step by Step

This guide walks you through setting up your secure remote desktop gateway from scratch.

## 📋 Prerequisites

Before starting, ensure you have:

- [ ] Ubuntu/Debian server with root/sudo access
- [ ] SSH access to your server
- [ ] VPN server credentials (L2TP or OpenVPN)
- [ ] OpenVPN configuration file (if using OpenVPN)
- [ ] Server's public IP address

## 🔧 Step 1: Initial Configuration

### 1.1 Connect to Your Server

```bash
ssh your-username@your-server-ip
```

### 1.2 Clone/Download Repository

```bash
cd ~
git clone <your-repo-url>
cd secure-remote-desktop-gateway
```

Or if you uploaded files directly:
```bash
cd /path/to/secure-remote-desktop-gateway
```

### 1.3 Edit Configuration File

```bash
vim workstation.env
```

#### Configure VNC Users

Update this line with your desired users:
```bash
VNC_USERS="gateway:StrongPass123:1:1920x1080:5910;vncuser:AnotherPass456:2:1920x1080:5911"
```

Format: `username:password:display:resolution:port`

#### Configure Server Information

```bash
SERVER_PUBLIC_IP="YOUR_SERVER_PUBLIC_IP"      # Your server's public IP
REMOTE_PC_IP="YOUR_REMOTE_PC_IP"              # PC you want to access remotely
```

#### Configure VPN List

Choose which VPNs you want to use:
```bash
VPN_LIST="l2tp ovpn"     # Both L2TP and OpenVPN
# VPN_LIST="l2tp"        # Only L2TP
# VPN_LIST="ovpn"        # Only OpenVPN
```

#### Configure L2TP (if using)

```bash
L2TP_SERVER_IP="vpn.example.com"
L2TP_IPSEC_PSK="your-ipsec-preshared-key"
L2TP_USERNAME="your-vpn-username"
L2TP_PASSWORD="your-vpn-password"
L2TP_PPP_GATEWAY="192.168.150.1"          # Usually this default is fine
L2TP_APPS="xrdp"                           # Apps to route through L2TP
```

#### Configure OpenVPN (if using)

```bash
OVPN_CONFIG_PATH="/etc/openvpn/client/config.ovpn"  # Path to your .ovpn file
OVPN_USERNAME="your-ovpn-username"                   # Leave empty if in config
OVPN_PASSWORD="your-ovpn-password"                   # Leave empty if in config
OVPN_APPS="remmina"                                  # Apps to route through OpenVPN
```

#### Save and Exit

Press `Esc`, then type `:wq` and press `Enter`

## 🚀 Step 2: Run Setup Scripts

### 2.1 Setup VNC Server

This creates VNC users and installs desktop environment:

```bash
sudo ./setup_vnc.sh
```

**Expected output:**
- Package installation progress
- User creation confirmations
- Service start confirmations
- Connection details for each user

**What to verify:**
```bash
# Check if services are running
systemctl status vncserver-gateway@1
systemctl status vncserver-vncuser@2

# Check if ports are open
sudo ss -tulpn | grep vnc
```

### 2.2 Setup Virtual Routers

This creates routing tables for VPNs:

```bash
sudo ./setup_virtual_router.sh
```

**Expected output:**
- IP forwarding enabled
- Routing tables created
- Helper script installed

**What to verify:**
```bash
# Check routing tables
cat /etc/iproute2/rt_tables | grep vpn

# Should show something like:
# 200 vpn_l2tp
# 201 vpn_ovpn

# Check helper script
show-vpn-routes.sh
```

### 2.3 Setup L2TP VPN (Optional - One-time)

If you included `l2tp` in your VPN_LIST, first run the setup:

```bash
sudo ./setup_l2tp.sh
```

**Expected output:**
- Package installation (strongSwan, xl2tpd)
- Configuration files created
- Services enabled

**Then connect to L2TP VPN:**

```bash
sudo ./run_l2tp.sh
```

**Expected output:**
- VPN connection established
- ppp0 interface up
- Connectivity test results
- Connection stays active until you close the terminal or press Ctrl+C

**What to verify:**
```bash
# Check VPN interface
ip addr show ppp0

# Check IPsec status
sudo ipsec statusall

# Check routing
ip route show table vpn_l2tp

# Test connectivity to remote PC
ping -c 3 YOUR_REMOTE_PC_IP
```

**Troubleshooting if connection fails:**
```bash
# Check IPsec logs
sudo journalctl -xeu strongswan-starter

# Check xl2tpd logs
sudo journalctl -xeu xl2tpd

# Try reconnecting
sudo ipsec restart
sleep 3
echo 'c l2tpvpn' | sudo tee /var/run/xl2tpd/l2tp-control
```

### 2.4 Setup OpenVPN (Optional - One-time)

If you included `ovpn` in your VPN_LIST:

**First, upload your .ovpn config file:**
```bash
# From your local machine:
scp /path/to/your/config.ovpn your-username@your-server:/etc/openvpn/client/

# Or use vim to create it:
sudo vim /etc/openvpn/client/config.ovpn
# (paste your config, then Ctrl+X, Y, Enter)
```

**Then run the setup:**
```bash
sudo ./setup_ovpn.sh
```

**Expected output:**
- Package installation (OpenVPN)
- Configuration prepared
- Routing scripts created

**Then connect to OpenVPN:**

```bash
sudo ./run_ovpn.sh
```

**Expected output:**
- VPN connection established
- tun0 interface up
- Connectivity test results
- Connection stays active until you close the terminal or press Ctrl+C

**What to verify:**
```bash
# Check VPN interface
ip addr show tun0

# Check OpenVPN service
systemctl status openvpn-client@config

# Check routing
ip route show table vpn_ovpn

# Test internet through VPN
ping -I tun0 8.8.8.8
```

**Troubleshooting if connection fails:**
```bash
# Check OpenVPN logs
sudo journalctl -xeu openvpn-client@config

# Check config file
sudo cat /etc/openvpn/client/config.ovpn

# Try manual connection
sudo openvpn --config /etc/openvpn/client/config.ovpn
```

## 🖥️ Step 3: Connect and Test

### 3.1 Connect to VNC

From your local machine:

**Using VNC Viewer:**
1. Open your VNC client (TigerVNC, RealVNC, etc.)
2. Enter: `your-server-ip:5910` (for first user)
3. Enter the password you set in workstation.env
4. You should see the XFCE desktop

**Using Command Line (Linux/Mac):**
```bash
vncviewer your-server-ip:5910
```

### 3.2 Test L2TP Applications

If you're using L2TP for xrdp:

**Connect to xRDP from outside:**
```bash
# From your local machine or inside VNC session:
# From your local machine:
xfreerdp /v:your-server-ip:3389 /u:gateway
```

**Traffic should now route through L2TP VPN!**

Verify:
```bash
# Check what route is being used
ip route get YOUR_REMOTE_PC_IP

# Should show route via ppp0
```

### 3.3 Test OpenVPN Applications

If you're using OpenVPN for remmina:

**Inside VNC session:**
```bash
# Launch Remmina through VPN
remmina-vpn

# Or launch normally (will route through OpenVPN automatically)
remmina -c rdp://YOUR_REMOTE_PC_IP
```

**Traffic should now route through OpenVPN!**

Verify:
```bash
# Check what route is being used
ip route get YOUR_REMOTE_PC_IP

# Should show route via tun0
```

## 📊 Step 4: Monitor and Verify

### 4.1 Check Overall Status

```bash
# Check all VPN routes
show-vpn-routes.sh

# Check VPN interfaces
ip addr show | grep -E "ppp|tun"

# Check routing rules
ip rule show

# Check iptables marks
sudo iptables -t mangle -L -n -v
```

### 4.2 Check Services

```bash
# VNC services
systemctl status vncserver-*

# L2TP services
systemctl status strongswan-starter
systemctl status xl2tpd

# OpenVPN service
systemctl status openvpn-client@*
```

### 4.3 Check Logs

```bash
# VNC logs
journalctl -xeu vncserver-gateway@1

# L2TP logs
journalctl -fu strongswan-starter
journalctl -fu xl2tpd

# OpenVPN logs
journalctl -fu openvpn-client@config
```

## 🔄 Step 5: Daily Usage

### Starting Your Work Session

1. **Connect to VNC:**
   ```bash
   vncviewer your-server-ip:5910
   ```

2. **Connect to VPNs (in separate terminals):**
   ```bash
   # L2TP (in terminal 1)
   sudo ./run_l2tp.sh
   
   # OpenVPN (in terminal 2)
   sudo ./run_ovpn.sh
   ```

3. **Verify VPNs are connected (in another terminal):**
   ```bash
   show-vpn-routes.sh
   ip addr show ppp0  # L2TP
   ip addr show tun0  # OpenVPN
   ```

4. **Launch your applications:**
   - Applications in L2TP_APPS automatically route through L2TP
   - Use `app-name-vpn` wrappers for OpenVPN apps

### Reconnecting After Reboot

All services should auto-start, but verify:

```bash
# Check if everything is running
systemctl status vncserver-gateway@1
systemctl status strongswan-starter
systemctl status xl2tpd
systemctl status openvpn-client@config

# If needed, restart:
sudo systemctl restart vncserver-gateway@1
sudo systemctl restart strongswan-starter xl2tpd
sudo systemctl restart openvpn-client@config
```

## 🆘 Common Issues and Solutions

### Issue: VNC service won't start

```bash
# Check logs
journalctl -xeu vncserver-username@display

# Common fixes:
# 1. Kill any existing VNC servers
vncserver -kill :1

# 2. Remove lock files
rm /tmp/.X1-lock
rm /tmp/.X11-unix/X1

# 3. Restart service
sudo systemctl restart vncserver-username@1
```

### Issue: L2TP won't connect

```bash
# Check if server is reachable
ping L2TP_SERVER_IP

# Check IPsec phase 1
sudo ipsec statusall

# Check L2TP logs
sudo tail -f /var/log/syslog | grep xl2tpd

# Verify credentials in:
sudo vim /etc/ipsec.secrets
sudo vim /etc/ppp/options.l2tpd.client
```

### Issue: OpenVPN won't connect

```bash
# Test config manually
sudo openvpn --config /etc/openvpn/client/config.ovpn

# Check if config file is valid
sudo openvpn --config /etc/openvpn/client/config.ovpn --verb 3

# Verify credentials
sudo cat /etc/openvpn/client/auth.txt
```

### Issue: Traffic not routing through VPN

```bash
# Check routing tables
ip route show table vpn_l2tp
ip route show table vpn_ovpn

# Check routing rules
ip rule show | grep vpn

# Check iptables marks
sudo iptables -t mangle -L OUTPUT -n -v

# Re-apply routing (for L2TP)
sudo /etc/ppp/ip-up.d/route-l2tp-apps
```

## 📝 Notes

- **Security**: Always use strong passwords and keep your VPN credentials secure
- **Firewall**: The scripts configure UFW automatically, but verify: `sudo ufw status`
- **Updates**: Regularly update your system: `sudo apt update && sudo apt upgrade`
- **Backups**: Keep backups of your workstation.env and VPN configs
- **Monitoring**: Check logs regularly for any issues

## 🎯 Next Steps

- Add more VNC users by editing workstation.env and re-running setup_vnc.sh
- Configure additional applications to route through VPNs
- Set up automatic reconnection scripts for VPNs
- Configure monitoring and alerts for VPN disconnections

---

**Happy remote working! 🚀**
