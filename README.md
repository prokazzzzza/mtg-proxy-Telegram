# MTProto Proxy

![Shell](https://img.shields.io/badge/Shell-Bash-green)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

⚡ Быстрый MTProto прокси для Telegram — развёртывание **одной командой** на любом VPS.

## 🚀 Быстрый старт

```bash
curl -s https://raw.githubusercontent.com/prokazzzzza/mtg-proxy-Telegram/main/deploy.sh | bash
```

После выполнения вы получите готовую ссылку для добавления прокси в Telegram.

### Что делает скрипт

1. ✅ Устанавливает Go (если не установлен)
2. ✅ Компилирует и устанавливает [mtg](https://github.com/9seconds/mtg) v2
3. ✅ Генерирует секрет с маскировкой под `ya.ru` (Fake TLS)
4. ✅ Настраивает systemd-сервис
5. ✅ Открывает порты 22 и 443 в firewall
6. ✅ Запускает MTProto Proxy
7. ✅ Выводит готовую ссылку в терминал

## 📋 Требования

| Компонент | Минимум |
|-----------|---------|
| OS | Ubuntu 22.04 LTS / Debian 11+ |
| Права | root (sudo) |
| Порты | 22 (SSH), 443 (MTProto) |
| RAM | 512 MB |
| Диск | 1 GB |

## 📖 Использование

### Добавление прокси в Telegram

1. Откройте Telegram
2. Перейдите в **Настройки** → **Данные и память** → **Прокси**
3. Нажмите **Добавить прокси**
4. Выберите **Ссылка (URL)**
5. Вставьте полученную ссылку

### Управление сервисом

```bash
sudo systemctl status mtg-proxy   # статус
sudo systemctl restart mtg-proxy # перезапуск
sudo journalctl -u mtg-proxy -f   # логи
```

## 🏗️ Архитектура

```mermaid
graph LR
    A[Telegram] -->|MTProto| B[Порт 443]
    B --> C[mrg]
    C -->|Fake TLS| D[ya.ru]
```

## 📝 License

MIT
