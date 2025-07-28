#!/bin/bash

# Скрипт автоматической настройки Cloudflare
# Включает настройку DNS, CDN, правил безопасности и оптимизации

set -euo pipefail

# Импорт функций вывода
source "$(dirname "$0")/../.env"

print_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Базовые переменные
CF_API_URL="https://api.cloudflare.com/client/v4"
CF_HEADERS=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

# Функция для API запросов к Cloudflare
cf_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    if [[ "$method" == "GET" ]]; then
        curl -s -X GET "${CF_API_URL}${endpoint}" "${CF_HEADERS[@]}"
    else
        curl -s -X "$method" "${CF_API_URL}${endpoint}" "${CF_HEADERS[@]}" -d "$data"
    fi
}

# Получение IP адреса сервера
get_server_ip() {
    curl -s http://ipv4.icanhazip.com || curl -s http://checkip.amazonaws.com || dig +short myip.opendns.com @resolver1.opendns.com
}

# Настройка DNS записей
setup_dns_records() {
    print_info "Настройка DNS записей в Cloudflare..."
    
    local server_ip
    server_ip=$(get_server_ip)
    
    if [[ -z "$server_ip" ]]; then
        print_error "Не удалось получить IP адрес сервера"
        return 1
    fi
    
    print_info "IP сервера: $server_ip"
    
    # Создание/обновление A записи для основного домена
    local dns_record_data="{
        \"type\": \"A\",
        \"name\": \"${DOMAIN_NAME}\",
        \"content\": \"${server_ip}\",
        \"ttl\": 300,
        \"proxied\": true
    }"
    
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "$dns_record_data"
    
    # Создание/обновление A записи для www
    local www_dns_record_data="{
        \"type\": \"A\",
        \"name\": \"www.${DOMAIN_NAME}\",
        \"content\": \"${server_ip}\",
        \"ttl\": 300,
        \"proxied\": true
    }"
    
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "$www_dns_record_data"
    
    print_success "DNS записи настроены"
}

# Настройка правил безопасности
setup_security_rules() {
    print_info "Настройка правил безопасности..."
    
    # Блокировка опасных стран (пример)
    local geo_rule="{
        \"targets\": [{
            \"target\": \"country\",
            \"constraint\": {
                \"operator\": \"in\",
                \"value\": [\"CN\", \"RU\", \"KP\"]
            }
        }],
        \"action\": \"challenge\",
        \"priority\": 1,
        \"description\": \"Challenge traffic from suspicious countries\"
    }"
    
    # Защита от SQL инъекций
    local sql_injection_rule="{
        \"targets\": [{
            \"target\": \"uri.query\",
            \"constraint\": {
                \"operator\": \"contains\",
                \"value\": \"union select\"
            }
        }],
        \"action\": \"block\",
        \"priority\": 2,
        \"description\": \"Block SQL injection attempts\"
    }"
    
    # Защита от XSS
    local xss_rule="{
        \"targets\": [{
            \"target\": \"uri.query\",
            \"constraint\": {
                \"operator\": \"contains\",
                \"value\": \"<script\"
            }
        }],
        \"action\": \"block\",
        \"priority\": 3,
        \"description\": \"Block XSS attempts\"
    }"
    
    # Ограничение доступа к wp-admin
    local wp_admin_rule="{
        \"targets\": [{
            \"target\": \"uri.path\",
            \"constraint\": {
                \"operator\": \"starts_with\",
                \"value\": \"/wp-admin\"
            }
        }, {
            \"target\": \"ip.src\",
            \"constraint\": {
                \"operator\": \"not_in\",
                \"value\": [\"${server_ip}/32\"]
            }
        }],
        \"action\": \"challenge\",
        \"priority\": 4,
        \"description\": \"Challenge access to wp-admin from external IPs\"
    }"
    
    # Применение правил
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/firewall/rules" "$geo_rule"
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/firewall/rules" "$sql_injection_rule"
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/firewall/rules" "$xss_rule"
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/firewall/rules" "$wp_admin_rule"
    
    print_success "Правила безопасности настроены"
}

# Настройка SSL/TLS
setup_ssl_tls() {
    print_info "Настройка SSL/TLS..."
    
    # Установка строгого SSL режима
    local ssl_setting="{
        \"value\": \"strict\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/ssl" "$ssl_setting"
    
    # Включение HSTS
    local hsts_setting="{
        \"value\": {
            \"enabled\": true,
            \"max_age\": 31536000,
            \"include_subdomains\": true,
            \"preload\": true
        }
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/security_header" "$hsts_setting"
    
    # Минимальная версия TLS
    local min_tls_setting="{
        \"value\": \"1.2\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/min_tls_version" "$min_tls_setting"
    
    print_success "SSL/TLS настроен"
}

