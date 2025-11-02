#!/bin/bash
# WireGuard Manager v10.0
# All-in-one installer + manager
# Ubuntu 22.04 - 24.10

set -e

# ===== Colors =====
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
RESET="\033[0m"

WG_IF="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
SUBNET_PREFIX="10.66.66"
SERVER_IP_V4="${SUBNET_PREFIX}.1"
FIRST_CLIENT_IP_V4="${SUBNET_PREFIX}.2"

# ===== Helpers =====
header() {
    clear
    echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
    echo -e "   ${GREEN}WireGuard Manager v10.0${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────${RESET}\n"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Ошибка:${RESET} запусти скрипт от root"
        exit 1
    fi
}

get_public_ip() {
    curl -4 -s https://ifconfig.me || curl -4 -s https://ipinfo.io/ip || hostname -I | awk '{print $1}'
}

get_wan_if() {
    ip route get 8.8.8.8 | grep -oP '(?<=dev )\S+' | head -1 || true
}

get_current_port() {
    awk '/ListenPort/ {print $3; exit}' "${WG_CONF}"
}

get_server_privkey() {
    awk '/PrivateKey/ {print $3; exit}' "${WG_CONF}"
}

get_server_pubkey() {
    local priv
    priv=$(get_server_privkey)
    echo "$priv" | wg pubkey
}

