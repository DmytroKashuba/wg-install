# ⚙️ WireGuard Manager v9.0 (UFW Edition)

### Overview
A complete **interactive WireGuard management script** for Ubuntu 22.04–24.10.  
Built for simplicity, security, and automation — using **UFW firewall** instead of raw iptables.

The script installs and manages a WireGuard VPN server with:
- 🧩 Interactive menu
- 🔐 SSH access control (whitelist by IP or DNS)
- 🌐 DNS server selection (Yandex, Cloudflare, Google, Quad9)
- ⚙️ Dynamic port change (old port closed automatically)
- 🧠 Automatic IP allocation for new clients
- 🧾 Colorized terminal output
- 🧱 Fully automated UFW configuration

---

### 🧰 Requirements
- Ubuntu 22.04, 23.04, 24.04, or newer  
- Root privileges  
- Internet connection  

---

## 🚀 Installation

Run this command as **root**:

```bash
# Direct from GitHub
bash <(curl -Ls https://raw.githubusercontent.com/DmytroKashuba/wg-install/main/wg-install.sh)

# If GitHub raw access is slow or blocked, use the mirror
bash <(curl -Ls https://ghproxy.net/https://raw.githubusercontent.com/DmytroKashuba/wg-install/main/wg-install.sh)

