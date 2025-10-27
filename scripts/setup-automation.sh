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
from datetime import datetime
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
    # Генерация контента с добавлением информации о микроразметке
    microdata_info = """
    <h3>Что такое микроразметка и почему она важна для SEO</h3>
    <p>Микроразметка – это специальный формат разметки на сайте, который помогает поисковым системам лучше понять содержание страниц. Вместо того чтобы гадать, что изображено на странице, поисковый робот получает структурированные данные о странице: что является заголовком статьи, где указаны автор и дата, какие элементы являются отзывами, рейтингами, вопросами и ответами и т.д.</p>
    
    <p>Проще говоря, микроразметка – это язык, на котором сайт общается с поисковиком, описывая свою информацию более понятно и точно. Для SEO это имеет большое значение.</p>
    
    <p>Во-первых, правильно добавленная микроразметка делает ваш сайт кандидатом на расширенные результаты. Такие сниппеты заметнее и привлекательнее для пользователей, что повышает CTR. Наличие разметки не гарантирует попадание в расширенный сниппет, но увеличивает эту вероятность.</p>
    
    <p>Помимо этого, структурированные данные помогают Google более точно проиндексировать и понять контекст страницы. Это косвенно влияет на ранжирование: если поисковик лучше понимает контент, ему проще сопоставить его с релевантными запросами.</p>
    
    <h4>JSON-LD – рекомендованный формат</h4>
    <p>Google поддерживает три основных формата разметки структурированных данных: Microdata, RDFa и JSON-LD. Мы рассматриваем только JSON-LD, так как это рекомендованный способ от Google.</p>
    
    <p>JSON-LD представляет данные в формате JSON, которые вставляются в код страницы внутри тега &lt;script type="application/ld+json"&gt;. JSON-LD не требует изменять существующий HTML-код – вы просто вставляете отдельный блок со структурированными данными.</p>
    """
    
    content = f"""
    <h2>Введение в {topic}</h2>
    <p>В этой статье мы рассмотрим важные аспекты {topic} и покажем, как правильно использовать микроразметку для улучшения SEO.</p>
    
    <h3>Ключевые моменты</h3>
    <ul>
    {"".join([f"<li>Важность {keyword} в контексте SEO-оптимизации</li>" for keyword in keywords])}
    </ul>
    
    {microdata_info}
    
    <h3>Практические рекомендации</h3>
    <p>Для эффективного использования {topic} рекомендуется:</p>
    <ul>
        <li>Внедрить структурированные данные JSON-LD</li>
        <li>Использовать FAQ-разметку для часто задаваемых вопросов</li>
        <li>Добавить схему статьи (Article Schema)</li>
        <li>Настроить хлебные крошки (Breadcrumbs)</li>
        <li>Проверить разметку через Google Rich Results Test</li>
    </ul>
    
    <h3>Заключение</h3>
    <p>Понимание {topic} и правильное использование микроразметки критически важно для современного SEO. Структурированные данные помогают поисковым системам лучше понимать ваш контент и могут значительно улучшить видимость в поисковой выдаче.</p>
    """
    
    return {
        "title": f"Полное руководство по {topic}",
        "content": content,
        "excerpt": f"Изучите все аспекты {topic} в нашем подробном руководстве."
    }

