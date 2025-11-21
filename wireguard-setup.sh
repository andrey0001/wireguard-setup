#!/bin/bash

# wireguard-setup.sh - WireGuard VPN Server Setup Script for Debian-based systems
# Features:
# - NAT configuration
# - Preshared key for additional security
# - Client configuration generation
# - Customizable subnet
# - Configurable client count
# - Ability to add clients to existing setup
# - Support for multiple interfaces
# - QR code generation as image files
# - Custom DNS settings

set -e

# Default values
DEFAULT_SUBNET="10.0.0.0/24"
DEFAULT_PORT="51820"
DEFAULT_CLIENT_COUNT=1
DEFAULT_INTERFACE="wg0"
DEFAULT_DNS="1.1.1.1,8.8.8.8"
CONFIG_FILE="wireguard-setup.conf"
CLIENT_DIR="/etc/wireguard/clients"

# Function to display usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --subnet SUBNET     Specify subnet (default: $DEFAULT_SUBNET)"
    echo "  -p, --port PORT         Specify port (default: $DEFAULT_PORT)"
    echo "  -c, --clients COUNT     Number of clients to create (default: $DEFAULT_CLIENT_COUNT)"
    echo "  -i, --interface NAME    WireGuard interface name (default: $DEFAULT_INTERFACE)"
    echo "  -d, --dns DNS_SERVERS   Comma-separated list of DNS servers (default: $DEFAULT_DNS)"
    echo "  -a, --add-client NAME   Add a new client to existing setup"
    echo "  -h, --help              Display this help message"
    exit 1
}

# Parse command line arguments
SUBNET=$DEFAULT_SUBNET
PORT=$DEFAULT_PORT
CLIENT_COUNT=$DEFAULT_CLIENT_COUNT
INTERFACE=$DEFAULT_INTERFACE
DNS=$DEFAULT_DNS
ADD_CLIENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subnet)
            SUBNET="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -c|--clients)
            CLIENT_COUNT="$2"
            shift 2
            ;;
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        -d|--dns)
            DNS="$2"
            shift 2
            ;;
        -a|--add-client)
            ADD_CLIENT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set server config path based on interface name
SERVER_CONFIG="/etc/wireguard/${INTERFACE}.conf"

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Function to check if WireGuard is already installed
check_wireguard() {
    if ! command -v wg &> /dev/null; then
        echo "WireGuard is not installed. Installing..."
        apt update
        apt install -y wireguard wireguard-tools
    else
        echo "WireGuard is already installed"
    fi
}

# Function to check if qrencode is installed
check_qrencode() {
    if ! command -v qrencode &> /dev/null; then
        echo "qrencode is not installed. Installing..."
        apt update
        apt install -y qrencode
    else
        echo "qrencode is already installed"
    fi
}

# Function to extract subnet base for IP assignments
get_subnet_base() {
    echo "$SUBNET" | cut -d'/' -f1 | sed 's/\.[0-9]*$//'
}

# Function to format DNS servers for client config
format_dns_servers() {
    # Replace commas with spaces
    # echo "$DNS" | tr ',' ' '
    echo "$DNS"
}

# Function to load existing configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo "Loaded existing configuration from $CONFIG_FILE"
        
        # Use the saved SERVER_CONFIG path if available
        if [[ -n "$SERVER_CONFIG_PATH" ]]; then
            SERVER_CONFIG="$SERVER_CONFIG_PATH"
            echo "Using server config path from configuration: $SERVER_CONFIG"
        fi
        
        # Use the saved interface name if available and not overridden by command line
        if [[ -n "$INTERFACE_NAME" && "$INTERFACE" == "$DEFAULT_INTERFACE" ]]; then
            INTERFACE="$INTERFACE_NAME"
            SERVER_CONFIG="/etc/wireguard/${INTERFACE}.conf"
            echo "Using interface name from configuration: $INTERFACE"
        fi
        
        # Use the saved DNS servers if available and not overridden by command line
        if [[ -n "$DNS_SERVERS" && "$DNS" == "$DEFAULT_DNS" ]]; then
            DNS="$DNS_SERVERS"
            echo "Using DNS servers from configuration: $DNS"
        fi
    else
        # Initialize configuration with default values
        SUBNET_BASE=$(get_subnet_base)
        SERVER_IP="${SUBNET_BASE}.1"
        LAST_CLIENT_IP=1
        SERVER_CONFIG_PATH="$SERVER_CONFIG"
        INTERFACE_NAME="$INTERFACE"
        DNS_SERVERS="$DNS"
        echo "Created new configuration"
    fi
}

