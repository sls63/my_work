#!/bin/bash

# Скрипт настройки системы автоматизации контента
# Включает настройку API, автоматического создания контента и SEO-оптимизации

set -euo pipefail

# Импорт функций вывода
source "$(dirname "$0")/../.env"

print_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Установка системы управления задачами
install_task_scheduler() {
    print_info "Установка системы управления задачами..."
    
    # Установка Redis для очередей задач
    apt-get install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server
    
    # Установка Python и необходимых библиотек
    apt-get install -y python3 python3-pip python3-venv
    
    # Создание виртуального окружения
    python3 -m venv /opt/automation-env
    source /opt/automation-env/bin/activate
    
    # Установка пакетов
    pip install \
        celery \
        redis \
        requests \
        beautifulsoup4 \
        wordpress-api \
        openai \
        schedule \
        pydantic \
        fastapi \
        uvicorn
    
    print_success "Система управления задачами установлена"
}

# Создание API для автоматизации
create_automation_api() {
    print_info "Создание API для автоматизации..."
    
    mkdir -p /opt/automation
    
    # Основной API файл
    cat > /opt/automation/main.py << 'EOF'
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional, List
import requests
import json
import os
from celery import Celery
import redis

app = FastAPI(title="WordPress Automation API", version="1.0.0")

# Настройка Celery
celery_app = Celery('automation',
                   broker='redis://localhost:6379/0',
                   backend='redis://localhost:6379/0')

# Модели данных
class PostRequest(BaseModel):
    title: str
    content: str
    excerpt: Optional[str] = None
    categories: Optional[List[str]] = []
    tags: Optional[List[str]] = []
    featured_image: Optional[str] = None
    publish_immediately: bool = False

class SEOOptimization(BaseModel):
    focus_keyword: str
    meta_description: Optional[str] = None
    meta_title: Optional[str] = None

class ContentGeneration(BaseModel):
    topic: str
    keywords: List[str]
    target_length: int = 1000
    tone: str = "professional"

# WordPress API клиент
class WordPressAPI:
    def __init__(self):
        self.base_url = f"https://{os.getenv('DOMAIN_NAME')}/wp-json/wp/v2"
        self.auth = (os.getenv('WP_ADMIN_USER'), os.getenv('WP_ADMIN_PASSWORD'))
    
    def create_post(self, post_data: dict):
        """Создание поста в WordPress"""
        response = requests.post(
            f"{self.base_url}/posts",
            json=post_data,
            auth=self.auth
        )
        response.raise_for_status()
        return response.json()
    
    def update_post(self, post_id: int, post_data: dict):
        """Обновление поста"""
        response = requests.post(
            f"{self.base_url}/posts/{post_id}",
            json=post_data,
            auth=self.auth
        )
        response.raise_for_status()
        return response.json()
    
    def get_categories(self):
        """Получение списка категорий"""
        response = requests.get(f"{self.base_url}/categories")
        response.raise_for_status()
        return response.json()
    
    def create_category(self, name: str, description: str = ""):
        """Создание новой категории"""
        response = requests.post(
            f"{self.base_url}/categories",
            json={"name": name, "description": description},
            auth=self.auth
        )
        response.raise_for_status()
        return response.json()

wp_api = WordPressAPI()

# Задачи Celery
@celery_app.task
def generate_content_task(topic: str, keywords: List[str], length: int):
    """Задача генерации контента"""
    # Здесь можно интегрировать AI для генерации контента
    # Пример простой генерации
    content = f"""
    <h2>Введение в {topic}</h2>
    <p>В этой статье мы рассмотрим важные аспекты {topic}.</p>
    
    <h3>Ключевые моменты</h3>
    <ul>
    {"".join([f"<li>Важность {keyword}</li>" for keyword in keywords])}
    </ul>
    
    <h3>Заключение</h3>
    <p>Понимание {topic} критически важно для современного бизнеса.</p>
    """
    
    return {
        "title": f"Полное руководство по {topic}",
        "content": content,
        "excerpt": f"Изучите все аспекты {topic} в нашем подробном руководстве."
    }

@celery_app.task
def optimize_seo_task(post_id: int, focus_keyword: str):
    """Задача SEO-оптимизации"""
    # Получение поста и оптимизация
    seo_data = {
        "meta": {
            "focus_keyword": focus_keyword,
            "meta_description": f"Узнайте больше о {focus_keyword}",
            "meta_title": f"{focus_keyword} - Полное руководство"
        }
    }
    return seo_data

# API endpoints
@app.get("/")
async def root():
    return {"message": "WordPress Automation API v1.0"}

@app.post("/posts/create")
async def create_post(post: PostRequest, background_tasks: BackgroundTasks):
    """Создание нового поста"""
    try:
        post_data = {
            "title": post.title,
            "content": post.content,
            "excerpt": post.excerpt,
            "status": "publish" if post.publish_immediately else "draft"
        }
        
        result = wp_api.create_post(post_data)
        
        # Добавление задачи SEO-оптимизации в фон
        if post.categories or post.tags:
            background_tasks.add_task(optimize_post_seo, result["id"], post.categories, post.tags)
        
        return {"success": True, "post_id": result["id"], "message": "Post created successfully"}
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/content/generate")
async def generate_content(request: ContentGeneration):
    """Генерация контента"""
    task = generate_content_task.delay(
        request.topic, 
        request.keywords, 
        request.target_length
    )
    
    return {"task_id": task.id, "status": "processing"}

@app.get("/content/status/{task_id}")
async def get_content_status(task_id: str):
    """Проверка статуса генерации контента"""
    task = celery_app.AsyncResult(task_id)
    
    if task.ready():
        return {"status": "completed", "result": task.result}
    else:
        return {"status": "processing"}

@app.post("/seo/optimize")
async def optimize_seo(post_id: int, seo: SEOOptimization):
    """SEO-оптимизация поста"""
    task = optimize_seo_task.delay(post_id, seo.focus_keyword)
    return {"task_id": task.id, "status": "processing"}

@app.get("/analytics/posts")
async def get_post_analytics():
    """Аналитика постов"""
    # Здесь можно добавить интеграцию с Google Analytics
    return {"total_posts": 0, "published": 0, "draft": 0}

def optimize_post_seo(post_id: int, categories: List[str], tags: List[str]):
    """Оптимизация SEO поста"""
    # Логика SEO-оптимизации
    pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    print_success "API для автоматизации создан"
}