# Настройка кеширования
setup_caching() {
    print_info "Настройка кеширования..."
    
    # Настройка уровня кеширования
    local cache_level="{
        \"value\": \"aggressive\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/cache_level" "$cache_level"
    
    # Настройка TTL браузера
    local browser_cache_ttl="{
        \"value\": 31536000
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/browser_cache_ttl" "$browser_cache_ttl"
    
    # Правила кеширования для статических файлов
    local static_cache_rule="{
        \"targets\": [{
            \"target\": \"uri.path\",
            \"constraint\": {
                \"operator\": \"matches\",
                \"value\": \".*\\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$\"
            }
        }],
        \"actions\": [{
            \"id\": \"cache_everything\",
            \"value\": \"on\"
        }, {
            \"id\": \"edge_cache_ttl\",
            \"value\": 2592000
        }],
        \"priority\": 1,
        \"status\": \"active\",
        \"description\": \"Cache static assets for 30 days\"
    }"
    
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/pagerules" "$static_cache_rule"
    
    # Правило кеширования для WordPress
    local wp_cache_rule="{
        \"targets\": [{
            \"target\": \"uri.path\",
            \"constraint\": {
                \"operator\": \"not_matches\",
                \"value\": \".*/wp-(admin|login|register|comments-post|cron)\\.php.*\"
            }
        }, {
            \"target\": \"uri.query\",
            \"constraint\": {
                \"operator\": \"equals\",
                \"value\": \"\"
            }
        }],
        \"actions\": [{
            \"id\": \"cache_everything\",
            \"value\": \"on\"
        }, {
            \"id\": \"edge_cache_ttl\",
            \"value\": 7200
        }],
        \"priority\": 2,
        \"status\": \"active\",
        \"description\": \"Cache WordPress pages for 2 hours\"
    }"
    
    cf_api_request "POST" "/zones/${CLOUDFLARE_ZONE_ID}/pagerules" "$wp_cache_rule"
    
    print_success "Кеширование настроено"
}

# Настройка сжатия и оптимизации
setup_optimization() {
    print_info "Настройка оптимизации..."
    
    # Включение Brotli сжатия
    local brotli_setting="{
        \"value\": \"on\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/brotli" "$brotli_setting"
    
    # Минификация HTML, CSS, JS
    local minify_setting="{
        \"value\": {
            \"css\": \"on\",
            \"html\": \"on\",
            \"js\": \"on\"
        }
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/minify" "$minify_setting"
    
    # Оптимизация изображений
    local image_optimization="{
        \"value\": \"lossless\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/polish" "$image_optimization"
    
    # Ракетный загрузчик
    local rocket_loader="{
        \"value\": \"on\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/rocket_loader" "$rocket_loader"
    
    print_success "Оптимизация настроена"
}

# Настройка DDoS защиты
setup_ddos_protection() {
    print_info "Настройка DDoS защиты..."
    
    # Режим Under Attack (можно включить при необходимости)
    local security_level="{
        \"value\": \"high\"
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/security_level" "$security_level"
    
    # Настройка Challenge Passage
    local challenge_ttl="{
        \"value\": 1800
    }"
    
    cf_api_request "PATCH" "/zones/${CLOUDFLARE_ZONE_ID}/settings/challenge_ttl" "$challenge_ttl"
    
    print_success "DDoS защита настроена"
}

