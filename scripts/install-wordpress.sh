#!/bin/bash

# Скрипт автоматической установки WordPress
# Включает установку LEMP стека, настройку SSL, и оптимизацию

set -euo pipefail

# Импорт функций вывода
source "$(dirname "$0")/../.env"

print_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Установка LEMP стека
install_lemp() {
    print_info "Установка LEMP стека (Nginx, MySQL, PHP)..."
    
    # Установка Nginx
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    
    # Установка MySQL
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
    
    # Безопасная настройка MySQL
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${WP_DB_ROOT_PASSWORD}';"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
    
    # Создание базы данных WordPress
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASSWORD}';"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_USER}'@'localhost';"
    mysql -u root -p"${WP_DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
    
    # Установка PHP
    apt-get install -y php8.1-fpm php8.1-mysql php8.1-curl php8.1-gd php8.1-xml php8.1-mbstring php8.1-zip php8.1-intl php8.1-bcmath
    
    print_success "LEMP стек установлен"
}

# Настройка Nginx для WordPress
configure_nginx() {
    print_info "Настройка Nginx для WordPress..."
    
    # Создание конфигурации сайта
    cat > /etc/nginx/sites-available/"${DOMAIN_NAME}" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};
    root /var/www/${DOMAIN_NAME};
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # WordPress specific rules
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { log_not_found off; access_log off; allow all; }
    location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Deny access to uploads that aren't images, videos, music, etc.
    location ~* ^/wp-content/uploads/.*.(html|htm|shtml|php|js|swf)$ {
        deny all;
    }
}
EOF

    # Включение сайта
    ln -sf /etc/nginx/sites-available/"${DOMAIN_NAME}" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Тестирование конфигурации
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx настроен"
}

# Установка WordPress
install_wordpress() {
    print_info "Установка WordPress..."
    
    # Создание директории сайта
    mkdir -p /var/www/"${DOMAIN_NAME}"
    cd /var/www/"${DOMAIN_NAME}"
    
    # Скачивание WordPress
    wget -O wordpress.tar.gz https://wordpress.org/latest.tar.gz
    tar xzf wordpress.tar.gz --strip-components=1
    rm wordpress.tar.gz
    
    # Настройка прав доступа
    chown -R www-data:www-data /var/www/"${DOMAIN_NAME}"
    find /var/www/"${DOMAIN_NAME}" -type d -exec chmod 755 {} \;
    find /var/www/"${DOMAIN_NAME}" -type f -exec chmod 644 {} \;
    
    # Создание wp-config.php
    cp wp-config-sample.php wp-config.php
    
    # Генерация соли для безопасности
    SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    # Настройка wp-config.php
    sed -i "s/database_name_here/${WP_DB_NAME}/" wp-config.php
    sed -i "s/username_here/${WP_DB_USER}/" wp-config.php
    sed -i "s/password_here/${WP_DB_PASSWORD}/" wp-config.php
    sed -i "s/localhost/localhost/" wp-config.php
    
    # Замена соли
    sed -i '/put your unique phrase here/d' wp-config.php
    sed -i "/Happy publishing/i\\${SALT}" wp-config.php
    
    # Дополнительные настройки безопасности
    cat >> wp-config.php << EOF

/* Дополнительные настройки безопасности */
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', true);

/* Настройки производительности */
define('WP_CACHE', true);
define('COMPRESS_CSS', true);
define('COMPRESS_SCRIPTS', true);
define('CONCATENATE_SCRIPTS', true);

/* Ограничения */
define('WP_MEMORY_LIMIT', '256M');
ini_set('upload_max_size', '64M');
ini_set('post_max_size', '64M');
ini_set('max_execution_time', 300);
EOF

    print_success "WordPress установлен"
}

# Установка SSL сертификата
install_ssl() {
    print_info "Установка SSL сертификата..."
    
    # Установка Certbot
    apt-get install -y certbot python3-certbot-nginx
    
    # Получение сертификата
    if [[ "${SSL_STAGING}" == "true" ]]; then
        certbot --nginx --staging -d "${DOMAIN_NAME}" -d "www.${DOMAIN_NAME}" --email "${LETSENCRYPT_EMAIL}" --agree-tos --non-interactive
    else
        certbot --nginx -d "${DOMAIN_NAME}" -d "www.${DOMAIN_NAME}" --email "${LETSENCRYPT_EMAIL}" --agree-tos --non-interactive
    fi
    
    # Настройка автоматического обновления
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
    
    print_success "SSL сертификат установлен"
}

# Оптимизация PHP
optimize_php() {
    print_info "Оптимизация PHP..."
    
    # Настройка PHP-FPM
    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 64M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/post_max_size = 8M/post_max_size = 64M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/8.1/fpm/php.ini
    sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/8.1/fpm/php.ini
    
    # Перезапуск PHP-FPM
    systemctl restart php8.1-fpm
    
    print_success "PHP оптимизирован"
}

# Установка полезных плагинов WordPress
install_wp_plugins() {
    print_info "Установка полезных плагинов WordPress..."
    
    cd /var/www/"${DOMAIN_NAME}"
    
    # Установка WP-CLI
    curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.7.1/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
    
    # Завершение установки WordPress через WP-CLI
    wp core install --url="https://${DOMAIN_NAME}" --title="${WP_TITLE}" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASSWORD}" --admin_email="${ADMIN_EMAIL}" --allow-root
    
    # Установка полезных плагинов
    wp plugin install wordfence --activate --allow-root
    wp plugin install wp-super-cache --activate --allow-root
    wp plugin install yoast --activate --allow-root
    wp plugin install contact-form-7 --activate --allow-root
    wp plugin install updraftplus --activate --allow-root
    
    print_success "Плагины WordPress установлены"
}

# Настройка мониторинга WordPress
setup_wp_monitoring() {
    print_info "Настройка мониторинга WordPress..."
    
    # Создание скрипта мониторинга
    cat > /usr/local/bin/wp-monitor.sh << 'EOF'
#!/bin/bash
WP_PATH="/var/www/${DOMAIN_NAME}"
LOG_FILE="/var/log/wp-monitor.log"

# Проверка доступности сайта
if curl -f -s "https://${DOMAIN_NAME}" > /dev/null; then
    echo "$(date): WordPress site is UP" >> $LOG_FILE
else
    echo "$(date): WordPress site is DOWN" >> $LOG_FILE
fi

# Проверка базы данных
if mysql -u "${WP_DB_USER}" -p"${WP_DB_PASSWORD}" -e "USE ${WP_DB_NAME};" 2>/dev/null; then
    echo "$(date): Database connection OK" >> $LOG_FILE
else
    echo "$(date): Database connection FAILED" >> $LOG_FILE
fi
EOF

    chmod +x /usr/local/bin/wp-monitor.sh
    
    # Добавление в cron
    echo "*/5 * * * * /usr/local/bin/wp-monitor.sh" | crontab -
    
    print_success "Мониторинг WordPress настроен"
}

# Основная функция
main() {
    print_info "=== Установка WordPress ==="
    
    install_lemp
    configure_nginx
    install_wordpress
    install_ssl
    optimize_php
    install_wp_plugins
    setup_wp_monitoring
    
    print_success "WordPress успешно установлен и настроен!"
    print_info "URL: https://${DOMAIN_NAME}"
    print_info "Админ-панель: https://${DOMAIN_NAME}/wp-admin"
    print_info "Пользователь: ${WP_ADMIN_USER}"
    print_info "Пароль: ${WP_ADMIN_PASSWORD}"
}

main "$@"