# Создание системы планировщика задач
create_task_scheduler() {
    print_info "Создание планировщика задач..."
    
    cat > /opt/automation/scheduler.py << 'EOF'
import schedule
import time
import requests
import json
from datetime import datetime
import logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/automation-scheduler.log'),
        logging.StreamHandler()
    ]
)

class AutomationScheduler:
    def __init__(self):
        self.api_base = "http://localhost:8000"
        
    def auto_generate_content(self):
        """Автоматическая генерация контента"""
        topics = [
            "веб-разработка",
            "SEO-оптимизация", 
            "цифровой маркетинг",
            "облачные технологии"
        ]
        
        for topic in topics:
            try:
                response = requests.post(f"{self.api_base}/content/generate", json={
                    "topic": topic,
                    "keywords": [topic, "руководство", "советы"],
                    "target_length": 1500,
                    "tone": "professional"
                })
                
                if response.status_code == 200:
                    logging.info(f"Запущена генерация контента для темы: {topic}")
                else:
                    logging.error(f"Ошибка генерации контента: {response.text}")
                    
            except Exception as e:
                logging.error(f"Ошибка при генерации контента: {e}")
    
    def cleanup_drafts(self):
        """Очистка старых черновиков"""
        logging.info("Запуск очистки старых черновиков")
        # Логика очистки черновиков старше 30 дней
    
    def backup_content(self):
        """Резервное копирование контента"""
        logging.info("Запуск резервного копирования контента")
        # Логика резервного копирования
    
    def update_seo_analytics(self):
        """Обновление SEO аналитики"""
        logging.info("Обновление SEO аналитики")
        # Интеграция с Google Search Console, Analytics

