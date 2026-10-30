#!/bin/bash
# Initialize firewall with domain/IP whitelist
# This script sets up iptables rules to only allow outbound connections to whitelisted
# domains, IPs and subnets. All outbound IPv6 traffic is blocked (except loopback).
#
# Whitelist entry format (one per line, # starts a comment):
#   github.com              TCP 80 and 443 to the domain's resolved IPs
#   github.com:22           only TCP 22 (ports replace the 80/443 default)
#   github.com:22,80,443    a comma-separated list of TCP ports
#   192.168.1.123           all ports and protocols to that IP
#   192.168.1.123:8080      only TCP 8080 (comma-separated lists work here too)
#   192.168.1.0/24          the whole subnet, all ports (ports are not supported for subnets)
# Rules add up, so listing both "github.com" and "github.com:22" allows 22, 80 and 443.

set -e

# Never resolve commands from /usr/local/bin, which the node user can write to
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

MOUNTED_CONFIG="/etc/claude-container/allowed-domains.conf"
WORKSPACE_CONFIG="/workspace/.devcontainer/allowed-domains.conf"
FALLBACK_CONFIG="/usr/local/etc/allowed-domains.conf"

# Written by container-init. With restricted sudo, a whitelist the node user can
# modify would let the agent open the firewall, so such files are ignored.
SUDO_MODE=$(cat /var/lib/claude-container/sudo-mode 2>/dev/null || echo full)

# True if the node user can modify the path, or any directory leading to it
node_can_modify() {
    local path="$1"
    while true; do
        runuser -u node -- test -w "$path" && return 0
        [[ "$path" == "/" ]] && return 1
        path=$(dirname "$path")
    done
}

# Lookup order: read-only mount from the host, workspace, baked-in default
CONFIG_FILE=""
for candidate in "$MOUNTED_CONFIG" "$WORKSPACE_CONFIG" "$FALLBACK_CONFIG"; do
    [[ -f "$candidate" ]] || continue
    if [[ "$SUDO_MODE" == "restricted" ]] && { node_can_modify "$candidate" || node_can_modify "$(realpath "$candidate")"; }; then
        echo "Ignoring $candidate: writable by node (sudo is restricted, mount the whitelist read-only)"
        continue
    fi
    CONFIG_FILE="$candidate"
    break
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Warning: No whitelist found at $MOUNTED_CONFIG, $WORKSPACE_CONFIG or $FALLBACK_CONFIG"
    echo "Firewall will not be configured."
    exit 0
fi

echo "Loading allowed domains from: $CONFIG_FILE"

WARNINGS=0
SELF_CHECK_DOMAIN=""

warn() {
    echo "  Warning: $*"
    WARNINGS=$((WARNINGS + 1))
}

# Block all outbound IPv6 except loopback and replies to inbound connections.
# ip6tables is always in the image, but fails when the host kernel has IPv6
# support disabled - in that case there is no IPv6 traffic to filter anyway.
configure_ipv6() {
    if ! ip6tables -L OUTPUT -n >/dev/null 2>&1; then
        warn "IPv6 unavailable in kernel (ip6tables failed), skipping IPv6 rules"
        return 0
    fi

    # A failing rule must not abort the IPv4 setup below; the DROP policy is set
    # first, so a partial failure still fails closed.
    local failed=0
    ip6tables -P OUTPUT DROP || failed=1
    ip6tables -F OUTPUT || failed=1
    ip6tables -F INPUT || failed=1
    ip6tables -P INPUT ACCEPT || failed=1
    ip6tables -A OUTPUT -o lo -j ACCEPT || failed=1
    ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || failed=1
    # Link-local neighbor discovery, needed to answer inbound IPv6 connections
    ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type neighbour-solicitation -j ACCEPT || failed=1
    ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type neighbour-advertisement -j ACCEPT || failed=1
    ip6tables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset || failed=1
    ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited || failed=1

    if (( failed )); then
        warn "Some IPv6 rules failed to apply, check: sudo ip6tables -L -n -v"
    else
        echo "IPv6: all outbound traffic blocked (loopback allowed)"
    fi
}

configure_ipv6

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT 2>/dev/null || true

# Default policies - allow all INPUT, restrict OUTPUT
iptables -P INPUT ACCEPT
iptables -P OUTPUT DROP

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow Docker bridge network (for DinD variant)
if ip link show docker0 &>/dev/null; then
    iptables -A OUTPUT -o docker0 -j ACCEPT
    echo "Allowing Docker bridge network (docker0)"
fi

# Allow Docker container networks
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (needed for domain resolution)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Append an OUTPUT accept rule unless an identical one already exists
allow_out() {
    iptables -C OUTPUT "$@" -j ACCEPT 2>/dev/null || iptables -A OUTPUT "$@" -j ACCEPT
}

# Allow TCP to a destination on each port of a comma-separated list
allow_tcp_ports() {
    local dest="$1" port
    local -a port_list
    IFS=',' read -ra port_list <<< "$2"
    for port in "${port_list[@]}"; do
        allow_out -d "$dest" -p tcp --dport "$port"
    done
}

