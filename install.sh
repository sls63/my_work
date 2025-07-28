#!/bin/bash

# Главный установочный скрипт системы автоматизации
# WordPress + Cloudflare + Grafana с системой автоматизации контента

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII арт логотип
show_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
 ██████╗ ██╗   ██╗████████╗ ██████╗ ███╗   ███╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
██╔═══██╗██║   ██║╚══██╔══╝██╔═══██╗████╗ ████║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██║   ██║██║   ██║   ██║   ██║   ██║██╔████╔██║███████║   ██║   ██║██║   ██║██╔██╗ ██║
██║   ██║██║   ██║   ██║   ██║   ██║██║╚██╔╝██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
╚██████╔╝╚██████╔╝   ██║   ╚██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
 ╚═════╝  ╚═════╝    ╚═╝    ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

    WordPress + Cloudflare + Grafana + Content Automation System
    Полная система автоматизации для современного веб-стека
EOF
    echo -e "${NC}"
}

# Функции для вывода
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Проверка окружения
check_environment() {
    print_step "Проверка системных требований..."
    
    # Проверка ОС
    if [[ ! -f /etc/os-release ]]; then
        print_error "Неподдерживаемая операционная система"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        print_warning "Система тестировалась на Ubuntu/Debian. Возможны проблемы."
    fi
    
    # Проверка прав root
    if [[ $EUID -ne 0 ]]; then
        print_error "Скрипт должен запускаться с правами root. Используйте: sudo $0"
        exit 1
    fi
    
    # Проверка ресурсов
    total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $total_ram -lt 2000000 ]]; then
        print_warning "Рекомендуется минимум 2GB RAM"
    fi
    
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10000000 ]]; then
        print_warning "Рекомендуется минимум 10GB свободного места"
    fi
    
    print_success "Системные требования проверены"
}

# Проверка конфигурации
check_configuration() {
    print_step "Проверка конфигурации..."
    
    if [[ ! -f .env ]]; then
        print_warning "Файл .env не найден. Создание из шаблона..."
        cp .env.example .env
        print_info "Файл .env создан. Пожалуйста, отредактируйте его и запустите скрипт снова."
        print_info "Основные настройки для изменения:"
        print_info "- DOMAIN_NAME (ваш домен)"
        print_info "- CLOUDFLARE_API_TOKEN и CLOUDFLARE_ZONE_ID"
        print_info "- Пароли для баз данных и администраторов"
        exit 1
    fi
    
    # Проверка критических переменных
    source .env
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        print_error "DOMAIN_NAME не задан в .env файле"
        exit 1
    fi
    
    if [[ "${DOMAIN_NAME}" == "example.com" ]]; then
        print_warning "Используется домен по умолчанию. Рекомендуется изменить DOMAIN_NAME в .env"
    fi
    
    print_success "Конфигурация проверена"
}

# Показ меню выбора
show_menu() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     ВЫБЕРИТЕ МЕТОД УСТАНОВКИ                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  1) Полная автоматическая установка (рекомендуется)         ║"
    echo "║     • Все компоненты на одном сервере                       ║"
    echo "║     • Автоматическая настройка                              ║"
    echo "║     • Готово к использованию                                 ║"
    echo "║                                                              ║"
    echo "║  2) Docker Compose установка                                 ║"
    echo "║     • Контейнеризованное развертывание                      ║"
    echo "║     • Легкое масштабирование                                 ║"
    echo "║     • Изолированные сервисы                                  ║"
    echo "║                                                              ║"
    echo "║  3) Ansible развертывание                                    ║"
    echo "║     • Для множественных серверов                            ║"
    echo "║     • Инфраструктура как код                                 ║"
    echo "║     • Автоматизация конфигурации                            ║"
    echo "║                                                              ║"
    echo "║  4) Ручная установка по компонентам                          ║"
    echo "║     • Пошаговая установка                                   ║"
    echo "║     • Полный контроль процесса                              ║"
    echo "║     • Настройка под специфические нужды                     ║"
    echo "║                                                              ║"
    echo "║  5) Показать информацию о системе                            ║"
    echo "║  q) Выход                                                    ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Информация о системе
