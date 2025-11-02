#!/bin/bash
set -e

# Проверка root
[ "$EUID" -ne 0 ] && { echo "Запусти от root"; exit 1; }

# === Ввод параметров ===
read -p "Введите порт для WireGuard [51820]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-51820}

read -p "Введите имя клиента [client1]: " CLIENT_NAME
CLIENT_NAME=${CLIENT_NAME:-client1}

# === Настройки ===
SERVER_IF="wg0"
SERVER_SUBNET_V4="10.66.66.0/24"
SERVER_IP_V4="10.66.66.1"
CLIENT_IP_V4="10.66.66.2"
DNS_SERVER="77.88.8.8"    # ← Яндекс DNS по умолчанию

# === Определение WAN-интерфейса ===
WAN_IF=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}')
[ -z "$WAN_IF" ] && { echo "Не удалось определить WAN интерфейс."; exit 1; }

echo "[1/6] Установка пакетов..."
apt update -y && apt install -y wireguard qrencode iptables curl >/dev/null

echo "[2/6] Включаем IPv4 форвардинг..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf \
  && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf \
  || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "[3/6] Генерация ключей..."
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)

SERVER_PUBLIC_IP=$(curl -4 -s https://ifconfig.me || curl -4 -s https://ipinfo.io/ip || true)
[ -z "$SERVER_PUBLIC_IP" ] && SERVER_PUBLIC_IP="YOUR_SERVER_IP"

echo "[4/6] Создание конфигов..."
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard

cat > /etc/wireguard/${SERVER_IF}.conf <<EOF
[Interface]
Address = ${SERVER_IP_V4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
SaveConfig = true

PostUp = iptables -t nat -A POSTROUTING -s ${SERVER_SUBNET_V4} -o ${WAN_IF} -j MASQUERADE; iptables -A FORWARD -i ${WAN_IF} -o ${SERVER_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -A FORWARD -i ${SERVER_IF} -o ${WAN_IF} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${SERVER_SUBNET_V4} -o ${WAN_IF} -j MASQUERADE; iptables -D FORWARD -i ${WAN_IF} -o ${SERVER_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -D FORWARD -i ${SERVER_IF} -o ${WAN_IF} -j ACCEPT

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${CLIENT_IP_V4}/32
EOF

chmod 600 /etc/wireguard/${SERVER_IF}.conf

cat > /root/${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP_V4}/24
DNS = ${DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /root/${CLIENT_NAME}.conf

echo "[5/6] Запуск WireGuard..."
systemctl enable wg-quick@${SERVER_IF} >/dev/null
systemctl restart wg-quick@${SERVER_IF}

echo "[6/6] Готово."
echo
echo "Серверный конфиг: /etc/wireguard/${SERVER_IF}.conf"
echo "Клиентский конфиг: /root/${CLIENT_NAME}.conf"
echo
echo "QR-код клиента ${CLIENT_NAME}:"
qrencode -t ansiutf8 < /root/${CLIENT_NAME}.conf
echo
echo "Проверка статуса: wg show ${SERVER_IF}"
