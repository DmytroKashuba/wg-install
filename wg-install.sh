#!/bin/bash
# WireGuard Manager v9.1 (UFW Edition)
# Tested on Ubuntu 22.04–24.10

set -e

# ---------- COLORS ----------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
RESET="\033[0m"

clear
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo -e "   ${GREEN}WireGuard Manager v9.1 (UFW Edition)${RESET}"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo ""

# ---------- CHECK ROOT ----------
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Ошибка:${RESET} запустите скрипт от root."
  exit 1
fi

# ---------- INPUTS ----------
read -rp "Введите порт для WireGuard [51820]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-51820}

read -rp "Введите имя клиента [client1]: " CLIENT_NAME
CLIENT_NAME=${CLIENT_NAME:-client1}

echo ""
echo "Выберите DNS-сервер:"
echo "1) Yandex (77.88.8.8)"
echo "2) Cloudflare (1.1.1.1)"
echo "3) Google (8.8.8.8)"
echo "4) Quad9 (9.9.9.9)"
read -rp "Ваш выбор [1]: " DNS_CHOICE
case $DNS_CHOICE in
  2) DNS="1.1.1.1";;
  3) DNS="8.8.8.8";;
  4) DNS="9.9.9.9";;
  *) DNS="77.88.8.8";;
esac

# ---------- VARIABLES ----------
SERVER_IF="wg0"
SERVER_DIR="/etc/wireguard"
SERVER_IP=$(hostname -I | awk '{print $1}')
PRIVATE_SUBNET="10.66.66.0/24"
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
CLIENT_PSK=$(wg genpsk)
CLIENT_IP="10.66.66.2"

# ---------- INSTALL PACKAGES ----------
echo -e "\n${YELLOW}[1/6] Установка пакетов...${RESET}"
apt update -y >/dev/null
apt install -y wireguard ufw qrencode >/dev/null

# ---------- ENABLE IP FORWARDING ----------
echo -e "${YELLOW}[2/6] Включаем IPv4 форвардинг...${RESET}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# ---------- GENERATE CONFIG ----------
echo -e "${YELLOW}[3/6] Генерация ключей и конфигов...${RESET}"
mkdir -p "$SERVER_DIR"
chmod 700 "$SERVER_DIR"

# Server config
cat > "$SERVER_DIR/$SERVER_IF.conf" <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
PostUp = ufw route allow in on $SERVER_IF out on eth0
PostDown = ufw route delete allow in on $SERVER_IF out on eth0
SaveConfig = true
EOF

# Client config
cat > "/root/$CLIENT_NAME.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $CLIENT_IP/32
DNS = $DNS

[Peer]
PublicKey = $SERVER_PUB_KEY
PresharedKey = $CLIENT_PSK
Endpoint = $SERVER_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# Add client to server
cat >> "$SERVER_DIR/$SERVER_IF.conf" <<EOF

[Peer]
PublicKey = $CLIENT_PUB_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = $CLIENT_IP/32
EOF

# ---------- FIREWALL CONFIG ----------
echo -e "${YELLOW}[4/6] Настройка UFW...${RESET}"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow $SERVER_PORT/udp
ufw --force enable >/dev/null

# ---------- ENABLE WG ----------
echo -e "${YELLOW}[5/6] Запуск WireGuard...${RESET}"
systemctl enable --now wg-quick@$SERVER_IF >/dev/null 2>&1

# ---------- DONE ----------
echo -e "${GREEN}[6/6] Успешно завершено!${RESET}\n"
echo -e "Серверный конфиг: ${CYAN}$SERVER_DIR/$SERVER_IF.conf${RESET}"
echo -e "Клиентский конфиг: ${CYAN}/root/$CLIENT_NAME.conf${RESET}\n"

echo -e "QR-код клиента ${YELLOW}$CLIENT_NAME${RESET}:"
qrencode -t ANSIUTF8 < "/root/$CLIENT_NAME.conf"
echo ""
echo -e "${GREEN}WireGuard успешно установлен и запущен.${RESET}"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