# Function to save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# WireGuard configuration - $(date)
SUBNET="$SUBNET"
PORT="$PORT"
SUBNET_BASE="$SUBNET_BASE"
SERVER_IP="$SERVER_IP"
SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"
SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY"
LAST_CLIENT_IP=$LAST_CLIENT_IP
SERVER_CONFIG_PATH="$SERVER_CONFIG"
INTERFACE_NAME="$INTERFACE"
DNS_SERVERS="$DNS"
EOF
    echo "Configuration saved to $CONFIG_FILE"
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    echo "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf
}

# Function to configure NAT
configure_nat() {
    echo "Configuring NAT..."
    
    # Get the primary network interface
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}')
    
    # Configure iptables for NAT
    iptables -t nat -A POSTROUTING -o "$PRIMARY_INTERFACE" -j MASQUERADE
    
    # Make iptables rules persistent
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 || {
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
        }
    fi
    
    # Ensure rules are loaded on boot
    if [[ ! -f /etc/systemd/system/iptables-restore.service ]]; then
        cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables rules
Before=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore < /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable iptables-restore.service
    fi
}

# Function to generate server keys
generate_server_keys() {
    echo "Generating server keys..."
    SERVER_PRIVATE_KEY=$(wg genkey)
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
}

# Function to create server configuration
create_server_config() {
    echo "Creating server configuration..."
    
    mkdir -p /etc/wireguard
    mkdir -p "$CLIENT_DIR/${INTERFACE}"
    
    cat > "$SERVER_CONFIG" << EOF
[Interface]
Address = $SERVER_IP/24
ListenPort = $PORT
PrivateKey = $SERVER_PRIVATE_KEY
SaveConfig = true

# Enable NAT
PostUp = iptables -A FORWARD -i $INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
PostDown = iptables -D FORWARD -i $INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
EOF

    chmod 600 "$SERVER_CONFIG"
}

# Function to generate QR code for client
generate_qr_code() {
    local CLIENT_NAME=$1
    local CONFIG_PATH="$CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.conf"
    local QR_PATH="$CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.png"
    
    echo "Generating QR code for client $CLIENT_NAME..."
    
    # Generate QR code as PNG image
    qrencode -t PNG -o "$QR_PATH" < "$CONFIG_PATH"
    
    echo "QR code saved to $QR_PATH"
    
    # Also display QR code in terminal if running interactively
    if [ -t 1 ]; then
        echo "QR code for client configuration:"
        qrencode -t ansiutf8 < "$CONFIG_PATH" || echo "QR code display failed."
    fi
}

# Function to generate client keys and configuration
generate_client() {
    local CLIENT_NAME=$1
    local CLIENT_IP="${SUBNET_BASE}.$((LAST_CLIENT_IP + 1))"
    local FORMATTED_DNS=$(format_dns_servers)
    
    echo "Generating configuration for client: $CLIENT_NAME (IP: $CLIENT_IP)"
    
    # Generate client keys
    local CLIENT_PRIVATE_KEY=$(wg genkey)
    local CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
    local PRESHARED_KEY=$(wg genpsk)
    
    # Create client configuration
    mkdir -p "$CLIENT_DIR/${INTERFACE}"
    cat > "$CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.conf" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = $FORMATTED_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = $(curl -s ipv4.goip.info):$PORT
PersistentKeepalive = 25
EOF

    # Create a temporary file for the peer configuration
    local PEER_CONFIG=$(mktemp)
    cat > "$PEER_CONFIG" << EOF
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_IP/32
EOF

    # Add client to server configuration
    echo "Adding client $CLIENT_NAME to server configuration..."
    
    if [[ -f "$SERVER_CONFIG" ]]; then
        # Add peer to config file for initial setup
        cat >> "$SERVER_CONFIG" << EOF

# Client: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_IP/32
EOF
    fi

    # Ensure proper permissions
    chmod 600 "$SERVER_CONFIG"
    chmod 600 "$PEER_CONFIG"

    # Update last client IP
    LAST_CLIENT_IP=$((LAST_CLIENT_IP + 1))
    
    echo "Client configuration saved to $CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.conf"
    
    # Generate QR code
    generate_qr_code "$CLIENT_NAME"
    
    # Clean up
    rm -f "$PEER_CONFIG"
}