def main():
    scheduler = AutomationScheduler()
    
    # Планирование задач
    schedule.every().day.at("09:00").do(scheduler.auto_generate_content)
    schedule.every().sunday.at("02:00").do(scheduler.cleanup_drafts)
    schedule.every().day.at("03:00").do(scheduler.backup_content)
    schedule.every().hour.do(scheduler.update_seo_analytics)
    
    logging.info("Планировщик задач запущен")
    
    while True:
        schedule.run_pending()
        time.sleep(60)

if __name__ == "__main__":
    main()
EOF

    print_success "Планировщик задач создан"
}

# Создание WordPress плагина для интеграции
create_wordpress_plugin() {
    print_info "Создание WordPress плагина для автоматизации..."
    
    mkdir -p /var/www/"${DOMAIN_NAME}"/wp-content/plugins/automation-integration
    
    cat > /var/www/"${DOMAIN_NAME}"/wp-content/plugins/automation-integration/automation-integration.php << 'EOF'
<?php
/**
 * Plugin Name: Automation Integration
 * Description: Интеграция с системой автоматизации контента
 * Version: 1.0
 * Author: Automation System
 */

if (!defined('ABSPATH')) {
    exit;
}

class AutomationIntegration {
    
    private $api_base = 'http://localhost:8000';
    
    public function __construct() {
        add_action('init', array($this, 'init'));
        add_action('admin_menu', array($this, 'add_admin_menu'));
        add_action('wp_ajax_automation_generate', array($this, 'handle_generate_content'));
        add_action('wp_ajax_automation_analytics', array($this, 'handle_analytics'));
        add_action('add_meta_boxes', array($this, 'add_seo_meta_box'));
        add_action('save_post', array($this, 'save_seo_data'));
    }
    
    public function init() {
        // Регистрация REST API endpoints
        add_action('rest_api_init', array($this, 'register_rest_routes'));
    }
    
    public function register_rest_routes() {
        register_rest_route('automation/v1', '/generate', array(
            'methods' => 'POST',
            'callback' => array($this, 'rest_generate_content'),
            'permission_callback' => array($this, 'check_permissions')
        ));
        
        register_rest_route('automation/v1', '/analytics', array(
            'methods' => 'GET',
            'callback' => array($this, 'rest_get_analytics'),
            'permission_callback' => array($this, 'check_permissions')
        ));
    }
    
    public function check_permissions() {
        return current_user_can('edit_posts');
    }
    
    public function rest_generate_content($request) {
        $topic = $request->get_param('topic');
        $keywords = $request->get_param('keywords');
        
        $response = wp_remote_post($this->api_base . '/content/generate', array(
            'body' => json_encode(array(
                'topic' => $topic,
                'keywords' => $keywords,
                'target_length' => 1500
            )),
            'headers' => array('Content-Type' => 'application/json')
        ));
        
        if (is_wp_error($response)) {
            return new WP_Error('api_error', 'Ошибка обращения к API автоматизации');
        }
        
        return json_decode(wp_remote_retrieve_body($response), true);
    }
    
    public function add_admin_menu() {
        add_menu_page(
            'Автоматизация',
            'Автоматизация',
            'manage_options',
            'automation-dashboard',
            array($this, 'admin_dashboard'),
            'dashicons-robot',
            30
        );
        
        add_submenu_page(
            'automation-dashboard',
            'Генерация контента',
            'Генерация контента',
            'edit_posts',
            'automation-generate',
            array($this, 'generate_page')
        );
        
        add_submenu_page(
            'automation-dashboard',
            'Аналитика',
            'Аналитика',
            'manage_options',
            'automation-analytics',
            array($this, 'analytics_page')
        );
    }
    
    public function admin_dashboard() {
        ?>
        <div class="wrap">
            <h1>Панель автоматизации</h1>
            <div class="automation-dashboard">
                <div class="dashboard-widget">
                    <h3>Статус системы</h3>
                    <p id="system-status">Проверка...</p>
                </div>
                <div class="dashboard-widget">
                    <h3>Последние задачи</h3>
                    <ul id="recent-tasks"></ul>
                </div>
                <div class="dashboard-widget">
                    <h3>Статистика</h3>
                    <p>Сгенерировано постов: <span id="posts-count">0</span></p>
                    <p>Активных задач: <span id="active-tasks">0</span></p>
                </div>
            </div>
        </div>
        
        <script>
        jQuery(document).ready(function($) {
            // Проверка статуса системы
            $.get('/wp-json/automation/v1/analytics', function(data) {
                $('#system-status').text('Система работает');
                $('#posts-count').text(data.total_posts || 0);
            }).fail(function() {
                $('#system-status').text('Система недоступна');
            });
        });
        </script>
        
        <style>
        .automation-dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .dashboard-widget {
            background: white;
            padding: 20px;
            border: 1px solid #ccd0d4;
            border-radius: 4px;
        }
        .dashboard-widget h3 {
            margin-top: 0;
        }
        </style>
        <?php
    }
    
    public function generate_page() {
        ?>
        <div class="wrap">
            <h1>Генерация контента</h1>
            <form id="content-generation-form">
                <table class="form-table">
                    <tr>
                        <th><label for="topic">Тема</label></th>
                        <td><input type="text" id="topic" name="topic" class="regular-text" required /></td>
                    </tr>
                    <tr>
                        <th><label for="keywords">Ключевые слова</label></th>
                        <td><input type="text" id="keywords" name="keywords" class="regular-text" placeholder="слово1, слово2, слово3" /></td>
                    </tr>
                    <tr>
                        <th><label for="length">Длина статьи</label></th>
                        <td>
                            <select id="length" name="length">
                                <option value="500">Короткая (500 слов)</option>
                                <option value="1000" selected>Средняя (1000 слов)</option>
                                <option value="1500">Длинная (1500 слов)</option>
                                <option value="2000">Очень длинная (2000+ слов)</option>
                            </select>
                        </td>
                    </tr>
                </table>
                <p class="submit">
                    <input type="submit" class="button-primary" value="Генерировать контент" />
                </p>
            </form>
            <div id="generation-status" style="display: none;">
                <h3>Статус генерации</h3>
                <p id="status-message">Обработка...</p>
                <div id="progress-bar" style="width: 100%; background: #f0f0f0; height: 20px;">
                    <div style="width: 0%; background: #0073aa; height: 100%; transition: width 0.3s;"></div>
                </div>
            </div>
        </div>
        
        <script>
        jQuery(document).ready(function($) {
            $('#content-generation-form').on('submit', function(e) {
                e.preventDefault();
                
                const topic = $('#topic').val();
                const keywords = $('#keywords').val().split(',').map(k => k.trim());
                const length = parseInt($('#length').val());
                
                $('#generation-status').show();
                $('#status-message').text('Запуск генерации...');
                
                $.post('/wp-json/automation/v1/generate', {
                    topic: topic,
                    keywords: keywords,
                    target_length: length
                }, function(response) {
                    if (response.task_id) {
                        checkTaskStatus(response.task_id);
                    }
                });
            });
            
            function checkTaskStatus(taskId) {
                const interval = setInterval(function() {
                    $.get('http://localhost:8000/content/status/' + taskId, function(data) {
                        if (data.status === 'completed') {
                            clearInterval(interval);
                            $('#status-message').text('Контент сгенерирован успешно!');
                            // Здесь можно добавить логику создания поста
                        } else {
                            $('#status-message').text('Генерация в процессе...');
                        }
                    });
                }, 2000);
            }
        });
        </script>
        <?php
    }
    
    public function analytics_page() {
        ?>
        <div class="wrap">
            <h1>Аналитика автоматизации</h1>
            <div id="analytics-charts">
                <div class="chart-container">
                    <h3>Статистика постов</h3>
                    <canvas id="posts-chart"></canvas>
                </div>
                <div class="chart-container">
                    <h3>SEO метрики</h3>
                    <canvas id="seo-chart"></canvas>
                </div>
            </div>
        </div>
        
        <style>
        #analytics-charts {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin-top: 20px;
        }
        .chart-container {
            background: white;
            padding: 20px;
            border: 1px solid #ccd0d4;
            border-radius: 4px;
        }
        </style>
        <?php
    }
    
    public function add_seo_meta_box() {
        add_meta_box(
            'automation-seo',
            'SEO Автоматизация',
            array($this, 'seo_meta_box_callback'),
            'post',
            'normal',
            'high'
        );
    }
    
    public function seo_meta_box_callback($post) {
        wp_nonce_field('automation_seo_nonce', 'automation_seo_nonce');
        
        $focus_keyword = get_post_meta($post->ID, '_automation_focus_keyword', true);
        $meta_description = get_post_meta($post->ID, '_automation_meta_description', true);
        
        ?>
        <table class="form-table">
            <tr>
                <th><label for="focus_keyword">Фокусное ключевое слово</label></th>
                <td><input type="text" id="focus_keyword" name="focus_keyword" value="<?php echo esc_attr($focus_keyword); ?>" class="regular-text" /></td>
            </tr>
            <tr>
                <th><label for="meta_description">Мета-описание</label></th>
                <td><textarea id="meta_description" name="meta_description" rows="3" class="large-text"><?php echo esc_textarea($meta_description); ?></textarea></td>
            </tr>
        </table>
        <p>
            <button type="button" id="optimize-seo" class="button">Автоматическая SEO-оптимизация</button>
        </p>
        
        <script>
        jQuery(document).ready(function($) {
            $('#optimize-seo').on('click', function() {
                const postId = <?php echo $post->ID; ?>;
                const focusKeyword = $('#focus_keyword').val();
                
                if (!focusKeyword) {
                    alert('Пожалуйста, укажите фокусное ключевое слово');
                    return;
                }
                
                $.post('http://localhost:8000/seo/optimize', {
                    post_id: postId,
                    focus_keyword: focusKeyword
                }, function(response) {
                    alert('SEO-оптимизация запущена');
                });
            });
        });
        </script>
        <?php
    }
    
    public function save_seo_data($post_id) {
        if (!isset($_POST['automation_seo_nonce']) || !wp_verify_nonce($_POST['automation_seo_nonce'], 'automation_seo_nonce')) {
            return;
        }
        
        if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) {
            return;
        }
        
        if (!current_user_can('edit_post', $post_id)) {
            return;
        }
        
        if (isset($_POST['focus_keyword'])) {
            update_post_meta($post_id, '_automation_focus_keyword', sanitize_text_field($_POST['focus_keyword']));
        }
        
        if (isset($_POST['meta_description'])) {
            update_post_meta($post_id, '_automation_meta_description', sanitize_textarea_field($_POST['meta_description']));
        }
    }
}

