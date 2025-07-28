# Руководство по использованию системы автоматизации

## Обзор системы

Система автоматизации WordPress + Cloudflare + Grafana предоставляет полный стек для современного веб-сайта с автоматизацией контента, мониторингом и защитой.

## Основные компоненты

### 1. WordPress
- **URL**: `https://ваш-домен.com`
- **Админка**: `https://ваш-домен.com/wp-admin`
- Оптимизированная конфигурация PHP 8.1
- Автоматические обновления безопасности
- Кеширование через Redis

### 2. Система автоматизации контента
- **API**: `http://ваш-сервер:8000`
- **Документация**: `http://ваш-сервер:8000/docs`
- **WordPress плагин**: Панель администрирования → Автоматизация

### 3. Мониторинг
- **Grafana**: `https://ваш-домен.com:3000`
- **Prometheus**: `https://ваш-домен.com:9090`
- Дашборды для системных метрик и WordPress

### 4. Cloudflare
- Автоматическая настройка DNS
- CDN и кеширование
- Защита от DDoS и ботов
- SSL/TLS оптимизация

## Использование API автоматизации

### Генерация контента

```bash
curl -X POST "http://localhost:8000/content/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "веб-разработка",
    "keywords": ["HTML", "CSS", "JavaScript"],
    "target_length": 1500,
    "tone": "professional"
  }'
```

### Создание поста

```bash
curl -X POST "http://localhost:8000/posts/create" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Новая статья",
    "content": "<p>Содержание статьи</p>",
    "excerpt": "Краткое описание",
    "publish_immediately": false
  }'
```

### SEO оптимизация

```bash
curl -X POST "http://localhost:8000/seo/optimize" \
  -H "Content-Type: application/json" \
  -d '{
    "post_id": 123,
    "focus_keyword": "веб-разработка",
    "meta_description": "Изучите основы веб-разработки"
  }'
```

## Использование WordPress плагина

1. Войдите в админку WordPress
2. Перейдите в **Автоматизация** в боковом меню
3. Используйте доступные функции:
   - **Панель автоматизации** - общий обзор
   - **Генерация контента** - создание нового контента
   - **Аналитика** - статистика и метрики

### Генерация контента через WordPress

1. Перейдите в **Автоматизация** → **Генерация контента**
2. Заполните форму:
   - **Тема**: основная тема статьи
   - **Ключевые слова**: список через запятую
   - **Длина статьи**: выберите подходящий размер
3. Нажмите **Генерировать контент**
4. Дождитесь завершения и проверьте результат

## Мониторинг системы

### Grafana дашборды

1. Откройте Grafana: `https://ваш-домен.com:3000`
2. Войдите (admin / ваш_пароль_grafana)
3. Доступные дашборды:
   - **System Metrics** - системные метрики
   - **WordPress Monitoring** - метрики WordPress
   - **Automation Dashboard** - метрики автоматизации

### Ключевые метрики для мониторинга

- **Загрузка CPU** - не должна превышать 80%
- **Использование RAM** - рекомендуется до 85%
- **Свободное место на диске** - минимум 15%
- **Время ответа WordPress** - оптимально до 2 секунд
- **Статус API автоматизации** - должен быть "Up"
- **Размер очереди задач** - в норме до 10

## Управление сервисами

### Проверка статуса

```bash
# Основные сервисы
systemctl status nginx mysql redis-server

# Сервисы автоматизации
systemctl status automation-api automation-worker automation-scheduler

# Мониторинг
systemctl status prometheus grafana-server
```

### Логы

```bash
# Логи WordPress (Nginx)
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# Логи автоматизации
journalctl -u automation-api -f
journalctl -u automation-worker -f

# Логи планировщика
tail -f /var/log/automation-scheduler.log
```

### Перезапуск сервисов

```bash
# Веб-сервер
systemctl restart nginx

# Автоматизация
systemctl restart automation-api
systemctl restart automation-worker

# Мониторинг
systemctl restart prometheus
systemctl restart grafana-server
```

## Резервное копирование

### Автоматические резервные копии

Система автоматически создает резервные копии:
- **WordPress файлы**: ежедневно в 2:00
- **База данных**: ежедневно в 2:30
- **Метрики**: еженедельно в воскресенье

### Ручное создание резервной копии

```bash
# Резервная копия WordPress
tar -czf /opt/backups/wordpress_$(date +%Y%m%d).tar.gz -C /var/www/ваш-домен.com .

# Резервная копия базы данных
mysqldump -u root -p wordpress > /opt/backups/wordpress_db_$(date +%Y%m%d).sql

# Резервная копия конфигураций
tar -czf /opt/backups/configs_$(date +%Y%m%d).tar.gz /etc/nginx /opt/automation /opt/monitoring
```

## Обслуживание системы

### Обновления

```bash
# Обновление системных пакетов
apt update && apt upgrade -y

# Обновление WordPress (через WP-CLI)
cd /var/www/ваш-домен.com
wp core update --allow-root
wp plugin update --all --allow-root

# Обновление Python пакетов
source /opt/automation-env/bin/activate
pip install --upgrade pip
pip list --outdated
```

### Очистка логов

```bash
# Очистка старых логов (старше 30 дней)
find /var/log -name "*.log" -mtime +30 -delete

# Очистка логов Nginx
truncate -s 0 /var/log/nginx/access.log
truncate -s 0 /var/log/nginx/error.log

# Ротация логов systemd
journalctl --vacuum-time=30d
```

### Оптимизация базы данных

```bash
# Оптимизация WordPress базы данных
cd /var/www/ваш-домен.com
wp db optimize --allow-root

# Очистка ревизий и спама
wp post delete $(wp post list --post_status=trash --format=ids --allow-root)
wp comment delete $(wp comment list --status=spam --format=ids --allow-root)
```

## Устранение неполадок

### API автоматизации не отвечает

```bash
# Проверка статуса
systemctl status automation-api

# Перезапуск
systemctl restart automation-api

# Проверка логов
journalctl -u automation-api -n 50
```

### WordPress недоступен

```bash
# Проверка Nginx
systemctl status nginx
nginx -t

# Проверка PHP-FPM
systemctl status php8.1-fpm

# Проверка базы данных
systemctl status mysql
mysql -u root -p -e "SHOW PROCESSLIST;"
```

### Проблемы с SSL

```bash
# Обновление сертификата
certbot renew --force-renewal

# Проверка конфигурации SSL
openssl s_client -connect ваш-домен.com:443

# Тест Nginx конфигурации
nginx -t
```

## Контакты и поддержка

При возникновении проблем:

1. Проверьте логи сервисов
2. Убедитесь что все сервисы запущены
3. Проверьте свободное место на диске
4. Проверьте сетевое подключение

Для диагностики системы используйте команды из раздела "Управление сервисами".