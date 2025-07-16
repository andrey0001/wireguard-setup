# WireGuard VPN Server Setup Script

A comprehensive bash script for setting up and managing a WireGuard VPN server on Debian-based Linux systems.

## Features

- **Easy Setup**: Quickly deploy a WireGuard VPN server with sensible defaults
- **NAT Configuration**: Automatically configures NAT for the WireGuard interface
- **Enhanced Security**: Uses preshared keys for additional security
- **Client Management**: Generate and manage client configurations
- **QR Code Generation**: Creates scannable QR codes for easy mobile setup
- **Multiple Interfaces**: Support for multiple WireGuard interfaces (wg0, wg1, etc.)
- **Custom DNS**: Configure custom DNS servers for clients
- **Persistent Configuration**: Saves settings for future client additions

## Requirements

- Debian-based Linux system (Ubuntu, Debian, etc.)
- Root privileges
- Internet connection

## Installation

1. Download the script:
   ```bash
   wget https://example.com/wireguard-setup.sh
   ```

2. Make it executable:
   ```bash
   chmod +x wireguard-setup.sh
   ```

## Usage

```
Usage: ./wireguard-setup.sh [options]
Options:
  -s, --subnet SUBNET     Specify subnet (default: 10.0.0.0/24)
  -p, --port PORT         Specify port (default: 51820)
  -c, --clients COUNT     Number of clients to create (default: 1)
  -i, --interface NAME    WireGuard interface name (default: wg0)
  -d, --dns DNS_SERVERS   Comma-separated list of DNS servers (default: 1.1.1.1,8.8.8.8)
  -a, --add-client NAME   Add a new client to existing setup
  -h, --help              Display this help message
```

## Examples

### Basic Setup

Set up a WireGuard server with default settings:

```bash
sudo ./wireguard-setup.sh
```

This will:
- Create a WireGuard interface named `wg0`
- Use subnet `10.0.0.0/24`
- Listen on port `51820`
- Create 1 client configuration
- Use Cloudflare and Google DNS servers (1.1.1.1, 8.8.8.8)

### Custom Setup

Set up a WireGuard server with custom settings:

```bash
sudo ./wireguard-setup.sh --subnet 192.168.5.0/24 --port 51821 --clients 3 --dns "9.9.9.9,1.1.1.1"
```

This will:
- Create a WireGuard interface named `wg0`
- Use subnet `192.168.5.0/24`
- Listen on port `51821`
- Create 3 client configurations
- Use Quad9 and Cloudflare DNS servers (9.9.9.9, 1.1.1.1)

### Multiple Interfaces

Set up a second WireGuard interface:

```bash
sudo ./wireguard-setup.sh --interface wg1 --subnet 10.1.0.0/24 --port 51821
```

This will create a separate WireGuard interface with its own configuration and clients.

### Adding Clients

Add a new client to an existing WireGuard server:

```bash
sudo ./wireguard-setup.sh --add-client john
```

Add a client to a specific interface:

```bash
sudo ./wireguard-setup.sh --interface wg1 --add-client jane
```

Add a client with custom DNS:

```bash
sudo ./wireguard-setup.sh --add-client bob --dns "192.168.1.1,8.8.8.8"
```

## Configuration Files

The script creates and manages the following files:

- **Server Configuration**: `/etc/wireguard/wg0.conf` (or wg1.conf, etc.)
- **Client Configurations**: `/etc/wireguard/clients/wg0/client1.conf` (and others)
- **QR Codes**: `/etc/wireguard/clients/wg0/client1.png` (and others)
- **Script Configuration**: `wireguard-setup.conf` (in the current directory)

## Client Setup

### Mobile Devices

1. Install the WireGuard app from the App Store or Google Play
2. Scan the QR code displayed in the terminal or saved as PNG
3. Activate the VPN connection

### Desktop Devices

1. Install the WireGuard client for your OS
2. Copy the client configuration file from `/etc/wireguard/clients/wg0/client1.conf`
3. Import the configuration into the WireGuard client
4. Activate the VPN connection

## Advanced Usage

### Running Multiple Instances

You can run multiple instances of the script from different directories to manage separate WireGuard setups:

```bash
# In directory A
mkdir -p ~/vpn-office
cd ~/vpn-office
sudo ~/wireguard-setup.sh --interface wg0

# In directory B
mkdir -p ~/vpn-home
cd ~/vpn-home
sudo ~/wireguard-setup.sh --interface wg1
```

Each directory will have its own `wireguard-setup.conf` file, allowing you to manage different WireGuard setups independently.

### Firewall Configuration

The script configures NAT and basic firewall rules, but you may need to open the WireGuard port in your firewall:

```bash
sudo ufw allow 51820/udp  # For default setup
sudo ufw allow 51821/udp  # For additional interfaces
```

## Troubleshooting

### Client Cannot Connect

1. Verify the server is running:
   ```bash
   sudo wg show
   ```

2. Check if the port is open:
   ```bash
   sudo ss -lnpu | grep wg
   ```

3. Verify firewall rules:
   ```bash
   sudo ufw status
   ```

### Connection Issues

If clients can connect but cannot access the internet:

1. Verify IP forwarding is enabled:
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   ```
   Should return `1`

2. Check NAT configuration:
   ```bash
   sudo iptables -t nat -L -v
   ```
   Should show MASQUERADE rules for the WireGuard interface

## Security Considerations

- The script generates strong keys and uses preshared keys for additional security
- Client configurations contain sensitive information and should be protected
- Consider using a firewall to restrict access to the WireGuard port
- Regularly update your system to patch security vulnerabilities

## License

This script is provided under the MIT License. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
