#!/bin/bash
# WireGuard Manager v10.1 (UFW + NAT fixed)

set -e
[ "$EUID" -ne 0 ] && { echo "Run as root."; exit 1; }

CONFIG_DIR="/etc/wireguard"
SERVER_IF="wg0"
SERVER_SUBNET_V4="10.66.66.0/24"
SERVER_IP_V4="10.66.66.1"

# --- Define WAN interface automatically ---
WAN_IF=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -n1)
[ -z "$WAN_IF" ] && { echo "Cannot detect WAN interface."; exit 1; }

SERVER_CONF="${CONFIG_DIR}/${SERVER_IF}.conf"

# --- Colors ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- Helper: Generate next IP ---
next_ip() {
  local last_ip=$(grep -Eo '10\.66\.66\.[0-9]+' $SERVER_CONF | sort -t. -k4 -n | tail -1 | awk -F. '{print $4}')
  [[ -z "$last_ip" ]] && last_ip=1
  echo "10.66.66.$((last_ip+1))"
}

# --- Helper: restart WG ---
restart_wg() {
  systemctl restart wg-quick@${SERVER_IF}
  ufw reload >/dev/null 2>&1 || true
}

# --- Installation if no config ---
if [ ! -f "$SERVER_CONF" ]; then
  echo -e "${CYAN}[1/6] Installing packages...${NC}"
  apt update -y >/dev/null && apt install -y wireguard qrencode curl ufw iptables resolvconf >/dev/null

  echo -e "${CYAN}[2/6] Enabling IPv4 forwarding...${NC}"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf \
    && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
    || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  echo -e "${CYAN}[3/6] Setting up SSH access...${NC}"
  echo "1) Allow SSH from anywhere"
  echo "2) Restrict SSH to specific IP/DNS"
  read -p "Choose option [1-2]: " SSH_CHOICE
  if [[ $SSH_CHOICE == 2 ]]; then
    read -p "Enter allowed IPs or hostnames (space separated): " SSH_IPS
  fi

  echo -e "${CYAN}[4/6] Selecting DNS...${NC}"
  echo "1) Yandex (77.88.8.8)"
  echo "2) Cloudflare (1.1.1.1)"
  echo "3) Google (8.8.8.8)"
  echo "4) Quad9 (9.9.9.9)"
  read -p "Choose DNS [1-4]: " DNS_CHOICE
  case $DNS_CHOICE in
    1) DNS_SERVER="77.88.8.8" ;;
    2) DNS_SERVER="1.1.1.1" ;;
    3) DNS_SERVER="8.8.8.8" ;;
    4) DNS_SERVER="9.9.9.9" ;;
    *) DNS_SERVER="77.88.8.8" ;;
  esac

  read -p "Enter server port [51820]: " SERVER_PORT
  SERVER_PORT=${SERVER_PORT:-51820}

  echo -e "${CYAN}[5/6] Generating keys...${NC}"
  SERVER_PRIV_KEY=$(wg genkey)
  SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
  CLIENT_PRIV_KEY=$(wg genkey)
  CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
  CLIENT_PSK=$(wg genpsk)

  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"

  SERVER_PUBLIC_IP=$(curl -4 -s https://ifconfig.me || curl -4 -s https://ipinfo.io/ip || true)
  [ -z "$SERVER_PUBLIC_IP" ] && SERVER_PUBLIC_IP="YOUR_SERVER_IP"

  echo -e "${CYAN}[6/6] Creating server config...${NC}"
  cat > "$SERVER_CONF" <<EOF
[Interface]
Address = ${SERVER_IP_V4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
SaveConfig = true

PostUp = ufw route allow in on %i out on ${WAN_IF}
PostUp = iptables -t nat -A POSTROUTING -s ${SERVER_SUBNET_V4} -o ${WAN_IF} -j MASQUERADE
PostDown = ufw route delete allow in on %i out on ${WAN_IF}
PostDown = iptables -t nat -D POSTROUTING -s ${SERVER_SUBNET_V4} -o ${WAN_IF} -j MASQUERADE
EOF

  chmod 600 "$SERVER_CONF"

  CLIENT_IP_V4="10.66.66.2"
  CLIENT_NAME="client1"
  CLIENT_CONF="/root/${CLIENT_NAME}.conf"

  cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP_V4}/24
DNS = ${DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

  chmod 600 "$CLIENT_CONF"

  cat >> "$SERVER_CONF" <<EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP_V4}/32
EOF

  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ${SERVER_PORT}/udp
  if [[ $SSH_CHOICE == 2 && -n "$SSH_IPS" ]]; then
    ufw delete allow ssh >/dev/null 2>&1 || true
    for ip in $SSH_IPS; do ufw allow from $ip to any port 22; done
    echo "SSH allowed only for: $SSH_IPS"
  else
    ufw allow ssh
  fi
  ufw --force enable

  systemctl enable wg-quick@${SERVER_IF} >/dev/null
  restart_wg

  echo -e "\n${GREEN}Server ready!${NC}"
  echo "Server config: ${SERVER_CONF}"
  echo "Client config: ${CLIENT_CONF}"
  qrencode -t ANSIUTF8 < "$CLIENT_CONF"
  exit 0
fi

# --- Management Menu ---
while true; do
  clear
  echo -e "${YELLOW}──────────── WireGuard Manager Menu ────────────${NC}"
  echo "1) Add new client"
  echo "2) Remove client"
  echo "3) Show client QR"
  echo "4) List clients"
  echo "5) Change server port"
  echo "6) Change DNS for all clients"
  echo "7) Restart WireGuard"
  echo "0) Exit"
  echo -e "${YELLOW}──────────────────────────────────────────────${NC}"
  read -p "Choose: " CHOICE

  case $CHOICE in
    1)
      read -p "Client name: " CLIENT_NAME
      CLIENT_IP_V4=$(next_ip)
      CLIENT_PRIV_KEY=$(wg genkey)
      CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
      CLIENT_PSK=$(wg genpsk)
      SERVER_PUB_KEY=$(grep PrivateKey $SERVER_CONF -A1 | grep -v PrivateKey | grep -v Address | grep -v ListenPort | grep -v SaveConfig | grep -m1 . || echo "")

      SERVER_PUBLIC_IP=$(curl -4 -s https://ifconfig.me || true)
      SERVER_PORT=$(grep ListenPort $SERVER_CONF | awk '{print $3}')
      DNS_SERVER=$(grep "DNS =" /root/client1.conf | awk '{print $3}' || echo "77.88.8.8")
      CLIENT_CONF="/root/${CLIENT_NAME}.conf"

      cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP_V4}/24