new AutomationIntegration();
EOF

    # Активация плагина
    cd /var/www/"${DOMAIN_NAME}"
    wp plugin activate automation-integration --allow-root
    
    print_success "WordPress плагин создан и активирован"
}

# Создание сервисов systemd
create_systemd_services() {
    print_info "Создание systemd сервисов..."
    
    # Сервис API
    cat > /etc/systemd/system/automation-api.service << EOF
[Unit]
Description=Automation API Service
After=network.target redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/automation
Environment=PATH=/opt/automation-env/bin
ExecStart=/opt/automation-env/bin/python main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Сервис Celery worker
    cat > /etc/systemd/system/automation-worker.service << EOF
[Unit]
Description=Automation Celery Worker
After=network.target redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/automation
Environment=PATH=/opt/automation-env/bin
ExecStart=/opt/automation-env/bin/celery -A main.celery_app worker --loglevel=info
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Сервис планировщика
    cat > /etc/systemd/system/automation-scheduler.service << EOF
[Unit]
Description=Automation Task Scheduler
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/automation
Environment=PATH=/opt/automation-env/bin
ExecStart=/opt/automation-env/bin/python scheduler.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Активация сервисов
    systemctl daemon-reload
    systemctl enable automation-api
    systemctl enable automation-worker
    systemctl enable automation-scheduler
    
    systemctl start automation-api
    systemctl start automation-worker
    systemctl start automation-scheduler
    
    print_success "Systemd сервисы созданы и запущены"
}

