#!/bin/bash

# Скрипт установки системы мониторинга Grafana + Prometheus
# Включает настройку дашбордов для WordPress и системных метрик

set -euo pipefail

# Импорт функций вывода
source "$(dirname "$0")/../.env"

print_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Создание Docker Compose для мониторинга
create_monitoring_compose() {
    print_info "Создание Docker Compose для мониторинга..."
    
    mkdir -p /opt/monitoring/{prometheus,grafana,node-exporter}
    
    cat > /opt/monitoring/docker-compose.yml << EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/rules:/etc/prometheus/rules
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION}'
      - '--web.enable-lifecycle'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_DOMAIN=${DOMAIN_NAME}
      - GF_SMTP_ENABLED=true
      - GF_SMTP_HOST=localhost:587
      - GF_SMTP_FROM_ADDRESS=${ADMIN_EMAIL}
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

  nginx-exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: nginx-exporter
    restart: unless-stopped
    ports:
      - "9113:9113"
    command:
      - '-nginx.scrape-uri=http://nginx/nginx_status'
    networks:
      - monitoring

  mysql-exporter:
    image: prom/mysqld-exporter:latest
    container_name: mysql-exporter
    restart: unless-stopped
    ports:
      - "9104:9104"
    environment:
      - DATA_SOURCE_NAME=${WP_DB_USER}:${WP_DB_PASSWORD}@(localhost:3306)/${WP_DB_NAME}
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
EOF

    print_success "Docker Compose создан"
}

