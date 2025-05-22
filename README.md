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

### 1. Clone the Repository

```sh
git clone https://github.com/HosseinBeheshti/secure-remote-desktop-gateway.git
cd secure-remote-desktop-gateway
```

### 2. Configure Your Environment

Edit [`gateway-config.sh`](gateway-config.sh) and set all variables according to your environment (VPN server IP, credentials, remote PC IP, etc).

### 3. Make Scripts Executable

```sh
chmod +x setup_server.sh setup_vpn.sh setup_remmina.sh remmina_troubleshooting.sh
```

### 4. Run the Server Setup

This installs all required packages, configures VNC, Remmina, and firewall.

```sh
sudo ./setup_server.sh
```

### 5. Connect to the VNC Server

For the remaining steps, you should connect to the VNC server that was just set up. Use your VNC client to connect to the server:

```
[Server IP]:5901
```

Use the VNC password you configured in `gateway-config.sh`.

### 6. Set Up the VPN Client

This configures L2TP/IPsec VPN, policy routing, and firewall rules.

```sh
sudo ./setup_vpn.sh
```

### 7. Create and Launch Remmina Profile

This creates a Remmina RDP profile and launches Remmina.

```sh
./setup_remmina.sh
```

### 8. Troubleshoot (If Needed)

If you have issues connecting with Remmina, run:

```sh
./remmina_troubleshooting.sh
```

---

## Notes

- **Firewall**: The scripts configure UFW and remind you to set up cloud provider firewall rules.
- **Persistence**: Routing and firewall rules are made persistent across reboots.
- **Security**: Change all default passwords after setup.
- **VNC**: Connect to the server's IP on port 5901 using the credentials set in [`gateway-config.sh`](gateway-config.sh).

---

## File Overview

- [`gateway-config.sh`](gateway-config.sh): All configuration variables.
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