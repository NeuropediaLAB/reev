from celery import Celery

from app.core.config import settings

celery_app = Celery("worker", broker=settings.RABBITMQ_URL)

celery_app.conf.task_routes = {
    "app.worker.*": {"queue": "main-queue"},
    # The case-archive tasks live in app.casearchive.tasks; without this they are
    # published to the default "celery" queue, which no worker consumes, so the
    # periodic reference-data polling and the weekly re-analysis were silently lost.
    "app.casearchive.tasks.*": {"queue": "main-queue"},
}
