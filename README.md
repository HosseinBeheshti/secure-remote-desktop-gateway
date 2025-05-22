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

- **Remote Client**: Your laptop/PC running Remmina or VNC viewer.
- **Gateway Server**: Ubuntu server running VPN client, VNC server, and Remmina.
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

Edit the gateway_config.sh file to update at least the VNC settings:

```sh
vim gateway_config.sh
```

Make sure to set:
- VNC_USER
- VNC_PASSWORD (change from the default)
- VNC_RESOLUTION

### 3. Run the Server Setup

Run the server setup script to configure the VNC server:

```sh
sudo ./setup_server.sh
```

This installs all required packages, configures VNC, Remmina, and firewall.

### 4. Connect to the VNC Server

For the remaining steps, you should connect to the VNC server that was just set up. Use your VNC client to connect to the server:

```
[Server IP]:5901
```

Use the VNC password you configured in `gateway_config.sh`.

### 5. Clone the Complete Repository

Now that you're connected via VNC, clone the complete repository:

```sh
cd ~
git clone https://github.com/HosseinBeheshti/secure-remote-desktop-gateway.git
cd secure-remote-desktop-gateway
```

### 6. Configure Your Environment

⚠️ **IMPORTANT**: Before proceeding further, you MUST modify the `gateway_config.sh` file with your specific settings:

```sh
vim gateway_config.sh
```

Make sure to set:
- VPN server IP address
- Server public IP address
- Remote PC IP address 
- Default gateway (get with `ip route | grep default | awk '{print $3}'`)
- VPN credentials
- Remote desktop credentials

The scripts will not work correctly without these modifications!

### 7. Make Scripts Executable

Make all scripts executable:

```sh
chmod +x *.sh
```

### 8. Set Up the VPN Client

Run the VPN setup script from the root of the cloned repository:

```sh
sudo ./setup_vpn.sh
```

This configures L2TP/IPsec VPN, policy routing, and firewall rules.

### 9. Create and Launch Remmina Profile

Run the Remmina setup script from the root of the cloned repository:

```sh
./setup_remmina.sh
```

This creates a Remmina RDP profile and launches Remmina.

### 10. Troubleshoot (If Needed)

If you have issues connecting with Remmina, run:

```sh
./remmina_troubleshooting.sh
```

---

## Notes

- **Firewall**: The scripts configure UFW and remind you to set up cloud provider firewall rules.
- **Persistence**: Routing and firewall rules are made persistent across reboots.
- **Security**: Change all default passwords after setup.
- **VNC**: Connect to the server's IP on port 5901 using the credentials set in [`gateway_config.sh`](gateway_config.sh).

---

## File Overview

- [`gateway_config.sh`](gateway_config.sh): All configuration variables.
- [`setup_server.sh`](setup_server.sh): Installs and configures VNC, Remmina, firewall.
- [`setup_vpn.sh`](setup_vpn.sh): Sets up L2TP/IPsec VPN client and policy routing.
- [`setup_remmina.sh`](setup_remmina.sh): Creates Remmina RDP profile.
- [`remmina_troubleshooting.sh`](remmina_troubleshooting.sh): Troubleshooting script for Remmina/VPN issues.

---

## Troubleshooting

- Check VPN status: `sudo ipsec statusall`
- Check VNC logs: `cat /home/vncuser/.vnc/*.log`
- Check Remmina logs: See Remmina GUI or run from terminal for output.
- Inspect traffic: `sudo tcpdump -i any -nn -v host <REMOTE_PC_IP>`

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.