show_system_info() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                        ИНФОРМАЦИЯ О СИСТЕМЕ                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${YELLOW}Компоненты системы:${NC}"
    echo "• WordPress - CMS с оптимизацией производительности"
    echo "• Nginx - веб-сервер с SSL/TLS"
    echo "• MySQL 8.0 - база данных"
    echo "• Redis - кеширование и очереди задач"
    echo "• PHP 8.1 - с оптимизацией"
    echo "• Система автоматизации контента (FastAPI + Celery)"
    echo "• Cloudflare - CDN, безопасность, оптимизация"
    echo "• Prometheus + Grafana - мониторинг"
    echo "• Автоматические резервные копии"
    echo ""
    
    echo -e "${YELLOW}Возможности автоматизации:${NC}"
    echo "• API для создания и управления контентом"
    echo "• Автоматическая SEO-оптимизация"
    echo "• Планировщик задач для регулярных операций"
    echo "• Интеграция с внешними сервисами"
    echo "• WordPress плагин для управления"
    echo ""
    
    echo -e "${YELLOW}Мониторинг и аналитика:${NC}"
    echo "• Системные метрики (CPU, RAM, диск, сеть)"
    echo "• Метрики веб-сервера и базы данных"
    echo "• Мониторинг WordPress и автоматизации"
    echo "• Дашборды в Grafana"
    echo "• Системы алертов"
    echo ""
    
    echo -e "${YELLOW}Безопасность:${NC}"
    echo "• SSL/TLS сертификаты (Let's Encrypt)"
    echo "• Cloudflare защита от DDoS"
    echo "• Firewall (UFW) и Fail2Ban"
    echo "• Автоматические обновления безопасности"
    echo "• Защита WordPress от атак"
    echo ""
    
    echo -e "${YELLOW}Требования к системе:${NC}"
    echo "• Ubuntu 20.04+ / Debian 11+"
    echo "• Минимум 2GB RAM (рекомендуется 4GB+)"
    echo "• Минимум 10GB диска (рекомендуется 20GB+)"
    echo "• Доменное имя с доступом к DNS"
    echo "• Учетная запись Cloudflare (опционально)"
    echo ""
}

# Полная автоматическая установка
full_installation() {
    print_step "Запуск полной автоматической установки..."
    
    print_info "Этот процесс займет 15-30 минут в зависимости от скорости интернета"
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Запуск главного установщика
    bash scripts/main-installer.sh
    
    print_success "Полная установка завершена!"
    show_post_install_info
}

# Docker Compose установка
docker_installation() {
    print_step "Запуск Docker Compose установки..."
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        print_info "Установка Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm get-docker.sh
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_info "Установка Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    cd docker
    print_info "Запуск контейнеров..."
    docker-compose up -d
    
    print_success "Docker Compose установка завершена!"
    print_info "Контейнеры запущены. Проверьте статус: docker-compose ps"
}

# Ansible развертывание
ansible_installation() {
    print_step "Подготовка Ansible развертывания..."
    
    # Установка Ansible если не установлен
    if ! command -v ansible &> /dev/null; then
        print_info "Установка Ansible..."
        apt-get update
        apt-get install -y ansible
    fi
    
    cd ansible
    
    print_info "Проверьте и отредактируйте файл inventory/hosts"
    print_info "Затем запустите:"
    print_info "ansible-playbook -i inventory/hosts playbook.yml"
    
    read -p "Запустить Ansible playbook сейчас? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ansible-playbook -i inventory/hosts playbook.yml
        print_success "Ansible развертывание завершено!"
    fi
}

