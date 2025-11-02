# ⚡ WireGuard Manager v10.0 (UFW Edition)

### Overview

A complete **interactive WireGuard management script** for Ubuntu 22.04–24.10.  
Built for simplicity, automation, and security — using **UFW firewall** instead of raw iptables.

This script installs and manages a full WireGuard VPN server with:

- 🧭 Interactive setup and menu  
- 🔐 SSH access control (allow all or whitelist by IP/DNS)  
- 🌐 DNS server selection (Yandex, Cloudflare, Google, Quad9)  
- 🔁 Dynamic port change (UFW auto-updates)  
- 🧩 Automatic IP allocation for new clients  
- 🧱 Fully automated UFW configuration  
- 🎨 Colored terminal output  
- 🧾 Built-in management menu (add/remove clients, change port/DNS, restart)

---

### 🧰 Requirements

- Ubuntu **22.04**, **23.04**, **24.04**, or newer  
- Root privileges (`sudo -i`)  
- Internet connection  

---

## 🚀 Installation

Run this command as **root**:

### 🟢 Direct from GitHub
```bash
bash <(curl -Ls https://raw.githubusercontent.com/DmytroKashuba/wg-install/main/wg-install.sh)
```

### 🟣 Mirror (if GitHub raw is slow or blocked)
```bash
bash <(curl -Ls https://ghproxy.net/https://raw.githubusercontent.com/DmytroKashuba/wg-install/main/wg-install.sh)
```

---

## ⚙️ Usage

After installation, just run the same script again:
```bash
bash wg-install.sh
```

You will get an **interactive menu**:
```
1) Add new client  
2) Remove client  
3) Show client QR  
4) List clients  
5) Change server port  
6) Change DNS for all clients  
7) Restart WireGuard  
0) Exit
```

---

## 🧩 Features in Detail

| Feature | Description |
|----------|--------------|
| 🧱 **UFW Firewall** | Automatically manages WireGuard and SSH rules |
| 🌐 **DNS Selector** | Choose from Yandex, Cloudflare, Google, or Quad9 |
| 🔐 **SSH Whitelist** | Allow SSH from specific IPs or DNS names |
| 🔁 **Port Manager** | Change port and auto-update UFW |
| 👥 **Client Manager** | Add/remove clients with auto IP assignment |
| 🧾 **Persistent Configs** | Stored in `/etc/wireguard` and `/root/*.conf` |
| 📱 **QR Output** | Display client configs as QR codes |

---

## 📂 Paths

| File | Description |
|------|--------------|
| `/etc/wireguard/wg0.conf` | Main server configuration |
| `/root/<client>.conf` | Individual client config |
| `/usr/bin/wg` | WireGuard CLI tool |

---

## ✅ Tested On

- Ubuntu Server 22.04 LTS  
- Ubuntu Server 24.04 LTS  
- VPS providers: Hetzner, Contabo, OVH, DigitalOcean  

---

## ⚠️ Notes

- Always run the script as **root**.  
- On first run — installs everything automatically.  
- On next runs — opens **interactive management menu**.

---

## 🧑‍💻 Author

**Dmytro Kashuba**  
📦 GitHub: [@DmytroKashuba](https://github.com/DmytroKashuba)  
🛠️ Project: [WireGuard Manager](https://github.com/DmytroKashuba/wg-install)

---

## 🪪 License

This project is licensed under the **MIT License**.  
You can freely use, modify, and distribute it.

---

> 💡 **Tip:** Use the mirror command if your server has slow or blocked access to `raw.githubusercontent.com`.
