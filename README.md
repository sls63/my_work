# Система автоматизации установки WordPress + ZennoPoster + Cloudflare + Grafana

Комплексная система автоматизации для развертывания полного стека веб-приложений с мониторингом и защитой.

## Компоненты системы

### 1. WordPress
- Автоматическая установка последней версии WordPress
- Настройка базы данных MySQL/MariaDB
- Конфигурация PHP и веб-сервера (Nginx/Apache)
- SSL-сертификаты через Let's Encrypt

### 2. ZennoPoster
- Установка и настройка ZennoPoster для автоматизации
- Конфигурация прокси и профилей
- Интеграция с WordPress

### 3. Cloudflare
- Автоматическая настройка DNS
- Конфигурация CDN и кеширования
- Настройка правил безопасности
- SSL/TLS оптимизация

### 4. Grafana + Prometheus
- Мониторинг системных ресурсов
- Мониторинг веб-приложений
- Дашборды для WordPress и ZennoPoster
- Алерты и уведомления

## Структура проекта

```
automation-system/
├── scripts/
│   ├── install-wordpress.sh
│   ├── install-zennoposter.sh
│   ├── setup-cloudflare.sh
│   ├── install-monitoring.sh
│   └── main-installer.sh
├── config/
│   ├── nginx/
│   ├── wordpress/
│   ├── grafana/
│   └── prometheus/
├── docker/
│   └── docker-compose.yml
├── ansible/
│   ├── playbook.yml
│   └── inventory/
└── terraform/
    ├── main.tf
    └── variables.tf
```

## Быстрый старт

1. Клонируйте репозиторий
2. Настройте переменные окружения в `.env`
3. Запустите главный установщик: `./scripts/main-installer.sh`

## Требования

- Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- Docker и Docker Compose
- Минимум 4GB RAM и 20GB диска
- Доменное имя для настройки Cloudflare

## Конфигурация

Все настройки находятся в файле `.env.example`. Скопируйте его в `.env` и настройте под ваши нужды.