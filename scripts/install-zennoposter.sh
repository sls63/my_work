#!/bin/bash

# Скрипт установки ZennoPoster
# Включает установку Wine, настройку ZennoPoster и интеграцию с WordPress

set -euo pipefail

# Импорт функций вывода
source "$(dirname "$0")/../.env"

print_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Установка Wine для запуска ZennoPoster
install_wine() {
    print_info "Установка Wine для запуска ZennoPoster..."
    
    # Добавление архитектуры i386
    dpkg --add-architecture i386
    
    # Добавление репозитория WineHQ
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | apt-key add -
    echo "deb https://dl.winehq.org/wine-builds/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/winehq.list
    
    # Обновление пакетов
    apt-get update -y
    
    # Установка Wine
    apt-get install -y --install-recommends winehq-stable
    
    # Установка дополнительных зависимостей
    apt-get install -y \
        winetricks \
        xvfb \
        fonts-wine \
        cabextract \
        p7zip-full \
        unzip
    
    print_success "Wine установлен"
}

# Настройка Wine окружения
setup_wine_environment() {
    print_info "Настройка Wine окружения..."
    
    # Создание пользователя для ZennoPoster
    useradd -m -s /bin/bash zennoposter || true
    
    # Настройка Wine от имени пользователя zennoposter
    sudo -u zennoposter bash -c '
        export DISPLAY=:99
        export WINEPREFIX=/home/zennoposter/.wine
        
        # Инициализация Wine
        wineboot --init
        
        # Настройка Wine (автоматический режим)
        winecfg /v win10
        
        # Установка необходимых компонентов
        winetricks -q corefonts vcrun2019 dotnet48
    '
    
    print_success "Wine окружение настроено"
}

# Создание виртуального дисплея
setup_virtual_display() {
    print_info "Настройка виртуального дисплея..."
    
    # Создание службы для Xvfb
    cat > /etc/systemd/system/xvfb.service << EOF
[Unit]
Description=X Virtual Framebuffer Service
After=network.target

[Service]
Type=simple
User=zennoposter
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable xvfb
    systemctl start xvfb
    
    print_success "Виртуальный дисплей настроен"
}

# Загрузка и установка ZennoPoster
install_zennoposter() {
    print_info "Загрузка и установка ZennoPoster..."
    
    # Создание директории для ZennoPoster
    mkdir -p /opt/zennoposter
    chown zennoposter:zennoposter /opt/zennoposter
    
    # Примечание: ZennoPoster - коммерческое ПО, требует лицензии
    # Здесь показан пример установки из загруженного файла
    
    cat > /opt/zennoposter/install.sh << 'EOF'
#!/bin/bash
# Скрипт установки ZennoPoster
# Замените на реальный путь к установочному файлу ZennoPoster

export DISPLAY=:99
export WINEPREFIX=/home/zennoposter/.wine

# Если у вас есть установочный файл ZennoPoster
if [ -f "/opt/zennoposter/ZennoPosterSetup.exe" ]; then
    wine /opt/zennoposter/ZennoPosterSetup.exe /S
else
    echo "Установочный файл ZennoPoster не найден"
    echo "Поместите ZennoPosterSetup.exe в /opt/zennoposter/"
    exit 1
fi
EOF

    chmod +x /opt/zennoposter/install.sh
    chown zennoposter:zennoposter /opt/zennoposter/install.sh
    
    print_warning "Поместите установочный файл ZennoPoster в /opt/zennoposter/ZennoPosterSetup.exe"
    print_warning "Затем запустите: sudo -u zennoposter /opt/zennoposter/install.sh"
    
    print_success "Скрипт установки ZennoPoster создан"
}