get_dns_from_any_client() {
    ls /root/*.conf 2>/dev/null | head -n 1 | xargs -r grep -m1 "^DNS" 2>/dev/null | awk '{print $3}'
}

get_next_ip() {
    # ищем все AllowedIPs = 10.66.66.X/32, берём самый большой X и +1
    LAST_OCTET=$(grep -Eo "${SUBNET_PREFIX}\.[0-9]+/32" "${WG_CONF}" 2>/dev/null \
        | awk -F'[./]' '{print $4}' \
        | sort -n | tail -n1)

    if [[ -z "$LAST_OCTET" || "$LAST_OCTET" -lt 2 ]]; then
        echo "${FIRST_CLIENT_IP_V4}"
    else
        NEXT=$((LAST_OCTET + 1))
        echo "${SUBNET_PREFIX}.${NEXT}"
    fi
}

list_clients_pretty() {
    # печатаем клиентов из wg0.conf
    awk '
        /^\[Peer\]/ {peer=1; name=""; pk=""; ip=""; next}
        /^$/ {if(peer){printf "  name=%s  pubkey=%s  ip=%s\n",name,pk,ip}; peer=0; next}
        /^# / && peer {sub(/^# /,""); name=$0}
        /PublicKey/ && peer {pk=$3}
        /AllowedIPs/ && peer {ip=$3}
        END{if(peer){printf "  name=%s  pubkey=%s  ip=%s\n",name,pk,ip}}
    ' "${WG_CONF}"
}

restart_wg() {
    systemctl restart wg-quick@${WG_IF}
}

ufw_open_port() {
    local PORT="$1"
    ufw allow ${PORT}/udp >/dev/null
}

ufw_close_port() {
    local PORT="$1"
    ufw delete allow ${PORT}/udp >/dev/null 2>&1 || true
}

# =========================================================
# =============== INSTALL (first run only) ================
# =========================================================
install_wg() {
    header
    echo -e "${YELLOW}[*] Первый запуск: устанавливаем сервер WireGuard${RESET}\n"

    read -rp "Порт для WireGuard [51820]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-51820}

    read -rp "Имя первого клиента [client1]: " CLIENT_NAME
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

    echo ""
    echo "Настройка SSH-доступа:"
    echo "1) Разрешить SSH всем"
    echo "2) Разрешить SSH только с указанных IP (можно DNS-имена)"
    read -rp "Ваш выбор [1]: " SSH_CHOICE
    if [[ $SSH_CHOICE == 2 ]]; then
        read -rp "Введите IP/DNS через пробел: " SSH_IPS
    fi

    SERVER_PUBLIC_IP=$(get_public_ip)
    [ -z "$SERVER_PUBLIC_IP" ] && SERVER_PUBLIC_IP="YOUR_SERVER_IP"

    WAN_IF=$(get_wan_if)
    [ -z "$WAN_IF" ] && WAN_IF="eth0"

    echo -e "\n${YELLOW}[1/6] Установка пакетов...${RESET}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq wireguard wireguard-tools ufw qrencode curl resolvconf

    echo -e "${YELLOW}[2/6] Включаем IPv4 forwarding...${RESET}"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    echo -e "${YELLOW}[3/6] Генерация ключей...${RESET}"
    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
    CLIENT_PSK=$(wg genpsk)

    echo -e "${YELLOW}[4/6] Создание конфигов...${RESET}"
    mkdir -p "${WG_DIR}"
    chmod 700 "${WG_DIR}"

    # server config
    cat > "${WG_CONF}" <<EOF
[Interface]
Address = ${SERVER_IP_V4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
SaveConfig = true
PostUp = ufw route allow in on ${WG_IF} out on ${WAN_IF}
PostDown = ufw route delete allow in on ${WG_IF} out on ${WAN_IF}

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${FIRST_CLIENT_IP_V4}/32
EOF
    chmod 600 "${WG_CONF}"

    # client config
    cat > "/root/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${FIRST_CLIENT_IP_V4}/24
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    chmod 600 "/root/${CLIENT_NAME}.conf"

    echo -e "${YELLOW}[5/6] Настройка UFW...${RESET}"
    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing

    # WG порт
    ufw_open_port "${SERVER_PORT}"

    # SSH политика
    if [[ $SSH_CHOICE == 2 && -n "$SSH_IPS" ]]; then
        ufw delete allow ssh >/dev/null 2>&1 || true
        for ip in $SSH_IPS; do
            ufw allow from "$ip" to any port 22 proto tcp >/dev/null
        done
        echo "SSH разрешён только для: $SSH_IPS"
    else
        ufw allow ssh >/dev/null
        echo "SSH открыт для всех"
    fi

    ufw --force enable >/dev/null

    echo -e "${YELLOW}[6/6] Запуск WireGuard...${RESET}"
    systemctl enable --now wg-quick@${WG_IF} >/dev/null 2>&1

    echo -e "\n${GREEN}✅ Готово.${RESET}"
    echo -e "Серверный конфиг: ${CYAN}${WG_CONF}${RESET}"
    echo -e "Клиентский конфиг: ${CYAN}/root/${CLIENT_NAME}.conf${RESET}\n"
    echo -e "QR-код клиента ${YELLOW}${CLIENT_NAME}${RESET}:"
    qrencode -t ANSIUTF8 < "/root/${CLIENT_NAME}.conf"

    echo -e "\n${CYAN}──────────────────────────────────────────────${RESET}"
    echo -e "${YELLOW}Дальше для управления просто снова запусти этот же скрипт.${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────${RESET}\n"
}

# =========================================================
# ==================== MANAGER MENU =======================
# =========================================================
menu_add_client() {
    header
    echo -e "${YELLOW}Добавление нового клиента${RESET}\n"

    read -rp "Имя нового клиента: " NEW_CLIENT
    [ -z "$NEW_CLIENT" ] && { echo "Имя не может быть пустым"; read -rp "Enter... " _; return; }

    # вычисляем следующий IP
    CLIENT_IP=$(get_next_ip)

    # генерим ключи
    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)
    CLIENT_PSK=$(wg genpsk)

    SERVER_PUB_KEY=$(get_server_pubkey)
    SERVER_PORT=$(get_current_port)
    SERVER_PUBLIC_IP=$(get_public_ip)
    [ -z "$SERVER_PUBLIC_IP" ] && SERVER_PUBLIC_IP="YOUR_SERVER_IP"

    # берём DNS из любого существующего клиента
    DNS_CUR=$(get_dns_from_any_client)
    [ -z "$DNS_CUR" ] && DNS_CUR="77.88.8.8"

    # дописываем в серверный конфиг
    cat >> "${WG_CONF}" <<EOF

[Peer]
# ${NEW_CLIENT}
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP}/32
EOF

    # создаём клиентский конфиг
    cat > "/root/${NEW_CLIENT}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP}/24
DNS = ${DNS_CUR}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    chmod 600 "/root/${NEW_CLIENT}.conf"

    restart_wg

    echo -e "\n${GREEN}✅ Клиент ${NEW_CLIENT} добавлен (${CLIENT_IP}).${RESET}\n"
    echo -e "Файл: ${CYAN}/root/${NEW_CLIENT}.conf${RESET}\n"
    echo "QR:"
    qrencode -t ANSIUTF8 < "/root/${NEW_CLIENT}.conf"
    echo ""
    read -rp "Enter для меню... " _
}

menu_remove_client() {
    header
    echo -e "${YELLOW}Удаление клиента${RESET}\n"
    read -rp "Имя клиента для удаления: " DEL_CLIENT
    [ -z "$DEL_CLIENT" ] && { echo "Имя пустое"; read -rp "Enter... " _; return; }

    # выпиливаем блок [Peer] с этим именем
    sed -i "/# ${DEL_CLIENT}/,/^$/d" "${WG_CONF}"

    rm -f "/root/${DEL_CLIENT}.conf" 2>/dev/null || true

    restart_wg

    echo -e "\n${GREEN}✅ Клиент ${DEL_CLIENT} удалён.${RESET}\n"
    read -rp "Enter для меню... " _
}

menu_list_clients() {
    header
    echo -e "${YELLOW}Список клиентов:${RESET}\n"
    list_clients_pretty
    echo ""
    read -rp "Enter для меню... " _
}

menu_show_qr() {
    header
    echo -e "${YELLOW}Показать QR клиента${RESET}\n"
    read -rp "Имя клиента: " QR_CLIENT
    CONF_FILE="/root/${QR_CLIENT}.conf"
    if [[ ! -f "$CONF_FILE" ]]; then
        echo -e "${RED}Нет такого клиента или нет файла ${CONF_FILE}${RESET}"
    else
        echo ""
        qrencode -t ANSIUTF8 < "$CONF_FILE"
        echo ""
        echo -e "Файл конфига: ${CYAN}${CONF_FILE}${RESET}"
    fi
    echo ""
    read -rp "Enter для меню... " _
}

menu_change_port() {
    header
    CUR_PORT=$(get_current_port)
    echo -e "${YELLOW}Смена порта сервера (текущий ${CUR_PORT})${RESET}\n"
    read -rp "Новый порт: " NEW_PORT
    [ -z "$NEW_PORT" ] && { echo "Порт не задан"; read -rp "Enter... " _; return; }

    # обновляем порт в конфиге wg0.conf
    sed -i "s/^ListenPort.*/ListenPort = ${NEW_PORT}/" "${WG_CONF}"

    # UFW: закрыть старый и открыть новый
    ufw_close_port "${CUR_PORT}"
    ufw_open_port "${NEW_PORT}"
    ufw reload >/dev/null

    restart_wg

    echo -e "\n${GREEN}✅ Порт изменён на ${NEW_PORT}.${RESET}\n"
    read -rp "Enter для меню... " _
}