is_ipv4() {
    local octet
    [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    for octet in "${BASH_REMATCH[@]:1}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

is_domain() {
    [[ "$1" =~ ^[A-Za-z0-9_]([A-Za-z0-9_-]*[A-Za-z0-9_])?(\.[A-Za-z0-9_]([A-Za-z0-9_-]*[A-Za-z0-9_])?)*$ ]]
}

# Comma-separated list of ports in the range 1-65535
is_port_list() {
    local port
    local -a port_list
    [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]] || return 1
    IFS=',' read -ra port_list <<< "$1"
    for port in "${port_list[@]}"; do
        (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
    done
}

# Resolve domain and allow its IPs on the given ports
allow_domain() {
    local domain="$1" ports="$2"

    echo "Allowing: $domain (TCP ports $ports)"

    # Resolve domain to IP addresses
    local ips
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)

    if [[ -z "$ips" ]]; then
        warn "Could not resolve $domain"
        return 0
    fi

    # Add iptables rules for each IP
    for ip in $ips; do
        allow_tcp_ports "$ip" "$ports"
        echo "  Added: $ip"
    done

    if [[ -z "$SELF_CHECK_DOMAIN" && ",$ports," == *",443,"* ]]; then
        SELF_CHECK_DOMAIN="$domain"
    fi
}

# Parse a whitelist line and add the matching rules
process_entry() {
    local entry="$1" host ports=""

    # Strip comments and surrounding whitespace (including CR from CRLF files)
    entry="${entry%%#*}"
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && return 0

    if [[ "$entry" == \[* || "$entry" == *:*:* ]]; then
        warn "Skipping '$entry': IPv6 entries are not supported (all outbound IPv6 is blocked)"
        return 0
    fi

    host="${entry%%:*}"
    if [[ "$entry" == *:* ]]; then
        ports="${entry#*:}"
        if ! is_port_list "$ports"; then
            warn "Skipping '$entry': invalid port list '$ports'"
            return 0
        fi
    fi

    if [[ "$host" == */* ]]; then
        local prefix="${host#*/}"
        if ! is_ipv4 "${host%/*}" || ! [[ "$prefix" =~ ^[0-9]{1,2}$ ]] || (( 10#$prefix > 32 )); then
            warn "Skipping '$entry': invalid subnet"
        elif [[ -n "$ports" ]]; then
            warn "Skipping '$entry': port restrictions are not supported for subnets"
        else
            echo "Allowing subnet: $host (all ports)"
            allow_out -d "$host"
        fi
    elif is_ipv4 "$host"; then
        if [[ -n "$ports" ]]; then
            echo "Allowing IP: $host (TCP ports $ports)"
            allow_tcp_ports "$host" "$ports"
        else
            echo "Allowing IP: $host (all ports)"
            allow_out -d "$host"
        fi
    elif is_domain "$host"; then
        allow_domain "$host" "${ports:-80,443}"
    else
        warn "Skipping '$entry': not a valid domain, IPv4 address or subnet"
    fi
}

# Read and process config file
while IFS= read -r line || [[ -n "$line" ]]; do
    process_entry "$line"
done < "$CONFIG_FILE"

# Allow git protocol (for SSH-based git operations)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Log dropped packets (optional, for debugging)
# iptables -A OUTPUT -j LOG --log-prefix "DROPPED: " --log-level 4

# Reject everything else so blocked connections fail immediately instead of timing out
iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# Self-check (warnings only, so offline or VPN startups still work)
echo ""
echo "Self-check:"
# 192.0.2.1 is TEST-NET-1 (RFC 5737) and never routed: a local REJECT answers
# "Connection refused" at once, without contacting any real host.
blocked_err=$(timeout 3 bash -c 'exec 3<>/dev/tcp/192.0.2.1/80' 2>&1) || true
if [[ "$blocked_err" == *"Connection refused"* ]]; then
    echo "  OK: non-whitelisted IP rejected"
else
    warn "Non-whitelisted IP (192.0.2.1:80) was not rejected"
fi
if [[ -n "$SELF_CHECK_DOMAIN" ]]; then
    if timeout 5 bash -c "exec 3<>/dev/tcp/$SELF_CHECK_DOMAIN/443" 2>/dev/null; then
        echo "  OK: whitelisted domain reachable ($SELF_CHECK_DOMAIN:443)"
    else
        warn "Whitelisted domain $SELF_CHECK_DOMAIN:443 not reachable (offline, or its IPs changed since resolving)"
    fi
fi

echo ""
echo "Firewall configured successfully!"
echo "Allowed domains loaded from: $CONFIG_FILE"
if (( WARNINGS > 0 )); then
    echo "$WARNINGS warning(s), see output above."
fi
echo ""
echo "To add new domains:"
echo "  1. Edit $CONFIG_FILE"
echo "  2. Run: firewall-reload (or: sudo /usr/local/sbin/init-firewall.sh)"