# Настройка ZennoPoster конфигурации
setup_zennoposter_config() {
    print_info "Настройка конфигурации ZennoPoster..."
    
    # Создание конфигурационного файла
    cat > /opt/zennoposter/config.json << EOF
{
    "license_key": "${ZENNOPOSTER_LICENSE_KEY}",
    "proxy_list": "${ZENNOPOSTER_PROXY_LIST}",
    "wordpress_integration": {
        "enabled": true,
        "wp_url": "https://${DOMAIN_NAME}",
        "wp_username": "${WP_ADMIN_USER}",
        "wp_password": "${WP_ADMIN_PASSWORD}",
        "wp_api_key": "auto-generated"
    },
    "automation_settings": {
        "max_threads": 5,
        "delay_between_actions": 2000,
        "timeout": 30000,
        "user_agent_rotation": true,
        "proxy_rotation": true
    },
    "monitoring": {
        "enabled": true,
        "metrics_endpoint": "http://localhost:9100/metrics",
        "log_level": "INFO"
    }
}
EOF

    chown zennoposter:zennoposter /opt/zennoposter/config.json
    
    print_success "Конфигурация ZennoPoster создана"
}

# Создание сервиса ZennoPoster
create_zennoposter_service() {
    print_info "Создание сервиса ZennoPoster..."
    
    cat > /etc/systemd/system/zennoposter.service << EOF
[Unit]
Description=ZennoPoster Automation Service
After=network.target xvfb.service mysql.service
Wants=xvfb.service

[Service]
Type=simple
User=zennoposter
Group=zennoposter
WorkingDirectory=/home/zennoposter/.wine/drive_c/Program Files (x86)/ZennoPoster Pro
Environment=DISPLAY=:99
Environment=WINEPREFIX=/home/zennoposter/.wine
ExecStart=/usr/bin/wine /home/zennoposter/.wine/drive_c/Program Files (x86)/ZennoPoster Pro/ZennoPoster.exe
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    print_success "Сервис ZennoPoster создан"
}

# Настройка интеграции с WordPress
setup_wordpress_integration() {
    print_info "Настройка интеграции ZennoPoster с WordPress..."
    
    # Создание WordPress плагина для интеграции с ZennoPoster
    mkdir -p /var/www/"${DOMAIN_NAME}"/wp-content/plugins/zennoposter-integration
    
    cat > /var/www/"${DOMAIN_NAME}"/wp-content/plugins/zennoposter-integration/zennoposter-integration.php << 'EOF'
<?php
/**
 * Plugin Name: ZennoPoster Integration
 * Description: Интеграция ZennoPoster с WordPress
 * Version: 1.0
 */

// Предотвращение прямого доступа
if (!defined('ABSPATH')) {
    exit;
}

class ZennoPosterIntegration {
    
    public function __construct() {
        add_action('init', array($this, 'init'));
        add_action('wp_ajax_zennoposter_webhook', array($this, 'handle_webhook'));
        add_action('wp_ajax_nopriv_zennoposter_webhook', array($this, 'handle_webhook'));
        add_action('admin_menu', array($this, 'add_admin_menu'));
    }
    
    public function init() {
        // Инициализация плагина
    }
    
    public function handle_webhook() {
        // Обработка webhook от ZennoPoster
        $data = json_decode(file_get_contents('php://input'), true);
        
        if (isset($data['action'])) {
            switch ($data['action']) {
                case 'create_post':
                    $this->create_post($data);
                    break;
                case 'update_post':
                    $this->update_post($data);
                    break;
                case 'status_update':
                    $this->log_status($data);
                    break;
            }
        }
        
        wp_die();
    }
    
    private function create_post($data) {
        $post_data = array(
            'post_title' => sanitize_text_field($data['title']),
            'post_content' => wp_kses_post($data['content']),
            'post_status' => 'draft',
            'post_author' => 1,
            'meta_input' => array(
                'zennoposter_source' => true,
                'zennoposter_task_id' => $data['task_id']
            )
        );
        
        $post_id = wp_insert_post($post_data);
        
        if ($post_id) {
            echo json_encode(array('success' => true, 'post_id' => $post_id));
        } else {
            echo json_encode(array('success' => false, 'error' => 'Failed to create post'));
        }
    }
    
    private function update_post($data) {
        $post_id = intval($data['post_id']);
        $post_data = array(
            'ID' => $post_id,
            'post_title' => sanitize_text_field($data['title']),
            'post_content' => wp_kses_post($data['content'])
        );
        
        $result = wp_update_post($post_data);
        
        if ($result) {
            echo json_encode(array('success' => true));
        } else {
            echo json_encode(array('success' => false, 'error' => 'Failed to update post'));
        }
    }
    
    private function log_status($data) {
        // Логирование статуса ZennoPoster
        error_log('ZennoPoster status: ' . json_encode($data));
    }
    
    public function add_admin_menu() {
        add_options_page(
            'ZennoPoster Integration',
            'ZennoPoster',
            'manage_options',
            'zennoposter-integration',
            array($this, 'admin_page')
        );
    }
    
    public function admin_page() {
        echo '<div class="wrap">';
        echo '<h1>ZennoPoster Integration</h1>';
        echo '<p>Настройки интеграции ZennoPoster с WordPress</p>';
        echo '<p>Webhook URL: ' . admin_url('admin-ajax.php?action=zennoposter_webhook') . '</p>';
        echo '</div>';
    }
}

new ZennoPosterIntegration();
EOF

    # Активация плагина
    cd /var/www/"${DOMAIN_NAME}"
    wp plugin activate zennoposter-integration --allow-root
    
    print_success "Интеграция с WordPress настроена"
}

