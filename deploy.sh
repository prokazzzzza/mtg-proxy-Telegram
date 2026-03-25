#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  MTProto Proxy — One Command Deploy
#  Usage: 
#    wget https://raw.githubusercontent.com/prokazzzzza/mtg-proxy-Telegram/main/deploy.sh -O deploy.sh && bash deploy.sh
#  Tested on: Ubuntu 22.04 LTS, Debian 11+
# ═══════════════════════════════════════════════════════════════════

set -u

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║       MTProto Proxy — Quick Deploy           ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check root ──────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || err "Запустите с sudo"

# ── Detect OS ──────────────────────────────────────────────────
command -v apt-get >/dev/null || err "Только Debian/Ubuntu поддерживаются"
log "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1)"

# ── Detect IP ──────────────────────────────────────────────────
PROXY_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
PROXY_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
PROXY_IP=$(hostname -I | awk '{print $1}')

[[ "$PROXY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    warn "Не удалось определить IP"
    read -rp "Введите IP сервера: " PROXY_IP
}
log "IP сервера: ${PROXY_IP}"

# ── Install system deps ─────────────────────────────────────────
info "Установка системных зависимостей..."
for i in {1..30}; do
    if apt-get update -qq 2>/dev/null; then
        break
    fi
    warn "Ожидание освобождения lock ($i/30)..."
    sleep 2
done
apt-get install -y -qq wget ufw curl git 2>&1 | grep -v "^WARNING" || true
log "Системные зависимости установлены"

# ── Install mtg from release ───────────────────────────────────
MTG_VERSION="2.2.4"
MTG_URL="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-linux-amd64"

if ! command -v mtg >/dev/null 2>&1; then
    info "Скачивание mtg v${MTG_VERSION}..."
    
    if wget -q "${MTG_URL}" -O /usr/local/bin/mtg 2>/dev/null; then
        chmod +x /usr/local/bin/mtg
        log "mtg v${MTG_VERSION} скачан"
    else
        # Fallback: clone and build
        warn "Релиз не найден, компилируем из исходников..."
        info "Установка Go..."
        GO_VER="1.26.1"
        wget -q "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" -O /tmp/go.tar.gz || err "Не удалось скачать Go"
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        export GOPATH=/root/go
        mkdir -p $GOPATH/bin
        
        info "Компиляция mtg (может занять 2-3 минуты)..."
        cd /tmp && rm -rf mtg
        git clone --depth 1 https://github.com/9seconds/mtg.git || err "Не удалось клонировать"
        cd mtg
        
        # Найти main.go
        MTG_MAIN=$(find . -name "main.go" -type f 2>/dev/null | head -1)
        if [[ -n "$MTG_MAIN" ]]; then
            MTG_DIR=$(dirname "$MTG_MAIN")
            info "Найден main.go в: $MTG_DIR"
            go build -o /usr/local/bin/mtg "$MTG_DIR" || err "Ошибка компиляции"
        else
            # Попробуем стандартный путь
            go build -o /usr/local/bin/mtg . || err "Ошибка компиляции"
        fi
        
        cd / && rm -rf /tmp/mtg
        chmod +x /usr/local/bin/mtg
        log "mtg скомпилирован"
    fi
else
    log "mtg уже установлен"
fi

log "mtg $(mtg --version 2>/dev/null | head -1)"

# ── Generate secret ──────────────────────────────────────────────
info "Генерация секрета..."
PROXY_SECRET=$(/usr/local/bin/mtg generate-secret --hex ya.ru) || err "Ошибка генерации"
[[ "$PROXY_SECRET" =~ ^ee[0-9a-f]{40,}$ ]] || err "Неверный формат секрета"
log "Секрет сгенерирован"

# ── Create systemd service ──────────────────────────────────────
info "Создание systemd сервиса..."
cat > /etc/systemd/system/mtg-proxy.service << SVCEOF
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
SVCEOF
log "Systemd сервис создан"

# ── Firewall ─────────────────────────────────────────────────────
info "Настройка firewall..."
ufw --force enable 2>/dev/null || true
ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
ufw allow 443/tcp comment 'MTProto' 2>/dev/null || true
log "Firewall: порты 22, 443 открыты"

# ── Start service ───────────────────────────────────────────────
info "Запуск MTProto Proxy..."
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now mtg-proxy 2>&1 || warn "Не удалось запустить"

sleep 2
systemctl is-active mtg-proxy >/dev/null 2>&1 && log "MTProto Proxy запущен" || warn "Проверьте: journalctl -u mtg-proxy -n 50"

# ── Output ───────────────────────────────────────────────────────
TG_LINK="tg://proxy?server=${PROXY_IP}&port=443&secret=${PROXY_SECRET}"
HTTPS_LINK="https://t.me/proxy?server=${PROXY_IP}&port=443&secret=${PROXY_SECRET}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              ✅ УСТАНОВКА ЗАВЕРШЕНА!                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  📡 Ссылка для Telegram:                                ║"
echo "║                                                          ║"
echo "║  ${TG_LINK}"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Управление:"
echo "   systemctl status mtg-proxy"
echo "   systemctl restart mtg-proxy"
echo "   journalctl -u mtg-proxy -f"
echo ""
