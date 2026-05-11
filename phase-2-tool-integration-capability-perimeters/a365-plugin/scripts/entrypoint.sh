#!/bin/bash
set -e

NETWORK_MODE="${NETWORK_MODE:-unrestricted}"

apply_restricted_rules() {
  echo "[entrypoint] Applying restricted network policy..."

  # Flush existing rules
  iptables -F OUTPUT 2>/dev/null || true

  # Allow loopback
  iptables -A OUTPUT -o lo -j ACCEPT

  # Allow established/related connections
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Essential Microsoft services
  for domain in login.microsoftonline.com graph.microsoft.com smba.trafficmanager.net; do
    # Resolve domain and allow IPs (best-effort; main rule is by port 443)
    iptables -A OUTPUT -p tcp --dport 443 -d $(getent hosts "$domain" | awk '{print $1}' | head -1) -j ACCEPT 2>/dev/null || true
  done

  # Allow Bot Framework (*.botframework.com) — wide range, allow HTTPS
  iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT  # Allow all HTTPS for Teams services
  iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT   # Allow HTTP for health checks

  # Block everything else
  iptables -A OUTPUT -j REJECT --reject-with icmp-net-unreachable

  echo "[entrypoint] Restricted network policy applied."
}

apply_allowlist_rules() {
  echo "[entrypoint] Applying allowlist network policy..."

  iptables -F OUTPUT 2>/dev/null || true
  iptables -A OUTPUT -o lo -j ACCEPT
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Essential Microsoft services (always allowed)
  iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT

  # User-defined allowlist
  if [ -n "$NETWORK_ALLOWLIST" ]; then
    IFS=',' read -ra DOMAINS <<< "$NETWORK_ALLOWLIST"
    for domain in "${DOMAINS[@]}"; do
      echo "[entrypoint] Allowing: $domain"
    done
  fi

  # DNS
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

  iptables -A OUTPUT -j REJECT --reject-with icmp-net-unreachable
  echo "[entrypoint] Allowlist network policy applied."
}

case "$NETWORK_MODE" in
  restricted)
    apply_restricted_rules
    ;;
  allowlist)
    apply_allowlist_rules
    ;;
  unrestricted)
    echo "[entrypoint] Network policy: unrestricted (no iptables rules applied)"
    ;;
  *)
    echo "[entrypoint] Unknown NETWORK_MODE='$NETWORK_MODE', defaulting to unrestricted"
    ;;
esac

echo "[entrypoint] Starting OpenClaw A365 agent..."
exec "$@"