# Настройка мониторинга ZennoPoster
setup_zennoposter_monitoring() {
    print_info "Настройка мониторинга ZennoPoster..."
    
    # Создание скрипта мониторинга
    cat > /usr/local/bin/zennoposter-monitor.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/zennoposter-monitor.log"
METRICS_FILE="/tmp/zennoposter_metrics.prom"

# Проверка работы ZennoPoster
if pgrep -f "ZennoPoster.exe" > /dev/null; then
    echo "zennoposter_status 1" > $METRICS_FILE
    echo "$(date): ZennoPoster is running" >> $LOG_FILE
else
    echo "zennoposter_status 0" > $METRICS_FILE
    echo "$(date): ZennoPoster is not running" >> $LOG_FILE
fi

# Подсчет активных процессов
PROCESS_COUNT=$(pgrep -f "ZennoPoster.exe" | wc -l)
echo "zennoposter_processes $PROCESS_COUNT" >> $METRICS_FILE

# Использование памяти
if pgrep -f "ZennoPoster.exe" > /dev/null; then
    MEMORY_USAGE=$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | grep ZennoPoster | head -1 | awk '{print $4}')
    echo "zennoposter_memory_percent $MEMORY_USAGE" >> $METRICS_FILE
fi

# Проверка лог файлов ZennoPoster
if [ -f "/home/zennoposter/.wine/drive_c/users/zennoposter/AppData/Local/ZennoPoster/Logs/log.txt" ]; then
    ERROR_COUNT=$(grep -c "ERROR" "/home/zennoposter/.wine/drive_c/users/zennoposter/AppData/Local/ZennoPoster/Logs/log.txt" || echo 0)
    echo "zennoposter_errors_total $ERROR_COUNT" >> $METRICS_FILE
fi
EOF

    chmod +x /usr/local/bin/zennoposter-monitor.sh
    
    # Добавление в cron
    (crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/zennoposter-monitor.sh") | crontab -
    
    print_success "Мониторинг ZennoPoster настроен"
}

# Создание скриптов управления
create_management_scripts() {
    print_info "Создание скриптов управления ZennoPoster..."
    
    # Скрипт запуска
    cat > /usr/local/bin/zennoposter-start.sh << 'EOF'
#!/bin/bash
systemctl start xvfb
sleep 5
systemctl start zennoposter
echo "ZennoPoster запущен"
EOF

    # Скрипт остановки
    cat > /usr/local/bin/zennoposter-stop.sh << 'EOF'
#!/bin/bash
systemctl stop zennoposter
systemctl stop xvfb
echo "ZennoPoster остановлен"
EOF

    # Скрипт перезапуска
    cat > /usr/local/bin/zennoposter-restart.sh << 'EOF'
#!/bin/bash
/usr/local/bin/zennoposter-stop.sh
sleep 5
/usr/local/bin/zennoposter-start.sh
echo "ZennoPoster перезапущен"
EOF

    # Скрипт статуса
    cat > /usr/local/bin/zennoposter-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус ZennoPoster ==="
systemctl status xvfb --no-pager
echo ""
systemctl status zennoposter --no-pager
echo ""
echo "Процессы:"
pgrep -f "ZennoPoster.exe" || echo "ZennoPoster не запущен"
EOF

    chmod +x /usr/local/bin/zennoposter-*.sh
    
    print_success "Скрипты управления созданы"
}

