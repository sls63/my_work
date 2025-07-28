#!/bin/bash

# Главный скрипт автоматизации установки WordPress + ZennoPoster + Cloudflare + Grafana
# Автор: Automation System
# Версия: 1.0

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
LOG_FILE="/var/log/automation-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Функции для вывода
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root"
        exit 1
    fi
}

# Загрузка переменных окружения
load_env() {
    if [[ ! -f ".env" ]]; then
        print_error "Файл .env не найден. Скопируйте .env.example в .env и настройте"
        exit 1
    fi
    source .env
    print_success "Переменные окружения загружены"
}

# Проверка системы
check_system() {
    print_info "Проверка системных требований..."
    
    # Проверка ОС
    if [[ ! -f /etc/os-release ]]; then
        print_error "Неподдерживаемая операционная система"
        exit 1
    fi
    
    # Проверка RAM
    total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $total_ram -lt 4000000 ]]; then
        print_warning "Рекомендуется минимум 4GB RAM"
    fi
    
    # Проверка диска
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 20000000 ]]; then
        print_warning "Рекомендуется минимум 20GB свободного места"
    fi
    
    print_success "Системные требования проверены"
}

# Установка базовых зависимостей
install_dependencies() {
    print_info "Установка базовых зависимостей..."
    
    # Обновление системы
    apt-get update -y
    apt-get upgrade -y
    
    # Установка необходимых пакетов
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        jq \
        htop \
        ufw \
        fail2ban
    
    print_success "Базовые зависимости установлены"
}

# Установка Docker
install_docker() {
    print_info "Установка Docker..."
    
    if command -v docker &> /dev/null; then
        print_warning "Docker уже установлен"
        return
    fi
    
    # Добавление официального GPG ключа Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Добавление репозитория Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Установка Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Запуск Docker
    systemctl enable docker
    systemctl start docker
    
    # Установка Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker установлен"
}

# Настройка безопасности
setup_security() {
    print_info "Настройка безопасности..."
    
    if [[ "${UFW_ENABLE}" == "true" ]]; then
        # Настройка UFW
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow "${SSH_PORT}/tcp"
        ufw allow "${NGINX_HTTP_PORT}/tcp"
        ufw allow "${NGINX_HTTPS_PORT}/tcp"
        ufw allow "${GRAFANA_PORT}/tcp"
        ufw --force enable
        print_success "UFW настроен"
    fi
    
    if [[ "${FAIL2BAN_ENABLE}" == "true" ]]; then
        # Настройка Fail2Ban
        systemctl enable fail2ban
        systemctl start fail2ban
        print_success "Fail2Ban включен"
    fi
}

# Основная функция установки
main() {
    print_info "=== Запуск системы автоматизации установки ==="
    print_info "Компоненты: WordPress + ZennoPoster + Cloudflare + Grafana"
    
    check_root
    load_env
    check_system
    install_dependencies
    install_docker
    setup_security
    
    # Запуск установочных скриптов
    print_info "Запуск установки WordPress..."
    bash "$(dirname "$0")/install-wordpress.sh"
    
    print_info "Запуск установки мониторинга..."
    bash "$(dirname "$0")/install-monitoring.sh"
    
    print_info "Настройка Cloudflare..."
    bash "$(dirname "$0")/setup-cloudflare.sh"
    
    print_info "Установка ZennoPoster..."
    bash "$(dirname "$0")/install-zennoposter.sh"
    
    print_success "=== Установка завершена успешно! ==="
    print_info "Доступные сервисы:"
    print_info "- WordPress: https://${DOMAIN_NAME}"
    print_info "- Grafana: https://${DOMAIN_NAME}:${GRAFANA_PORT}"
    print_info "- Prometheus: https://${DOMAIN_NAME}:${PROMETHEUS_PORT}"
    print_info ""
    print_info "Логи установки: ${LOG_FILE}"
}

# Обработка сигналов
trap 'print_error "Установка прервана"; exit 1' INT TERM

# Запуск
main "$@"