# Настройка Prometheus
configure_prometheus() {
    print_info "Настройка Prometheus..."
    
    cat > /opt/monitoring/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 30s

  - job_name: 'nginx-exporter'
    static_configs:
      - targets: ['nginx-exporter:9113']
    scrape_interval: 30s

  - job_name: 'mysql-exporter'
    static_configs:
      - targets: ['mysql-exporter:9104']
    scrape_interval: 30s

  - job_name: 'wordpress'
    static_configs:
      - targets: ['${DOMAIN_NAME}:80', '${DOMAIN_NAME}:443']
    scrape_interval: 60s
    metrics_path: /wp-admin/admin-ajax.php
    params:
      action: ['prometheus_metrics']

  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://${DOMAIN_NAME}
        - https://${DOMAIN_NAME}/wp-admin
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
EOF

    # Создание правил алертов
    mkdir -p /opt/monitoring/prometheus/rules
    cat > /opt/monitoring/prometheus/rules/alerts.yml << EOF
groups:
  - name: wordpress_alerts
    rules:
      - alert: WordPressDown
        expr: up{job="wordpress"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "WordPress сайт недоступен"
          description: "WordPress сайт {{ \$labels.instance }} недоступен более 2 минут"

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокая загрузка CPU"
          description: "CPU загрузка на {{ \$labels.instance }} превышает 80% в течение 5 минут"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое использование памяти"
          description: "Использование памяти на {{ \$labels.instance }} превышает 85%"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Мало свободного места на диске"
          description: "Свободного места на диске {{ \$labels.instance }} менее 15%"

      - alert: MySQLDown
        expr: mysql_up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "MySQL сервер недоступен"
          description: "MySQL сервер на {{ \$labels.instance }} недоступен"
EOF

    print_success "Prometheus настроен"
}

# Настройка Grafana
configure_grafana() {
    print_info "Настройка Grafana..."
    
    # Создание директорий для provisioning
    mkdir -p /opt/monitoring/grafana/{provisioning/datasources,provisioning/dashboards,dashboards}
    
    # Настройка источников данных
    cat > /opt/monitoring/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Настройка дашбордов
    cat > /opt/monitoring/grafana/provisioning/dashboards/dashboard.yml << EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Создание дашборда для системных метрик
    cat > /opt/monitoring/grafana/dashboards/system-metrics.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "System Metrics",
    "tags": ["system"],
    "timezone": "browser",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
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
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100",
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
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF

    print_success "Grafana настроен"
}

# Настройка Nginx для мониторинга
configure_nginx_monitoring() {
    print_info "Настройка мониторинга Nginx..."
    
    # Добавление страницы статуса Nginx
    cat > /etc/nginx/sites-available/monitoring << EOF
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow ::1;
        deny all;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/monitoring /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    print_success "Мониторинг Nginx настроен"
}

# Установка WordPress плагина для метрик
install_wp_metrics_plugin() {
    print_info "Установка плагина метрик для WordPress..."
    
    cd /var/www/"${DOMAIN_NAME}"
    
    # Создание простого плагина для экспорта метрик
    mkdir -p wp-content/plugins/wp-prometheus
    cat > wp-content/plugins/wp-prometheus/wp-prometheus.php << 'EOF'
<?php
/**
 * Plugin Name: WordPress Prometheus Metrics
 * Description: Экспорт метрик WordPress для Prometheus
 * Version: 1.0
 */

add_action('wp_ajax_prometheus_metrics', 'wp_prometheus_metrics');
add_action('wp_ajax_nopriv_prometheus_metrics', 'wp_prometheus_metrics');

function wp_prometheus_metrics() {
    global $wpdb;
    
    header('Content-Type: text/plain');
    
    // Количество постов
    $posts_count = wp_count_posts();
    echo "wordpress_posts_total{status=\"publish\"} " . $posts_count->publish . "\n";
    echo "wordpress_posts_total{status=\"draft\"} " . $posts_count->draft . "\n";
    
    // Количество пользователей
    $users_count = count_users();
    echo "wordpress_users_total " . $users_count['total_users'] . "\n";
    
    // Количество комментариев
    $comments_count = wp_count_comments();
    echo "wordpress_comments_total{status=\"approved\"} " . $comments_count->approved . "\n";
    echo "wordpress_comments_total{status=\"spam\"} " . $comments_count->spam . "\n";
    
    // Размер базы данных
    $db_size = $wpdb->get_var("SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='" . DB_NAME . "'");
    echo "wordpress_database_size_mb " . $db_size . "\n";
    
    // Время загрузки страницы
    echo "wordpress_page_load_time_seconds " . (microtime(true) - $_SERVER['REQUEST_TIME_FLOAT']) . "\n";
    
    wp_die();
}
EOF

    # Активация плагина
    wp plugin activate wp-prometheus --allow-root
    
    print_success "Плагин метрик WordPress установлен"
}

# Запуск сервисов мониторинга
start_monitoring_services() {
    print_info "Запуск сервисов мониторинга..."
    
    cd /opt/monitoring
    docker-compose up -d
    
    # Ожидание запуска сервисов
    sleep 30
    
    # Проверка статуса
    if docker-compose ps | grep -q "Up"; then
        print_success "Сервисы мониторинга запущены"
    else
        print_error "Ошибка запуска сервисов мониторинга"
        docker-compose logs
        return 1
    fi
}

# Настройка автоматического резервного копирования метрик
setup_metrics_backup() {
    print_info "Настройка резервного копирования метрик..."
    
    cat > /usr/local/bin/backup-metrics.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups/metrics"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup Prometheus data
docker exec prometheus tar czf - /prometheus | gzip > $BACKUP_DIR/prometheus_$DATE.tar.gz

# Backup Grafana data  
docker exec grafana tar czf - /var/lib/grafana | gzip > $BACKUP_DIR/grafana_$DATE.tar.gz

# Cleanup old backups (older than 7 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Metrics backup completed: $DATE"
EOF

    chmod +x /usr/local/bin/backup-metrics.sh
    
    # Добавление в cron
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/backup-metrics.sh") | crontab -
    
    print_success "Резервное копирование метрик настроено"
}

# Основная функция
main() {
    print_info "=== Установка системы мониторинга ==="
    
    create_monitoring_compose
    configure_prometheus
    configure_grafana
    configure_nginx_monitoring
    install_wp_metrics_plugin
    start_monitoring_services
    setup_metrics_backup
    
    print_success "Система мониторинга установлена!"
    print_info "Grafana: https://${DOMAIN_NAME}:${GRAFANA_PORT}"
    print_info "Пользователь: admin"
    print_info "Пароль: ${GRAFANA_ADMIN_PASSWORD}"
    print_info "Prometheus: https://${DOMAIN_NAME}:${PROMETHEUS_PORT}"
}

main "$@"