@celery_app.task
def optimize_seo_task(post_id: int, focus_keyword: str):
    """Задача SEO-оптимизации с генерацией микроразметки"""
    
    # Генерация базовой Article Schema
    article_schema = {
        "@context": "https://schema.org",
        "@type": "Article",
        "headline": f"{focus_keyword} - Полное руководство",
        "description": f"Подробное руководство по {focus_keyword} с практическими советами и рекомендациями",
        "author": {
            "@type": "Person",
            "name": "Редакция сайта"
        },
        "publisher": {
            "@type": "Organization",
            "name": os.getenv('WP_TITLE', 'My WordPress Site'),
            "logo": {
                "@type": "ImageObject",
                "url": f"https://{os.getenv('DOMAIN_NAME')}/wp-content/uploads/logo.png"
            }
        },
        "datePublished": datetime.now().isoformat(),
        "dateModified": datetime.now().isoformat(),
        "mainEntityOfPage": {
            "@type": "WebPage",
            "@id": f"https://{os.getenv('DOMAIN_NAME')}/post-{post_id}/"
        }
    }
    
    # FAQ Schema для часто задаваемых вопросов
    faq_schema = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [
            {
                "@type": "Question",
                "name": f"Что такое {focus_keyword}?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": f"{focus_keyword} - это важный аспект современного интернет-маркетинга, который требует комплексного подхода и глубокого понимания."
                }
            },
            {
                "@type": "Question", 
                "name": f"Как использовать {focus_keyword} для SEO?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": f"Для эффективного использования {focus_keyword} необходимо применять структурированные данные, оптимизировать контент и следить за техническими аспектами сайта."
                }
            },
            {
                "@type": "Question",
                "name": "Какие преимущества дает микроразметка?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": "Микроразметка помогает поисковым системам лучше понимать контент, увеличивает шансы на расширенные сниппеты и улучшает CTR в поисковой выдаче."
                }
            }
        ]
    }
    
    # BreadcrumbList Schema
    breadcrumb_schema = {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {
                "@type": "ListItem",
                "position": 1,
                "name": "Главная",
                "item": f"https://{os.getenv('DOMAIN_NAME')}/"
            },
            {
                "@type": "ListItem", 
                "position": 2,
                "name": "Статьи",
                "item": f"https://{os.getenv('DOMAIN_NAME')}/articles/"
            },
            {
                "@type": "ListItem",
                "position": 3,
                "name": f"{focus_keyword}",
                "item": f"https://{os.getenv('DOMAIN_NAME')}/post-{post_id}/"
            }
        ]
    }
    
    seo_data = {
        "meta": {
            "focus_keyword": focus_keyword,
            "meta_description": f"Узнайте всё о {focus_keyword}. Практические советы, рекомендации экспертов и полное руководство по применению микроразметки для SEO.",
            "meta_title": f"{focus_keyword} - Полное руководство с микроразметкой"
        },
        "structured_data": {
            "article": article_schema,
            "faq": faq_schema,
            "breadcrumb": breadcrumb_schema
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

class SchemaType(BaseModel):
    schema_type: str  # article, game, review, faq, organization
    title: str
    description: Optional[str] = None
    keywords: Optional[List[str]] = []
    rating: Optional[float] = None
    review_body: Optional[str] = None
    game_genre: Optional[str] = None
    developer: Optional[str] = None

@app.post("/schema/generate")
async def generate_schema(schema_request: SchemaType):
    """Генерация специализированных JSON-LD схем"""
    
    schemas = {}
    
    if schema_request.schema_type == "game":
        # VideoGame Schema для игр
        schemas["game"] = {
            "@context": "https://schema.org",
            "@type": "VideoGame",
            "name": schema_request.title,
            "description": schema_request.description,
            "genre": schema_request.game_genre or "Casino Game",
            "author": {
                "@type": "Organization",
                "name": schema_request.developer or "Game Developer"
            },
            "operatingSystem": "Web Browser",
            "applicationCategory": "Game",
            "aggregateRating": {
                "@type": "AggregateRating",
                "ratingValue": schema_request.rating or 4.5,
                "ratingCount": 100,
                "bestRating": 5,
                "worstRating": 1
            } if schema_request.rating else None
        }
        
    elif schema_request.schema_type == "review":
        # Review Schema для обзоров
        schemas["review"] = {
            "@context": "https://schema.org",
            "@type": "Review",
            "itemReviewed": {
                "@type": "Thing",
                "name": schema_request.title
            },
            "reviewRating": {
                "@type": "Rating",
                "ratingValue": schema_request.rating or 4.5,
                "bestRating": 5,
                "worstRating": 1
            },
            "author": {
                "@type": "Person",
                "name": "Редакция сайта"
            },
            "reviewBody": schema_request.review_body or f"Подробный обзор {schema_request.title}",
            "datePublished": datetime.now().isoformat()
        }
        
    elif schema_request.schema_type == "organization":
        # Organization Schema для компаний/казино
        schemas["organization"] = {
            "@context": "https://schema.org",
            "@type": "Organization",
            "name": schema_request.title,
            "description": schema_request.description,
            "aggregateRating": {
                "@type": "AggregateRating",
                "ratingValue": schema_request.rating or 4.5,
                "ratingCount": 50,
                "bestRating": 5,
                "worstRating": 1
            } if schema_request.rating else None
        }
    
    # Всегда добавляем FAQ с информацией о микроразметке
    schemas["faq"] = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [
            {
                "@type": "Question",
                "name": "Что такое микроразметка и зачем она нужна?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": "Микроразметка помогает поисковым системам лучше понимать содержание страниц и может улучшить отображение в результатах поиска через расширенные сниппеты."
                }
            },
            {
                "@type": "Question",
                "name": "Как проверить корректность микроразметки?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": "Используйте инструмент Google Rich Results Test для проверки структурированных данных на наличие ошибок и соответствие стандартам."
                }
            },
            {
                "@type": "Question",
                "name": f"Что нужно знать о {schema_request.title}?",
                "acceptedAnswer": {
                    "@type": "Answer",
                    "text": f"{schema_request.description or 'Полная информация и практические рекомендации по использованию.'}"
                }
            }
        ]
    }
    
    return {
        "success": True,
        "schemas": schemas,
        "instructions": {
            "implementation": "Добавьте сгенерированные схемы в раздел <head> страницы внутри тегов <script type='application/ld+json'>",
            "validation": "Проверьте схемы через https://search.google.com/test/rich-results",
            "seo_tips": [
                "Убедитесь, что данные в схемах соответствуют контенту на странице",
                "Не используйте одинаковые схемы на разных типах контента",
                "Регулярно проверяйте отчеты в Google Search Console"
            ]
        }
    }

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
import os
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
        """Автоматическая генерация контента с микроразметкой"""
        topics = [
            "микроразметка Schema.org",
            "JSON-LD для SEO", 
            "структурированные данные Google",
            "расширенные сниппеты",
            "FAQ Schema разметка",
            "Article Schema оптимизация"
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
        
    def validate_structured_data(self):
        """Проверка структурированных данных на сайте"""
        logging.info("Проверка микроразметки на страницах сайта")
        
        try:
            # Получение списка страниц WordPress
            wp_api_url = f"https://{os.getenv('DOMAIN_NAME', 'localhost')}/wp-json/wp/v2/posts"
            response = requests.get(wp_api_url, params={'per_page': 10})
            
            if response.status_code == 200:
                posts = response.json()
                for post in posts:
                    post_url = post.get('link', '')
                    if post_url:
                        # Здесь можно добавить проверку через Google Rich Results Test API
                        logging.info(f"Проверка микроразметки для: {post_url}")
                        
        except Exception as e:
            logging.error(f"Ошибка при проверке структурированных данных: {e}")
            
    def generate_microdata_report(self):
        """Генерация отчета по микроразметке"""
        logging.info("Генерация отчета по использованию микроразметки")
        
        report_data = {
            "timestamp": datetime.now().isoformat(),
            "domain": os.getenv('DOMAIN_NAME', 'localhost'),
            "schemas_found": {
                "article": 0,
                "faq": 0,
                "breadcrumb": 0,
                "review": 0,
                "organization": 0
            },
            "recommendations": [
                "Добавьте FAQ Schema для улучшения расширенных сниппетов",
                "Проверьте Article Schema на всех статьях блога",
                "Внедрите BreadcrumbList для улучшения навигации",
                "Добавьте Review Schema для страниц с отзывами"
            ]
        }
        
        # Сохранение отчета
        with open('/var/log/microdata-report.json', 'w', encoding='utf-8') as f:
            json.dump(report_data, f, ensure_ascii=False, indent=2)
            
        logging.info("Отчет по микроразметке сохранен в /var/log/microdata-report.json")

def main():
    scheduler = AutomationScheduler()
    
    # Планирование задач
    schedule.every().day.at("09:00").do(scheduler.auto_generate_content)
    schedule.every().sunday.at("02:00").do(scheduler.cleanup_drafts)
    schedule.every().day.at("03:00").do(scheduler.backup_content)
    schedule.every().hour.do(scheduler.update_seo_analytics)
    schedule.every().day.at("11:00").do(scheduler.validate_structured_data)
    schedule.every().monday.at("08:00").do(scheduler.generate_microdata_report)
    
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
         add_action('wp_head', array($this, 'output_structured_data'));
         add_action('template_redirect', array($this, 'setup_content_filters'));
         add_action('add_meta_boxes', array($this, 'add_schema_info_meta_box'));
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
         
         // Автоматическая генерация JSON-LD схем
         $this->generate_structured_data($post_id);
     }
     
     private function generate_structured_data($post_id) {
         $post = get_post($post_id);
         $focus_keyword = get_post_meta($post_id, '_automation_focus_keyword', true);
         
         if (empty($focus_keyword)) {
             return;
         }
         
         // Article Schema
         $article_schema = array(
             '@context' => 'https://schema.org',
             '@type' => 'Article',
             'headline' => $post->post_title,
             'description' => $post->post_excerpt ?: wp_trim_words($post->post_content, 20),
             'author' => array(
                 '@type' => 'Person',
                 'name' => get_the_author_meta('display_name', $post->post_author)
             ),
             'publisher' => array(
                 '@type' => 'Organization',
                 'name' => get_bloginfo('name'),
                 'logo' => array(
                     '@type' => 'ImageObject',
                     'url' => get_site_url() . '/wp-content/uploads/logo.png'
                 )
             ),
             'datePublished' => get_the_date('c', $post_id),
             'dateModified' => get_the_modified_date('c', $post_id),
             'mainEntityOfPage' => array(
                 '@type' => 'WebPage',
                 '@id' => get_permalink($post_id)
             )
         );
         
         // FAQ Schema с информацией о микроразметке
         $faq_schema = array(
             '@context' => 'https://schema.org',
             '@type' => 'FAQPage',
             'mainEntity' => array(
                 array(
                     '@type' => 'Question',
                     'name' => 'Что такое микроразметка и почему она важна для SEO?',
                     'acceptedAnswer' => array(
                         '@type' => 'Answer',
                         'text' => 'Микроразметка – это специальный формат разметки на сайте, который помогает поисковым системам лучше понять содержание страниц. Она увеличивает шансы на получение расширенных сниппетов и улучшает видимость в поисковой выдаче.'
                     )
                 ),
                 array(
                     '@type' => 'Question',
                     'name' => 'Какие типы микроразметки наиболее важны?',
                     'acceptedAnswer' => array(
                         '@type' => 'Answer',
                         'text' => 'Наиболее важными являются схемы Article (для статей), FAQ (для вопросов-ответов), BreadcrumbList (для навигации), Review (для отзывов) и Organization (для информации о компании).'
                     )
                 ),
                 array(
                     '@type' => 'Question',
                     'name' => 'Как проверить правильность микроразметки?',
                     'acceptedAnswer' => array(
                         '@type' => 'Answer',
                         'text' => 'Используйте инструмент Google Rich Results Test (search.google.com/test/rich-results) для проверки структурированных данных и выявления возможных ошибок.'
                     )
                 )
             )
         );
         
         // BreadcrumbList Schema
         $breadcrumb_schema = array(
             '@context' => 'https://schema.org',
             '@type' => 'BreadcrumbList',
             'itemListElement' => array(
                 array(
                     '@type' => 'ListItem',
                     'position' => 1,
                     'name' => 'Главная',
                     'item' => home_url()
                 ),
                 array(
                     '@type' => 'ListItem',
                     'position' => 2,
                     'name' => 'Статьи',
                     'item' => home_url('/articles/')
                 ),
                 array(
                     '@type' => 'ListItem',
                     'position' => 3,
                     'name' => $post->post_title,
                     'item' => get_permalink($post_id)
                 )
             )
         );
         
         // Сохранение схем в метаполя
         update_post_meta($post_id, '_automation_article_schema', wp_json_encode($article_schema));
         update_post_meta($post_id, '_automation_faq_schema', wp_json_encode($faq_schema));
         update_post_meta($post_id, '_automation_breadcrumb_schema', wp_json_encode($breadcrumb_schema));
     }
     
     public function output_structured_data() {
         if (!is_single()) {
             return;
         }
         
         global $post;
         
         $article_schema = get_post_meta($post->ID, '_automation_article_schema', true);
         $faq_schema = get_post_meta($post->ID, '_automation_faq_schema', true);
         $breadcrumb_schema = get_post_meta($post->ID, '_automation_breadcrumb_schema', true);
         
         if ($article_schema) {
             echo '<script type="application/ld+json">' . $article_schema . '</script>' . PHP_EOL;
         }
         
         if ($faq_schema) {
             echo '<script type="application/ld+json">' . $faq_schema . '</script>' . PHP_EOL;
         }
         
         if ($breadcrumb_schema) {
             echo '<script type="application/ld+json">' . $breadcrumb_schema . '</script>' . PHP_EOL;
         }
         
                   // Добавление информации о микроразметке в контент
          add_filter('the_content', array($this, 'add_microdata_info_to_content'));
      }
      
      public function setup_content_filters() {
          if (is_single()) {
              add_filter('the_content', array($this, 'add_microdata_info_to_content'));
          }
      }
      
      public function add_microdata_info_to_content($content) {
          if (!is_single() || !in_the_loop() || !is_main_query()) {
              return $content;
          }
          
          global $post;
          $focus_keyword = get_post_meta($post->ID, '_automation_focus_keyword', true);
          
          if (empty($focus_keyword)) {
              return $content;
          }
          
          $microdata_info = '
          <div class="microdata-info" style="background: #f8f9fa; border-left: 4px solid #007cba; padding: 20px; margin: 20px 0; border-radius: 5px;">
              <h3 style="color: #1e1e1e; margin-top: 0;">💡 Что такое микроразметка и почему она важна для SEO</h3>
              
              <p><strong>Микроразметка</strong> – это специальный формат разметки на сайте, который помогает поисковым системам лучше понять содержание страниц. Вместо того чтобы гадать, что изображено на странице, поисковый робот получает структурированные данные о странице: что является заголовком статьи, где указаны автор и дата, какие элементы являются отзывами, рейтингами, вопросами и ответами и т.д.</p>
              
              <p>Проще говоря, микроразметка – это язык, на котором сайт общается с поисковиком, описывая свою информацию более понятно и точно. <strong>Для SEO это имеет большое значение.</strong></p>
              
              <h4 style="color: #1e1e1e;">🎯 Преимущества микроразметки:</h4>
              <ul style="margin-left: 20px;">
                  <li><strong>Расширенные сниппеты</strong> – увеличивают CTR и привлекают больше кликов</li>
                  <li><strong>Лучшее понимание контента</strong> – поисковики точнее индексируют страницы</li>
                  <li><strong>Улучшение ранжирования</strong> – косвенно влияет на позиции в выдаче</li>
                  <li><strong>Повышение доверия</strong> – структурированные данные создают более профессиональный вид</li>
              </ul>
              
              <h4 style="color: #1e1e1e;">📋 JSON-LD – рекомендованный формат</h4>
              <p>Google поддерживает три основных формата разметки: Microdata, RDFa и <strong>JSON-LD</strong>. Мы используем именно JSON-LD, так как это рекомендованный способ от Google. JSON-LD не требует изменять существующий HTML-код – достаточно вставить отдельный блок со структурированными данными.</p>
              
              <div style="background: #fff; padding: 15px; border-radius: 3px; margin: 15px 0;">
                  <h5 style="margin-top: 0; color: #1e1e1e;">🔧 Основные типы схем на этой странице:</h5>
                  <ul style="margin-left: 20px; margin-bottom: 0;">
                      <li><strong>Article Schema</strong> – описывает статью с автором, датой публикации и основным контентом</li>
                      <li><strong>FAQ Schema</strong> – структурирует часто задаваемые вопросы для расширенных сниппетов</li>
                      <li><strong>BreadcrumbList</strong> – улучшает навигацию и отображение в поиске</li>
                  </ul>
              </div>
              
              <p style="margin-bottom: 0;"><strong>💡 Совет:</strong> Проверить корректность микроразметки можно через <a href="https://search.google.com/test/rich-results" target="_blank" rel="noopener">Google Rich Results Test</a></p>
          </div>';
          
          // Добавляем информацию после первого абзаца или в конец контента
          $paragraphs = explode('</p>', $content);
          if (count($paragraphs) > 1) {
              // Вставляем после первого абзаца
              $paragraphs[0] .= '</p>' . $microdata_info;
              $content = implode('</p>', $paragraphs);
          } else {
              // Добавляем в конец
              $content .= $microdata_info;
          }
          
          return $content;
      }
      
      // Добавление информации о применяемых схемах в админку
      public function add_schema_info_meta_box() {
          add_meta_box(
              'automation-schema-info',
              'Применённые JSON-LD схемы',
              array($this, 'schema_info_meta_box_callback'),
              'post',
              'side',
              'low'
          );
      }
      
      public function schema_info_meta_box_callback($post) {
          $article_schema = get_post_meta($post->ID, '_automation_article_schema', true);
          $faq_schema = get_post_meta($post->ID, '_automation_faq_schema', true);
          $breadcrumb_schema = get_post_meta($post->ID, '_automation_breadcrumb_schema', true);
          
          echo '<div style="font-size: 13px;">';
          echo '<p><strong>Активные схемы:</strong></p>';
          echo '<ul style="margin-left: 15px;">';
          
          if ($article_schema) {
              echo '<li>✅ Article Schema</li>';
          }
          if ($faq_schema) {
              echo '<li>✅ FAQ Schema</li>';
          }
          if ($breadcrumb_schema) {
              echo '<li>✅ BreadcrumbList Schema</li>';
          }
          
          if (!$article_schema && !$faq_schema && !$breadcrumb_schema) {
              echo '<li>❌ Схемы не настроены</li>';
              echo '</ul>';
              echo '<p style="color: #d63638;">Добавьте фокусное ключевое слово и сохраните пост для автоматической генерации схем.</p>';
          } else {
              echo '</ul>';
              echo '<p style="color: #00a32a;">Микроразметка настроена корректно!</p>';
              echo '<p><a href="https://search.google.com/test/rich-results?url=' . urlencode(get_permalink($post->ID)) . '" target="_blank">🔍 Проверить в Google</a></p>';
          }
          
          echo '</div>';
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