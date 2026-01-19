#!/bin/bash
# Initialize firewall with domain whitelist
# This script sets up iptables rules to only allow outbound connections to whitelisted domains

set -e

CONFIG_FILE="${FIREWALL_CONFIG:-/workspace/.devcontainer/allowed-domains.conf}"
FALLBACK_CONFIG="/usr/local/etc/allowed-domains.conf"

# Use fallback if workspace config doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "$FALLBACK_CONFIG" ]]; then
        CONFIG_FILE="$FALLBACK_CONFIG"
    else
        echo "Warning: No domain whitelist found at $CONFIG_FILE or $FALLBACK_CONFIG"
        echo "Firewall will not be configured."
        exit 0
    fi
fi

echo "Loading allowed domains from: $CONFIG_FILE"

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT 2>/dev/null || true

# Default policies - allow all INPUT, restrict OUTPUT
iptables -P INPUT ACCEPT
iptables -P OUTPUT DROP

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (needed for domain resolution)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Function to resolve domain and add iptables rules
allow_domain() {
    local domain="$1"

    # Skip empty lines and comments
    [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]] && return 0

    # Trim whitespace
    domain=$(echo "$domain" | xargs)
    [[ -z "$domain" ]] && return 0

    echo "Allowing: $domain"

    # Resolve domain to IP addresses
    local ips
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)

    if [[ -z "$ips" ]]; then
        echo "  Warning: Could not resolve $domain"
        return 0
    fi

    # Add iptables rules for each IP
    for ip in $ips; do
        iptables -A OUTPUT -d "$ip" -p tcp --dport 443 -j ACCEPT
        iptables -A OUTPUT -d "$ip" -p tcp --dport 80 -j ACCEPT
        echo "  Added: $ip"
    done
}

# Read and process config file
while IFS= read -r line || [[ -n "$line" ]]; do
    allow_domain "$line"
done < "$CONFIG_FILE"

# Allow git protocol (for SSH-based git operations)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Log dropped packets (optional, for debugging)
# iptables -A OUTPUT -j LOG --log-prefix "DROPPED: " --log-level 4

echo ""
echo "Firewall configured successfully!"
echo "Allowed domains loaded from: $CONFIG_FILE"
echo ""
echo "To add new domains:"
echo "  1. Edit $CONFIG_FILE"
echo "  2. Run: firewall-reload (or: sudo /usr/local/bin/init-firewall.sh)"
