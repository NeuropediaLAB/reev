"""Celery tasks for the case archive (periodic re-analysis, data monitoring)."""

import asyncio
import logging

from celery.schedules import crontab
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.celery_app import celery_app
from app.core.config import settings
from app.db.session import json_serializer

logger = logging.getLogger(__name__)


def _run_async(coro_factory):
    """Run an async function with its own engine inside a fresh event loop."""

    async def inner():
        engine = create_async_engine(
            str(settings.SQLALCHEMY_DATABASE_URI),
            pool_pre_ping=True,
            json_serializer=json_serializer,
        )
        try:
            return await coro_factory(engine)
        finally:
            await engine.dispose()

    return asyncio.run(inner())


@celery_app.task(acks_late=True)
def poll_data_versions():
    """Record the versions of the reference databases and re-analyse on change."""
    from sqlalchemy.ext.asyncio import async_sessionmaker

    from app.casearchive import service

    logger.info("poll_data_versions - START")

    async def work(engine):
        factory = async_sessionmaker(engine, expire_on_commit=False)
        async with factory() as session:
            out = await service.poll_and_maybe_reanalyze(session)
            await session.commit()
            return out

    try:
        out = _run_async(work)
        logger.info("poll_data_versions - result: %s", out)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("Caught exception of type %s: %s", type(e), e)

    logger.info("poll_data_versions - END")


@celery_app.task(acks_late=True)
def reanalyze_all_cases():
    """Re-analyse every followed variant of every case."""
    from sqlalchemy.ext.asyncio import async_sessionmaker

    from app.casearchive import service

    logger.info("reanalyze_all_cases - START")

    async def work(engine):
        factory = async_sessionmaker(engine, expire_on_commit=False)
        async with factory() as session:
            run = await service.run_reanalysis(session, trigger="scheduled")
            await session.commit()
            return {"run": str(run.id), "status": run.status}

    try:
        out = _run_async(work)
        logger.info("reanalyze_all_cases - result: %s", out)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("Caught exception of type %s: %s", type(e), e)

    logger.info("reanalyze_all_cases - END")


@celery_app.on_after_configure.connect
def setup_casearchive_periodic_tasks(sender, **kwargs):
    """Register the periodic tasks of the case archive."""
    _ = kwargs
    if not settings.CASEARCHIVE_REANALYSIS_ENABLED:
        return

    sender.add_periodic_task(
        crontab(minute=17, hour="*/6"),
        poll_data_versions.s(),
        name="poll reference data versions",
    )
    sender.add_periodic_task(
        crontab(minute=41, hour=3, day_of_week=settings.CASEARCHIVE_REANALYSIS_WEEKDAY),
        reanalyze_all_cases.s(),
        name="weekly re-analysis of followed variants",
    )