# Настройка мониторинга автоматизации
setup_automation_monitoring() {
    print_info "Настройка мониторинга системы автоматизации..."
    
    # Создание exporter для метрик
    cat > /opt/automation/metrics_exporter.py << 'EOF'
#!/usr/bin/env python3
from prometheus_client import start_http_server, Gauge, Counter, Histogram
import time
import redis
import requests
import json

# Метрики
automation_tasks_total = Counter('automation_tasks_total', 'Total automation tasks', ['status'])
automation_api_requests = Counter('automation_api_requests_total', 'Total API requests', ['endpoint', 'method'])
automation_generation_time = Histogram('automation_content_generation_seconds', 'Content generation time')
automation_queue_size = Gauge('automation_queue_size', 'Current queue size')
automation_api_status = Gauge('automation_api_status', 'API service status')

class AutomationMetrics:
    def __init__(self):
        self.redis_client = redis.Redis(host='localhost', port=6379, db=0)
    
    def collect_metrics(self):
        """Сбор метрик автоматизации"""
        try:
            # Проверка статуса API
            response = requests.get('http://localhost:8000/', timeout=5)
            automation_api_status.set(1 if response.status_code == 200 else 0)
        except:
            automation_api_status.set(0)
        
        # Размер очереди задач
        try:
            queue_size = self.redis_client.llen('celery')
            automation_queue_size.set(queue_size)
        except:
            automation_queue_size.set(-1)

def main():
    metrics = AutomationMetrics()
    start_http_server(9105)
    
    while True:
        metrics.collect_metrics()
        time.sleep(30)

if __name__ == '__main__':
    main()
EOF

    chmod +x /opt/automation/metrics_exporter.py
    
    # Сервис для exporter
    cat > /etc/systemd/system/automation-metrics.service << EOF
[Unit]
Description=Automation Metrics Exporter
After=network.target redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/automation
Environment=PATH=/opt/automation-env/bin
ExecStart=/opt/automation-env/bin/python metrics_exporter.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable automation-metrics
    systemctl start automation-metrics
    
    print_success "Мониторинг автоматизации настроен"
}