# Настройка системы прокси
setup_proxy_management() {
    print_info "Настройка системы управления прокси..."
    
    # Создание скрипта управления прокси
    cat > /opt/zennoposter/proxy-manager.py << 'EOF'
#!/usr/bin/env python3
import json
import requests
import random
import time
from typing import List, Dict

class ProxyManager:
    def __init__(self, config_file: str):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        self.proxy_list = self.parse_proxy_list()
        
    def parse_proxy_list(self) -> List[Dict]:
        proxies = []
        for proxy_string in self.config['proxy_list'].split(','):
            parts = proxy_string.strip().split(':')
            if len(parts) == 4:
                proxies.append({
                    'host': parts[0],
                    'port': parts[1],
                    'username': parts[2],
                    'password': parts[3],
                    'working': True,
                    'last_check': 0
                })
        return proxies
    
    def test_proxy(self, proxy: Dict) -> bool:
        try:
            proxy_url = f"http://{proxy['username']}:{proxy['password']}@{proxy['host']}:{proxy['port']}"
            proxies = {'http': proxy_url, 'https': proxy_url}
            response = requests.get('http://httpbin.org/ip', proxies=proxies, timeout=10)
            return response.status_code == 200
        except:
            return False
    
    def get_working_proxy(self) -> Dict:
        working_proxies = [p for p in self.proxy_list if p['working']]
        if working_proxies:
            return random.choice(working_proxies)
        return None
    
    def check_all_proxies(self):
        for proxy in self.proxy_list:
            proxy['working'] = self.test_proxy(proxy)
            proxy['last_check'] = time.time()
            print(f"Proxy {proxy['host']}:{proxy['port']} - {'OK' if proxy['working'] else 'FAILED'}")

if __name__ == "__main__":
    manager = ProxyManager('/opt/zennoposter/config.json')
    manager.check_all_proxies()
EOF

    chmod +x /opt/zennoposter/proxy-manager.py
    
    # Добавление проверки прокси в cron
    (crontab -l 2>/dev/null; echo "0 */6 * * * /usr/bin/python3 /opt/zennoposter/proxy-manager.py") | crontab -
    
    print_success "Система управления прокси настроена"
}

# Создание дашборда для Grafana
create_grafana_dashboard() {
    print_info "Создание дашборда Grafana для ZennoPoster..."
    
    cat > /opt/monitoring/grafana/dashboards/zennoposter-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "ZennoPoster Monitoring",
    "tags": ["zennoposter", "automation"],
    "timezone": "browser",
    "panels": [
      {
        "title": "ZennoPoster Status",
        "type": "stat",
        "targets": [
          {
            "expr": "zennoposter_status",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {"value": 0, "text": "Stopped"},
              {"value": 1, "text": "Running"}
            ],
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "green", "value": 1}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "zennoposter_memory_percent",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "title": "Error Count",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(zennoposter_errors_total[5m])",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF

    print_success "Дашборд Grafana создан"
}

# Основная функция
main() {
    print_info "=== Установка ZennoPoster ==="
    
    install_wine
    setup_wine_environment
    setup_virtual_display
    install_zennoposter
    setup_zennoposter_config
    create_zennoposter_service
    setup_wordpress_integration
    setup_zennoposter_monitoring
    create_management_scripts
    setup_proxy_management
    create_grafana_dashboard
    
    print_success "ZennoPoster установлен и настроен!"
    print_info "Команды управления:"
    print_info "- Запуск: /usr/local/bin/zennoposter-start.sh"
    print_info "- Остановка: /usr/local/bin/zennoposter-stop.sh"
    print_info "- Перезапуск: /usr/local/bin/zennoposter-restart.sh"
    print_info "- Статус: /usr/local/bin/zennoposter-status.sh"
    print_info ""
    print_warning "Не забудьте:"
    print_warning "1. Поместить установочный файл ZennoPoster в /opt/zennoposter/"
    print_warning "2. Настроить лицензионный ключ в .env"
    print_warning "3. Добавить список прокси в конфигурацию"
}

main "$@"