DNS = ${DNS_SERVER}

[Peer]
PublicKey = $(grep PrivateKey $SERVER_CONF -A1 | tail -n1 | wg pubkey 2>/dev/null || echo "")
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
      cat >> "$SERVER_CONF" <<EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP_V4}/32
EOF
      restart_wg
      echo -e "${GREEN}Client added:${NC} ${CLIENT_NAME}"
      qrencode -t ANSIUTF8 < "$CLIENT_CONF"
      ;;
    2)
      read -p "Client name to remove: " CLIENT_NAME
      sed -i "/# ${CLIENT_NAME}/,/AllowedIPs/d" "$SERVER_CONF"
      rm -f "/root/${CLIENT_NAME}.conf"
      restart_wg
      echo -e "${GREEN}Client removed.${NC}"
      ;;
    3)
      read -p "Client name to show QR: " CLIENT_NAME
      qrencode -t ANSIUTF8 < "/root/${CLIENT_NAME}.conf"
      ;;
    4)
      grep "# " "$SERVER_CONF" | cut -d' ' -f2
      ;;
    5)
      read -p "New port: " NEW_PORT
      OLD_PORT=$(grep ListenPort "$SERVER_CONF" | awk '{print $3}')
      sed -i "s/ListenPort = ${OLD_PORT}/ListenPort = ${NEW_PORT}/" "$SERVER_CONF"
      ufw delete allow ${OLD_PORT}/udp >/dev/null 2>&1 || true
      ufw allow ${NEW_PORT}/udp
      restart_wg
      echo -e "${GREEN}Port changed to ${NEW_PORT}.${NC}"
      ;;
    6)
      echo "1) Yandex (77.88.8.8)"
      echo "2) Cloudflare (1.1.1.1)"
      echo "3) Google (8.8.8.8)"
      echo "4) Quad9 (9.9.9.9)"
      read -p "Choose DNS [1-4]: " DNS_CHOICE
      case $DNS_CHOICE in
        1) DNS_SERVER="77.88.8.8" ;;
        2) DNS_SERVER="1.1.1.1" ;;
        3) DNS_SERVER="8.8.8.8" ;;
        4) DNS_SERVER="9.9.9.9" ;;
        *) DNS_SERVER="77.88.8.8" ;;
      esac
      sed -i "s/^DNS =.*/DNS = ${DNS_SERVER}/" /root/*.conf
      echo -e "${GREEN}DNS changed for all clients to ${DNS_SERVER}.${NC}"
      ;;
    7)
      restart_wg
      echo -e "${GREEN}WireGuard restarted.${NC}"
      ;;
    0) exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
done