# Ручная установка
manual_installation() {
    print_step "Ручная установка по компонентам..."
    
    echo "Доступные компоненты для установки:"
    echo "1) WordPress (LEMP стек)"
    echo "2) Система мониторинга (Prometheus + Grafana)"
    echo "3) Автоматизация контента"
    echo "4) Настройка Cloudflare"
    echo "5) Все компоненты поочередно"
    echo ""
    
    read -p "Выберите компонент (1-5): " component
    
    case $component in
        1)
            bash scripts/install-wordpress.sh
            ;;
        2)
            bash scripts/install-monitoring.sh
            ;;
        3)
            bash scripts/setup-automation.sh
            ;;
        4)
            bash scripts/setup-cloudflare.sh
            ;;
        5)
            bash scripts/install-wordpress.sh
            bash scripts/install-monitoring.sh
            bash scripts/setup-automation.sh
            bash scripts/setup-cloudflare.sh
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
}

# Информация после установки
show_post_install_info() {
    source .env
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    УСТАНОВКА ЗАВЕРШЕНА!                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${YELLOW}Доступные сервисы:${NC}"
    echo "• WordPress: https://${DOMAIN_NAME}"
    echo "• WordPress Admin: https://${DOMAIN_NAME}/wp-admin"
    echo "• Grafana: https://${DOMAIN_NAME}:${GRAFANA_PORT}"
    echo "• Prometheus: https://${DOMAIN_NAME}:${PROMETHEUS_PORT}"
    echo "• API автоматизации: http://$(hostname -I | awk '{print $1}'):8000"
    echo "• Документация API: http://$(hostname -I | awk '{print $1}'):8000/docs"
    echo ""
    
    echo -e "${YELLOW}Учетные данные:${NC}"
    echo "• WordPress пользователь: ${WP_ADMIN_USER}"
    echo "• WordPress пароль: ${WP_ADMIN_PASSWORD}"
    echo "• Grafana пользователь: admin"
    echo "• Grafana пароль: ${GRAFANA_ADMIN_PASSWORD}"
    echo ""
    
    echo -e "${YELLOW}Полезные команды:${NC}"
    echo "• Статус сервисов: systemctl status nginx mysql redis-server"
    echo "• Логи автоматизации: journalctl -u automation-api -f"
    echo "• Мониторинг очереди: redis-cli monitor"
    echo "• Проверка SSL: openssl s_client -connect ${DOMAIN_NAME}:443"
    echo ""
    
    echo -e "${YELLOW}Следующие шаги:${NC}"
    echo "1. Проверьте доступность сайта: https://${DOMAIN_NAME}"
    echo "2. Войдите в WordPress админку и настройте сайт"
    echo "3. Настройте дашборды в Grafana"
    echo "4. Протестируйте API автоматизации"
    echo "5. Настройте регулярные резервные копии"
    echo ""
    
    if [[ "${CLOUDFLARE_API_TOKEN:-}" != "your_cloudflare_api_token" ]]; then
        echo -e "${YELLOW}Cloudflare:${NC}"
        echo "• Проверьте DNS настройки в панели Cloudflare"
        echo "• Убедитесь что домен проксируется через Cloudflare"
        echo "• Настройте дополнительные правила безопасности"
        echo ""
    fi
}

# Главная функция
main() {
    show_banner
    
    check_environment
    check_configuration
    
    while true; do
        show_menu
        read -p "Выберите опцию: " choice
        
        case $choice in
            1)
                full_installation
                break
                ;;
            2)
                docker_installation
                break
                ;;
            3)
                ansible_installation
                break
                ;;
            4)
                manual_installation
                ;;
            5)
                show_system_info
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            q|Q)
                print_info "До свидания!"
                exit 0
                ;;
            *)
                print_error "Неверный выбор. Попробуйте снова."
                ;;
        esac
    done
}

# Обработка сигналов
trap 'print_error "Установка прервана пользователем"; exit 1' INT TERM

# Запуск
main "$@"