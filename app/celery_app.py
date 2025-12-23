import os

from celery import Celery

celery_app = Celery(
    "upload_docs_service",
    broker=os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0"),
    backend=os.getenv("CELERY_RESULT_BACKEND", "redis://redis:6379/0"),
    broker_connection_retry_on_startup=True,
    include=["app.tasks"],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=30 * 60,  # 30 minutes
    task_soft_time_limit=25 * 60,  # 25 minutes
    worker_prefetch_multiplier=1,
    worker_max_tasks_per_child=1000
)

celery_app.conf.task_routes = {
    "app.tasks.process_document": {"queue": "document_processing"},
    "app.tasks.*": {"queue": "default"}
}