# Function to add a client to an existing setup
add_client_to_existing() {
    local CLIENT_NAME=$1
    
    echo "Adding new client $CLIENT_NAME to existing WireGuard server (interface: $INTERFACE)..."
    
    # Load existing configuration
    load_config
    
    # Check if server config exists
    if [[ ! -f "$SERVER_CONFIG" ]]; then
        echo "Server configuration not found at $SERVER_CONFIG"
        exit 1
    fi
    
    # Check if WireGuard interface is running
    if ! ip link show "$INTERFACE" &>/dev/null; then
        echo "WireGuard interface $INTERFACE is not running. Starting it..."
        systemctl start wg-quick@$INTERFACE
    fi
    
    echo "Using server configuration file: $SERVER_CONFIG"
    
    # Generate client keys
    local CLIENT_PRIVATE_KEY=$(wg genkey)
    local CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
    local PRESHARED_KEY=$(wg genpsk)
    
    # Calculate client IP
    local CLIENT_IP="${SUBNET_BASE}.$((LAST_CLIENT_IP + 1))"
    local FORMATTED_DNS=$(format_dns_servers)
    
    echo "Assigning IP address $CLIENT_IP to client $CLIENT_NAME"
    echo "Using DNS servers: $FORMATTED_DNS"
    
    # Create client configuration
    mkdir -p "$CLIENT_DIR/${INTERFACE}"
    cat > "$CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.conf" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = $FORMATTED_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = $(curl -s ifconfig.me):$PORT
PersistentKeepalive = 25
EOF
    
    # Create a temporary file for the peer configuration
    local PEER_CONFIG=$(mktemp)
    cat > "$PEER_CONFIG" << EOF
$PRESHARED_KEY
EOF
    
    # THIS IS THE CRITICAL PART: Add client as peer to server using wg command
    echo "Adding client $CLIENT_NAME as peer to WireGuard interface $INTERFACE..."
    wg set "$INTERFACE" peer "$CLIENT_PUBLIC_KEY" preshared-key "$PEER_CONFIG" allowed-ips "$CLIENT_IP/32"
    
    # Verify the client was added
    if wg show "$INTERFACE" | grep -q "$CLIENT_PUBLIC_KEY"; then
        echo "Successfully added client $CLIENT_NAME as peer to WireGuard"
        wg show "$INTERFACE" | grep -A 2 "$CLIENT_PUBLIC_KEY"
    else
        echo "ERROR: Failed to add client to WireGuard"
        exit 1
    fi
    
    # Save the configuration to ensure it persists
    wg-quick save "$INTERFACE"
    
    # Update last client IP and save configuration
    LAST_CLIENT_IP=$((LAST_CLIENT_IP + 1))
    save_config
    
    echo "Client $CLIENT_NAME added successfully with IP $CLIENT_IP"
    echo "Client configuration saved to $CLIENT_DIR/${INTERFACE}/${CLIENT_NAME}.conf"
    
    # Generate QR code
    generate_qr_code "$CLIENT_NAME"
    
    # Clean up
    rm -f "$PEER_CONFIG"
}

# Main function for initial setup
setup_wireguard() {
    check_root
    check_wireguard
    check_qrencode
    
    # Install additional required packages
    apt install -y curl
    
    # Load or initialize configuration
    load_config
    
    # Set up subnet base and server IP
    SUBNET_BASE=$(get_subnet_base)
    SERVER_IP="${SUBNET_BASE}.1"
    LAST_CLIENT_IP=1
    SERVER_CONFIG_PATH="$SERVER_CONFIG"
    INTERFACE_NAME="$INTERFACE"
    DNS_SERVERS="$DNS"
    
    echo "Using DNS servers: $DNS"
    
    enable_ip_forwarding
    configure_nat
    generate_server_keys
    create_server_config
    
    # Generate client configurations
    for ((i=1; i<=CLIENT_COUNT; i++)); do
        generate_client "client$i"
    done
    
    # Save configuration
    save_config
    
    # Enable and start WireGuard
    systemctl enable wg-quick@$INTERFACE
    systemctl start wg-quick@$INTERFACE
    
    echo "WireGuard setup completed successfully!"
    echo "Interface: $INTERFACE"
    echo "Server IP: $SERVER_IP"
    echo "Server Public Key: $SERVER_PUBLIC_KEY"
    echo "DNS Servers: $DNS"
    echo "Client configurations are saved in $CLIENT_DIR/${INTERFACE}/"
    echo "Server configuration is at $SERVER_CONFIG"
    echo "To add additional clients, run: $0 --interface $INTERFACE --add-client CLIENT_NAME"
}

# Main execution
if [[ -n "$ADD_CLIENT" ]]; then
    check_root  # Ensure we're running as root
    check_qrencode  # Ensure qrencode is installed
    add_client_to_existing "$ADD_CLIENT"
else
    setup_wireguard
fi
