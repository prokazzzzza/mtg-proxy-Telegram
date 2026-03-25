#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  MTProto Proxy — One Command Deploy
#  Usage: curl -s https://raw.githubusercontent.com/prokazzzzza/mtg-proxy-simple/main/deploy.sh | bash
#  Tested on: Ubuntu 22.04 LTS, Debian 11+
# ═══════════════════════════════════════════════════════════════════

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║       MTProto Proxy — Quick Deploy           ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check root ──────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Запустите с sudo${NC}"
   exit 1
fi

# ── Detect OS ──────────────────────────────────────────────────
if ! command -v apt-get &>/dev/null; then
    echo -e "${RED}❌ Только Debian/Ubuntu поддерживаются${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1)"

# ── Detect IP ──────────────────────────────────────────────────
PROXY_IP=$(curl -s https://api.ipify.org 2>/dev/null || \
            curl -s https://ifconfig.me 2>/dev/null || \
            hostname -I | awk '{print $1}')
if [[ ! "$PROXY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${YELLOW}⚠️  Не удалось определить IP автоматически${NC}"
    read -rp "Введите IP сервера: " PROXY_IP
fi
echo -e "${GREEN}✓${NC} IP сервера: ${PROXY_IP}"

# ── Install system deps ─────────────────────────────────────────
echo "📦 Установка системных зависимостей..."
apt-get update -qq
apt-get install -y -qq wget ufw curl git >/dev/null 2>&1
echo -e "${GREEN}✓${NC} Системные зависимости установлены"

# ── Install Go ──────────────────────────────────────────────────
GO_VER="1.22.5"
GO_INSTALLED=false
if command -v go &>/dev/null; then
    CURRENT_GO=$(go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+' | head -1)
    if [[ $(echo -e "$CURRENT_GO\n1.22" | sort -V | head -1) == "1.22" ]]; then
        GO_INSTALLED=true
    fi
fi

if [[ "$GO_INSTALLED" == "false" ]]; then
    echo "📦 Установка Go ${GO_VER}..."
    wget -q "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/golang.sh
    rm /tmp/go.tar.gz
fi
export PATH=$PATH:/usr/local/go/bin
echo -e "${GREEN}✓${NC} Go $(go version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# ── Install mtg ──────────────────────────────────────────────────
if ! command -v mtg &>/dev/null; then
    echo "📦 Компиляция mtg из исходников (это может занять 2-3 минуты)..."
    
    # Создаём директорию для GOPATH
    mkdir -p /root/go/bin
    
    # Компилируем mtg с выводом прогресса
    echo "   -> Скачивание и компиляция..."
    GOPATH=/root/go go install github.com/9seconds/mtg/v2/cmd/mtg@latest 2>&1
    
    # Проверяем результат
    if [[ -f /root/go/bin/mtg ]]; then
        cp /root/go/bin/mtg /usr/local/bin/mtg
        chmod +x /usr/local/bin/mtg
        echo -e "${GREEN}✓${NC} mtg успешно скомпилирован"
    else
        echo -e "${RED}❌ Ошибка компиляции mtg${NC}"
        echo "Попробуйте вручную: GOPATH=/root/go go install github.com/9seconds/mtg/v2/cmd/mtg@latest"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} mtg уже установлен"
fi

MTG_VER=$(mtg --version 2>/dev/null | head -1 || echo "installed")
echo -e "${GREEN}✓${NC} mtg ${MTG_VER}"

# ── Generate secret ──────────────────────────────────────────────
echo "🔑 Генерация секрета MTProto..."
PROXY_SECRET=$(/usr/local/bin/mtg generate-secret --hex ya.ru)
if [[ ! "$PROXY_SECRET" =~ ^ee[0-9a-f]{40,}$ ]]; then
    echo -e "${RED}❌ Ошибка генерации секрета${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Секрет сгенерирован"

# ── Create systemd service ──────────────────────────────────────
echo "⚙️  Настройка systemd сервиса..."
cat > /etc/systemd/system/mtg-proxy.service << EOF
[Unit]
Description=MTProto Proxy for Telegram
Documentation=https://github.com/9seconds/mtg
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/mtg simple-run 0.0.0.0:443 ${PROXY_SECRET} -n 1.1.1.1 -t 30s -a 512kib -p 443 -i prefer-ipv4
Restart=always
RestartSec=3
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓${NC} Systemd сервис создан"

# ── Firewall ─────────────────────────────────────────────────────
echo "🔒 Настройка firewall..."
ufw --force enable >/dev/null 2>&1
ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1
ufw allow 443/tcp comment 'MTProto' >/dev/null 2>&1
echo -e "${GREEN}✓${NC} Firewall: порты 22, 443 открыты"

# ── Start service ───────────────────────────────────────────────
echo "🚀 Запуск MTProto Proxy..."
systemctl daemon-reload
systemctl enable --now mtg-proxy 2>&1

sleep 2
if systemctl is-active mtg-proxy; then
    echo -e "${GREEN}✓${NC} MTProto Proxy запущен и работает"
else
    echo -e "${YELLOW}⚠️  Сервис создан, но неактивен. Проверьте: journalctl -u mtg-proxy -n 50${NC}"
fi

# ── Output ───────────────────────────────────────────────────────
TG_LINK="tg://proxy?server=${PROXY_IP}&port=443&secret=${PROXY_SECRET}"
HTTPS_LINK="https://t.me/proxy?server=${PROXY_IP}&port=443&secret=${PROXY_SECRET}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              ✅ УСТАНОВКА ЗАВЕРШЕНА!                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  📡 Ссылка для Telegram (скопируйте):                    ║"
echo "║                                                          ║"
echo -e "║  ${TG_LINK}"
echo "║                                                          ║"
echo "║  🔗 HTTPS версия (для браузера):                          ║"
echo -e "║  ${HTTPS_LINK}"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Команды управления:"
echo "   sudo systemctl status mtg-proxy   — статус"
echo "   sudo systemctl restart mtg-proxy — перезапуск"
echo "   sudo journalctl -u mtg-proxy -f  — логи"
echo ""