menu_change_dns() {
    header
    echo -e "${YELLOW}Смена DNS у всех клиентов${RESET}\n"
    echo "1) Yandex (77.88.8.8)"
    echo "2) Cloudflare (1.1.1.1)"
    echo "3) Google (8.8.8.8)"
    echo "4) Quad9 (9.9.9.9)"
    read -rp "Ваш выбор [1]: " DNS_CHOICE
    case $DNS_CHOICE in
      2) NEWDNS="1.1.1.1";;
      3) NEWDNS="8.8.8.8";;
      4) NEWDNS="9.9.9.9";;
      *) NEWDNS="77.88.8.8";;
    esac

    for f in /root/*.conf; do
        [ -f "$f" ] || continue
        sed -i "s/^DNS.*/DNS = ${NEWDNS}/" "$f"
    done

    echo -e "\n${GREEN}✅ DNS обновлён на ${NEWDNS} для всех клиентов.${RESET}\n"
    read -rp "Enter для меню... " _
}

menu_restart() {
    header
    echo -e "${YELLOW}Перезапуск WireGuard...${RESET}\n"
    restart_wg
    echo -e "${GREEN}✅ Готово.${RESET}\n"
    read -rp "Enter для меню... " _
}

main_menu() {
    while true; do
        header
        echo -e "${YELLOW}Меню управления:${RESET}"
        echo "1) Добавить клиента"
        echo "2) Удалить клиента"
        echo "3) Показать QR клиента"
        echo "4) Список клиентов"
        echo "5) Сменить порт сервера"
        echo "6) Сменить DNS у всех клиентов"
        echo "7) Перезапустить WireGuard"
        echo "0) Выйти"
        echo ""
        read -rp "Выбор: " CH
        case "$CH" in
            1) menu_add_client ;;
            2) menu_remove_client ;;
            3) menu_show_qr ;;
            4) menu_list_clients ;;
            5) menu_change_port ;;
            6) menu_change_dns ;;
            7) menu_restart ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

# ===== entrypoint =====
require_root
if [[ -f "${WG_CONF}" ]]; then
    # уже установлен -> режим менеджера
    main_menu
else
    # не установлен -> установка
    install_wg
fi