# Настройка мониторинга Cloudflare
setup_cf_monitoring() {
    print_info "Настройка мониторинга Cloudflare..."
    
    # Создание скрипта мониторинга статистики Cloudflare
    cat > /usr/local/bin/cf-stats.sh << 'EOF'
#!/bin/bash
source /workspace/.env

CF_API_URL="https://api.cloudflare.com/client/v4"
CF_HEADERS=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
LOG_FILE="/var/log/cloudflare-stats.log"

# Получение статистики
STATS=$(curl -s -X GET "${CF_API_URL}/zones/${CLOUDFLARE_ZONE_ID}/analytics/dashboard" "${CF_HEADERS[@]}")

# Логирование
echo "$(date): $STATS" >> $LOG_FILE

# Извлечение метрик для Prometheus
REQUESTS=$(echo $STATS | jq -r '.result.totals.requests.all // 0')
BANDWIDTH=$(echo $STATS | jq -r '.result.totals.bandwidth.all // 0')
THREATS=$(echo $STATS | jq -r '.result.totals.threats.all // 0')

# Запись метрик
echo "cloudflare_requests_total $REQUESTS" > /tmp/cloudflare_metrics.prom
echo "cloudflare_bandwidth_bytes $BANDWIDTH" >> /tmp/cloudflare_metrics.prom
echo "cloudflare_threats_total $THREATS" >> /tmp/cloudflare_metrics.prom
EOF

    chmod +x /usr/local/bin/cf-stats.sh
    
    # Добавление в cron
    (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/cf-stats.sh") | crontab -
    
    print_success "Мониторинг Cloudflare настроен"
}

# Создание воркера Cloudflare для дополнительной логики
setup_cloudflare_worker() {
    print_info "Создание Cloudflare Worker..."
    
    # Код воркера для дополнительной обработки
    local worker_script='
addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)
  
  // Блокировка доступа к файлам конфигурации
  if (url.pathname.includes("wp-config.php") || 
      url.pathname.includes(".env") ||
      url.pathname.includes("/.git/")) {
    return new Response("Access Denied", { status: 403 })
  }
  
  // Дополнительная безопасность для wp-admin
  if (url.pathname.startsWith("/wp-admin/") && 
      !request.headers.get("cf-connecting-ip")) {
    return new Response("Access Denied", { status: 403 })
  }
  
  // Продолжение обработки запроса
  return fetch(request)
}'
    
    # Создание воркера через API
    local worker_data="{
        \"script\": \"$worker_script\",
        \"metadata\": {
            \"body_part\": \"script\"
        }
    }"
    
    cf_api_request "PUT" "/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/security-worker" "$worker_data"
    
    print_success "Cloudflare Worker создан"
}

# Проверка статуса настроек
verify_cloudflare_setup() {
    print_info "Проверка настроек Cloudflare..."
    
    # Проверка DNS записей
    local dns_records
    dns_records=$(cf_api_request "GET" "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "")
    
    if echo "$dns_records" | grep -q "\"name\":\"${DOMAIN_NAME}\""; then
        print_success "DNS записи найдены"
    else
        print_warning "DNS записи могут быть не настроены корректно"
    fi
    
    # Проверка доступности сайта через Cloudflare
    if curl -s -I "https://${DOMAIN_NAME}" | grep -q "cf-ray"; then
        print_success "Сайт доступен через Cloudflare"
    else
        print_warning "Сайт может быть недоступен через Cloudflare"
    fi
    
    print_success "Проверка завершена"
}

# Создание отчета о настройках
generate_cloudflare_report() {
    print_info "Создание отчета о настройках..."
    
    local report_file="/tmp/cloudflare-setup-report.txt"
    
    cat > "$report_file" << EOF
=== Отчет о настройке Cloudflare ===
Дата: $(date)
Домен: ${DOMAIN_NAME}
Zone ID: ${CLOUDFLARE_ZONE_ID}

Настроенные функции:
- DNS записи (A записи для домена и www)
- Правила безопасности (блокировка опасных стран, SQL инъекций, XSS)
- SSL/TLS (строгий режим, HSTS, минимальная версия TLS 1.2)
- Кеширование (агрессивное кеширование, правила для статических файлов)
- Оптимизация (Brotli, минификация, оптимизация изображений)
- DDoS защита (высокий уровень безопасности)
- Мониторинг (скрипт статистики)

Рекомендации:
1. Проверьте DNS пропагацию (может занять до 24 часов)
2. Протестируйте работу сайта через Cloudflare
3. Настройте дополнительные правила безопасности по необходимости
4. Мониторьте логи в /var/log/cloudflare-stats.log

Полезные ссылки:
- Панель управления: https://dash.cloudflare.com
- Аналитика: https://dash.cloudflare.com/zones/${CLOUDFLARE_ZONE_ID}/analytics
- Настройки безопасности: https://dash.cloudflare.com/zones/${CLOUDFLARE_ZONE_ID}/security
EOF

    print_success "Отчет создан: $report_file"
    cat "$report_file"
}

# Основная функция
main() {
    print_info "=== Настройка Cloudflare ==="
    
    # Проверка наличия необходимых переменных
    if [[ -z "${CLOUDFLARE_API_TOKEN}" || -z "${CLOUDFLARE_ZONE_ID}" ]]; then
        print_error "Не заданы CLOUDFLARE_API_TOKEN или CLOUDFLARE_ZONE_ID"
        exit 1
    fi
    
    setup_dns_records
    setup_security_rules
    setup_ssl_tls
    setup_caching
    setup_optimization
    setup_ddos_protection
    setup_cf_monitoring
    verify_cloudflare_setup
    generate_cloudflare_report
    
    print_success "Cloudflare настроен успешно!"
    print_info "Панель управления: https://dash.cloudflare.com"
    print_info "Проверьте DNS пропагацию командой: dig ${DOMAIN_NAME}"
}

main "$@"