# Создание дашборда Grafana
create_automation_dashboard() {
    print_info "Создание дашборда автоматизации для Grafana..."
    
    cat > /opt/monitoring/grafana/dashboards/automation-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "WordPress Automation Dashboard",
    "tags": ["automation", "wordpress"],
    "timezone": "browser",
    "panels": [
      {
        "title": "API Status",
        "type": "stat",
        "targets": [
          {
            "expr": "automation_api_status",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {"value": 0, "text": "Down"},
              {"value": 1, "text": "Up"}
            ],
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "green", "value": 1}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
      },
      {
        "title": "Queue Size",
        "type": "stat",
        "targets": [
          {
            "expr": "automation_queue_size",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 10},
                {"color": "red", "value": 50}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
      },
      {
        "title": "Total Tasks",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(automation_tasks_total)",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
      },
      {
        "title": "API Requests Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(automation_api_requests_total[5m])",
            "refId": "A",
            "legendFormat": "{{endpoint}} {{method}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "title": "Content Generation Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(automation_content_generation_seconds_bucket[5m]))",
            "refId": "A",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(automation_content_generation_seconds_bucket[5m]))",
            "refId": "B",
            "legendFormat": "50th percentile"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF

    print_success "Дашборд автоматизации создан"
}

# Основная функция
main() {
    print_info "=== Настройка системы автоматизации контента ==="
    
    install_task_scheduler
    create_automation_api
    create_task_scheduler
    create_wordpress_plugin
    create_systemd_services
    setup_automation_monitoring
    create_automation_dashboard
    
    print_success "Система автоматизации контента настроена!"
    print_info "Доступные сервисы:"
    print_info "- API автоматизации: http://localhost:8000"
    print_info "- Документация API: http://localhost:8000/docs"
    print_info "- Метрики: http://localhost:9105/metrics"
    print_info "- WordPress панель: https://${DOMAIN_NAME}/wp-admin"
    print_info ""
    print_info "Команды управления:"
    print_info "- Статус сервисов: systemctl status automation-*"
    print_info "- Логи: journalctl -u automation-api -f"
    print_info "- Мониторинг очереди: redis-cli monitor"
}

main "$@"