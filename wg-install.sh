#!/bin/bash
# WireGuard Manager v9.2 (UFW Edition)
# by Dmytro Kashuba
# Compatible with Ubuntu 22.04–24.10

set -e

# === Цвета ===
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
RESET="\033[0m"

clear
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo -e "   ${GREEN}WireGuard Manager v9.2 (UFW Edition)${RESET}"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo ""

# === Проверка прав ===
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Ошибка:${RESET} запусти скрипт от root"
  exit 1
fi

# === Ввод параметров ===
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

# === Переменные ===
SERVER_IF="wg0"
SERVER_DIR="/etc/wireguard"
PRIVATE_SUBNET="10.66.66.0/24"
SERVER_IP_V4="10.66.66.1"
CLIENT_IP_V4="10.66.66.2"

WAN_IF=$(ip route get 8.8.8.8 | grep -oP '(?<=dev )\S+' | head -1)
[ -z "$WAN_IF" ] && WAN_IF="eth0"

SERVER_PUBLIC_IP=$(curl -4 -s https://ifconfig.me || curl -4 -s https://ipinfo.io/ip || hostname -I | awk '{print $1}')
[ -z "$SERVER_PUBLIC_IP" ] && SERVER_PUBLIC_IP="YOUR_SERVER_IP"

# === Установка пакетов ===
echo -e "\n${YELLOW}[1/6] Установка пакетов...${RESET}"
apt update -y >/dev/null
apt install -y wireguard wireguard-tools ufw qrencode curl resolvconf >/dev/null

# === Включение IPv4 форвардинга ===
echo -e "${YELLOW}[2/6] Включаем IPv4 форвардинг...${RESET}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf \
  && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
  || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# === Генерация ключей ===
echo -e "${YELLOW}[3/6] Генерация ключей...${RESET}"
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
CLIENT_PSK=$(wg genpsk)

# === Конфиги ===
echo -e "${YELLOW}[4/6] Создание конфигов...${RESET}"
mkdir -p $SERVER_DIR
chmod 700 $SERVER_DIR

cat > $SERVER_DIR/$SERVER_IF.conf <<EOF
[Interface]
Address = ${SERVER_IP_V4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
SaveConfig = true
PostUp = ufw route allow in on ${SERVER_IF} out on ${WAN_IF}
PostDown = ufw route delete allow in on ${SERVER_IF} out on ${WAN_IF}
EOF

cat > /root/${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP_V4}/24
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

cat >> $SERVER_DIR/$SERVER_IF.conf <<EOF

[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP_V4}/32
EOF

# === Настройка UFW ===
echo -e "${YELLOW}[5/6] Настройка UFW...${RESET}"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow ${SERVER_PORT}/udp
ufw --force enable >/dev/null

# === Запуск WireGuard ===
echo -e "${YELLOW}[6/6] Запуск WireGuard...${RESET}"
systemctl enable --now wg-quick@${SERVER_IF} >/dev/null 2>&1

# === Готово ===
echo -e "\n${GREEN}✅ WireGuard успешно установлен и запущен.${RESET}"
echo -e "Серверный конфиг: ${CYAN}${SERVER_DIR}/${SERVER_IF}.conf${RESET}"
echo -e "Клиентский конфиг: ${CYAN}/root/${CLIENT_NAME}.conf${RESET}\n"
echo -e "QR-к
