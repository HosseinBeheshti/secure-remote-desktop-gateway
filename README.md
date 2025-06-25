# Secure Remote Access & VPN Setup

This repository provides scripts to automate the setup of a secure remote desktop environment using L2TP/IPsec VPN, policy-based routing, and Remmina/RDP access. It is designed for deployment on a cloud server running Ubuntu.

---

## System Block Diagram

```
+-------------------+         +-------------------+         +-------------------+
|                   | <-----> |   Gateway Server  | <-----> |      Remote PC    |
|   Remote Client   |   VNC   | (L2TP/IPsec, VNC, |   RDP   |    (RDP Server)   |
|                   |=========|  Policy Routing)  |=========|                   |
+-------------------+         +-------------------+         +-------------------+
                                      |   ^
                                      |   |
                                      v   |
                                 [Firewall, UFW]
```

- **Remote Client**: Your laptop/PC running VNC viewer.
- **Gateway Server**: Ubuntu server running VPN client, TigerVNC server, and Remmina.
- **Remote PC**: Target Windows PC accessible via RDP over VPN.

---

## Step-by-Step Installation (Fresh Ubuntu)

### 0. Connect to the Server via SSH

Open your terminal and connect to your Ubuntu server using SSH:

```sh
ssh user@your_server_ip
```

Replace `user` with your username and `your_server_ip` with the actual IP address of your server.

### 1. Download Initial Scripts

First, download the server setup script and create a configuration file:

```sh
mkdir -p ~/secure-remote-desktop
cd ~/secure-remote-desktop
# Download setup_server.sh
wget https://raw.githubusercontent.com/HosseinBeheshti/secure-remote-desktop-gateway/main/setup_server.sh
# Download gateway_config.sh
wget https://raw.githubusercontent.com/HosseinBeheshti/secure-remote-desktop-gateway/main/gateway_config.sh
chmod +x *.sh
```

### 2. Configure VNC Settings

Edit the gateway_config.sh file to update at least the basic settings:

```sh
vim gateway_config.sh
```

Make sure to set:
- GATEWAY_USER and GATEWAY_PASSWORD (administrative user)
- VNC_USER and VNC_PASSWORD (regular VNC user)
- VNC ports and resolutions
- Change all default passwords!

### 3. Run the Server Setup

Run the server setup script to configure the dual-user VNC server:

```sh
sudo ./setup_server.sh
```

This installs all required packages, configures TigerVNC with two users, Remmina, and firewall.

### 4. Connect to the VNC Server

After setup, you can connect to either VNC user:

**Gateway User (Administrative)**:
```
[Server IP]:5910
Username: gateway (or your configured GATEWAY_USER)
Password: [your configured GATEWAY_PASSWORD]
```

**Regular VNC User**:
```
[Server IP]:5911
Username: vncuser (or your configured VNC_USER)  
Password: [your configured VNC_PASSWORD]
```

### 5. Clone the Complete Repository

Now that you're connected via VNC, clone the complete repository:

```sh
cd ~
git clone https://github.com/HosseinBeheshti/secure-remote-desktop-gateway.git
cd secure-remote-desktop-gateway
```

### 6. Configure Your VPN Environment

⚠️ **IMPORTANT**: Before proceeding further, you MUST modify the `gateway_config.sh` file with your specific VPN settings:

```sh
vim gateway_config.sh
```

Make sure to set:
- SERVER_PUBLIC_IP (your server's public IP)
- VPN_SERVER_PUBLIC_IP (VPN server IP address)
- REMOTE_PC_IP (target PC IP address)
- VPN_PPP_GATEWAY_IP (usually 192.168.150.1)
- IPSEC_PSK (IPsec pre-shared key)
- VPN_USERNAME and VPN_PASSWORD (VPN credentials)

The VPN scripts will not work correctly without these modifications!

### 7. Make Scripts Executable

Make all scripts executable:

```sh
chmod +x *.sh
```

### 8. Set Up VPN and Remmina

Run the VPN setup script from the root of the cloned repository:

```sh
sudo ./setup_vpn.sh
```

This configures L2TP/IPsec VPN, policy routing, firewall rules, and Remmina.

### 9. Troubleshoot (If Needed)

If you have issues connecting with Remmina, run the troubleshooting script:

```sh
./troubleshooting.sh
```

This script performs focused checks on:
- VPN connection status (ppp0 interface)
- IP routing to target PC
- RDP port connectivity
- Remmina connection test

---

## Dual VNC User Setup

The setup creates two VNC users for different purposes:

### Gateway User (Administrative)
- **Purpose**: Server administration and VPN management
- **Port**: 5910 (Display :1)
- **Resolution**: 1280x800 (configurable)
- **Privileges**: Full sudo access
- **Use Case**: Managing VPN connections, server configuration

### VNC User (Regular)
- **Purpose**: General remote desktop access
- **Port**: 5911 (Display :2)  
- **Resolution**: 1920x1080 (configurable)
- **Privileges**: Standard user with sudo access
- **Use Case**: Running Remmina, daily remote desktop tasks

Both users can connect simultaneously without interfering with each other.

---

## Service Management

Check VNC service status:
```sh
# Gateway user
sudo systemctl status vncserver-gateway@1.service

# Regular VNC user  
sudo systemctl status vncserver-vncuser@2.service
```

Restart VNC services:
```sh
# Gateway user
sudo systemctl restart vncserver-gateway@1.service

# Regular VNC user
sudo systemctl restart vncserver-vncuser@2.service
```

---

## Notes

- **Firewall**: The scripts configure UFW and remind you to set up cloud provider firewall rules.
- **Persistence**: Routing and firewall rules are made persistent across reboots.
- **Security**: Change all default passwords after setup.
- **VNC**: TigerVNC server is used for better performance and features.
- **Multi-User**: Two separate VNC sessions can run simultaneously.
- **Remmina**: Pre-installed and ready for RDP connections through VPN.

---

## File Overview

- [`gateway_config.sh`](gateway_config.sh): All configuration variables for both VNC users and VPN.
- [`setup_server.sh`](setup_server.sh): Installs and configures dual-user TigerVNC, Remmina, firewall.
- [`setup_vpn.sh`](setup_vpn.sh): Sets up L2TP/IPsec VPN client, policy routing, and Remmina.
- [`troubleshooting.sh`](troubleshooting.sh): VPN route and Remmina connectivity checker.

---

## Troubleshooting

### VNC Issues
- Check VNC service status: `sudo systemctl status vncserver-[username]@[display].service`
- Check VNC logs: `cat /home/[username]/.vnc/*.log`
- View systemd logs: `journalctl -xeu vncserver-[username]@[display].service`

### VPN Issues
- Check VPN status: `sudo ipsec statusall` or `ip addr show ppp0`
- Check VPN routing: `ip route | grep ppp0`
- Test target connectivity: `ping <REMOTE_PC_IP>`
- Test RDP port: `nc -zv <REMOTE_PC_IP> 3389`

### General Network
- Inspect traffic: `sudo tcpdump -i any -nn -v host <REMOTE_PC_IP>`
- Check firewall: `sudo ufw status verbose`
- View routing tables: `ip route list table all`

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.