"""Endpoints of the case archive: followed variants, ACMG history and alerts."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas
from app.api import deps
from app.api.deps import current_active_user
from app.casearchive import service
from app.models.bookmark import Bookmark
from app.models.casearchive import (
    AcmgAssessment,
    CaseVariant,
    DataVersion,
    ReanalysisAlert,
    ReanalysisRun,
)
from app.models.caseinfo import CaseInfo
from app.models.user import User

router = APIRouter()


async def _get_case_or_403(
    db: AsyncSession, case_id: uuid.UUID, user: User, *, superuser_ok: bool = False
) -> CaseInfo:
    case = (
        await db.execute(select(CaseInfo).where(CaseInfo.id == case_id))
    ).scalars().first()
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")
    if case.user != user.id and not (superuser_ok and user.is_superuser):
        raise HTTPException(status_code=403, detail="Not enough permissions")
    return case


async def _latest_assessment(db: AsyncSession, variant_id: uuid.UUID):
    return (
        await db.execute(
            select(AcmgAssessment)
            .where(AcmgAssessment.case_variant == variant_id)
            .order_by(AcmgAssessment.created_at.desc())
            .limit(1)
        )
    ).scalars().first()


def _variant_read(variant: CaseVariant, latest) -> schemas.CaseVariantRead:
    out = schemas.CaseVariantRead.model_validate(variant)
    out.latest = (
        schemas.AcmgAssessmentRead.model_validate(latest) if latest is not None else None
    )
    return out


@router.get("/{case_id}/variants", response_model=list[schemas.CaseVariantRead])
async def list_case_variants(
    case_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """List the variants followed in a case, with their latest classification."""
    await _get_case_or_403(db, case_id, user)
    variants = (
        await db.execute(
            select(CaseVariant)
            .where(CaseVariant.case_info == case_id)
            .order_by(CaseVariant.added_at.desc())
        )
    ).scalars().all()
    out = []
    for variant in variants:
        out.append(_variant_read(variant, await _latest_assessment(db, variant.id)))
    return out


@router.post("/{case_id}/variants", response_model=schemas.CaseVariantRead, status_code=201)
async def add_case_variant(
    case_id: uuid.UUID,
    payload: schemas.CaseVariantCreate,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Follow a variant in a case."""
    case = await _get_case_or_403(db, case_id, user)
    exists = (
        await db.execute(
            select(CaseVariant).where(
                CaseVariant.case_info == case_id,
                CaseVariant.obj_type == payload.obj_type.value,
                CaseVariant.obj_id == payload.obj_id,
            )
        )
    ).scalars().first()
    if exists is not None:
        raise HTTPException(status_code=409, detail="Variant already followed in this case")

    build = payload.genome_build or _build_from_obj_id(payload.obj_id) or "grch37"
    bookmark = (
        await db.execute(
            select(Bookmark).where(
                Bookmark.user == user.id,
                Bookmark.obj_type == payload.obj_type.value,
                Bookmark.obj_id == payload.obj_id,
            )
        )
    ).scalars().first()

    variant = CaseVariant(
        case_info=case.id,
        user=user.id,
        bookmark=bookmark.id if bookmark is not None else None,
        obj_type=payload.obj_type.value,
        obj_id=payload.obj_id,
        genome_build=build,
        gene_symbol=payload.gene_symbol,
        hgnc_id=payload.hgnc_id,
        transcript=payload.transcript,
        label=payload.label,
        notes=payload.notes,
        follow=payload.follow,
        added_at=datetime.utcnow(),
    )
    db.add(variant)
    await db.commit()
    await db.refresh(variant)
    return _variant_read(variant, None)


def _build_from_obj_id(obj_id: str) -> str | None:
    lowered = obj_id.lower()
    if lowered.startswith("grch37"):
        return "grch37"
    if lowered.startswith("grch38"):
        return "grch38"
    return None


@router.post(
    "/{case_id}/variants/import-bookmarks",
    response_model=list[schemas.CaseVariantRead],
)
async def import_bookmarks(
    case_id: uuid.UUID,
    payload: schemas.CaseVariantImport,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Follow every matching bookmark of the current user in this case."""
    case = await _get_case_or_403(db, case_id, user)
    types = [t.value for t in payload.obj_types]
    bookmarks = (
        await db.execute(
            select(Bookmark).where(Bookmark.user == user.id, Bookmark.obj_type.in_(types))
        )
    ).scalars().all()

    existing = {
        (v.obj_type, v.obj_id): v
        for v in (
            await db.execute(select(CaseVariant).where(CaseVariant.case_info == case_id))
        ).scalars().all()
    }
    out = []
    for bookmark in bookmarks:
        obj_type = (
            bookmark.obj_type.value
            if hasattr(bookmark.obj_type, "value")
            else str(bookmark.obj_type)
        )
        key = (obj_type, bookmark.obj_id)
        if key in existing:
            # Already followed: never insert a duplicate (uq_case_variant), just
            # re-enable the follow flag when overwrite was requested.
            if payload.overwrite:
                existing[key].follow = True
                out.append(existing[key])
            continue
        variant = CaseVariant(
            case_info=case.id,
            user=user.id,
            bookmark=bookmark.id,
            obj_type=obj_type,
            obj_id=bookmark.obj_id,
            genome_build=_build_from_obj_id(bookmark.obj_id) or "grch37",
            follow=True,
            added_at=datetime.utcnow(),
        )
        db.add(variant)
        out.append(variant)
        existing[key] = variant
    await db.commit()
    return [_variant_read(v, None) for v in out]


@router.patch("/{case_id}/variants/{variant_id}", response_model=schemas.CaseVariantRead)
async def update_case_variant(
    case_id: uuid.UUID,
    variant_id: uuid.UUID,
    payload: schemas.CaseVariantUpdate,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Edit a followed variant (including whether it is re-analysed)."""
    await _get_case_or_403(db, case_id, user)
    variant = (
        await db.execute(
            select(CaseVariant).where(
                CaseVariant.id == variant_id, CaseVariant.case_info == case_id
            )
        )
    ).scalars().first()
    if variant is None:
        raise HTTPException(status_code=404, detail="Case variant not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(variant, field, value)
    await db.commit()
    await db.refresh(variant)
    return _variant_read(variant, await _latest_assessment(db, variant.id))


@router.delete("/{case_id}/variants/{variant_id}", status_code=204)
async def delete_case_variant(
    case_id: uuid.UUID,
    variant_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Stop following a variant.

    The ACMG history is kept (assessments cascade from the variant), so this
    removes the history too; use ``PATCH follow=false`` to keep it.
    """
    await _get_case_or_403(db, case_id, user)
    await db.execute(
        delete(CaseVariant).where(
            CaseVariant.id == variant_id, CaseVariant.case_info == case_id
        )
    )
    await db.commit()


@router.get(
    "/{case_id}/variants/{variant_id}/history",
    response_model=list[schemas.AcmgAssessmentRead],
)
async def variant_history(
    case_id: uuid.UUID,
    variant_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Full ACMG classification history of a followed variant."""
    await _get_case_or_403(db, case_id, user)
    rows = (
        await db.execute(
            select(AcmgAssessment)
            .where(AcmgAssessment.case_variant == variant_id)
            .order_by(AcmgAssessment.created_at.desc())
        )
    ).scalars().all()
    return [schemas.AcmgAssessmentRead.model_validate(r) for r in rows]


@router.post(
    "/{case_id}/variants/{variant_id}/reanalyze",
    response_model=schemas.AcmgAssessmentRead | None,
)
async def reanalyze_variant(
    case_id: uuid.UUID,
    variant_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Re-run the ACMG classification of one variant right now."""
    await _get_case_or_403(db, case_id, user)
    variant = (
        await db.execute(
            select(CaseVariant).where(
                CaseVariant.id == variant_id, CaseVariant.case_info == case_id
            )
        )
    ).scalars().first()
    if variant is None:
        raise HTTPException(status_code=404, detail="Case variant not found")

    import httpx

    async with httpx.AsyncClient() as client:
        versions = await service.fetch_data_versions(client)
        assessment, _changed = await service.assess_variant(
            db, client, variant, None, service.signature_of(versions), versions
        )
    await db.commit()
    if assessment is None:
        raise HTTPException(
            status_code=502, detail="The ACMG service did not return a classification"
        )
    return schemas.AcmgAssessmentRead.model_validate(assessment)


@router.post("/{case_id}/reanalyze", response_model=schemas.ReanalysisRunRead)
async def reanalyze_case(
    case_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Re-run the ACMG classification of every followed variant of a case."""
    await _get_case_or_403(db, case_id, user)
    run = await service.run_reanalysis(
        db, trigger="manual", user_id=user.id, case_ids=[case_id]
    )
    return schemas.ReanalysisRunRead.model_validate(run)


@router.get("/{case_id}/alerts", response_model=list[schemas.ReanalysisAlertRead])
async def list_alerts(
    case_id: uuid.UUID,
    only_unread: bool = Query(False),
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Alerts raised when a classification in this case changed."""
    await _get_case_or_403(db, case_id, user)
    stmt = select(ReanalysisAlert).where(ReanalysisAlert.case_info == case_id)
    if only_unread:
        stmt = stmt.where(ReanalysisAlert.read_at.is_(None))
    rows = (
        await db.execute(stmt.order_by(ReanalysisAlert.created_at.desc()))
    ).scalars().all()
    return [schemas.ReanalysisAlertRead.model_validate(r) for r in rows]


@router.post("/{case_id}/alerts/{alert_id}/read", response_model=schemas.ReanalysisAlertRead)
async def mark_alert_read(
    case_id: uuid.UUID,
    alert_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Mark an alert as read."""
    await _get_case_or_403(db, case_id, user)
    alert = (
        await db.execute(
            select(ReanalysisAlert).where(
                ReanalysisAlert.id == alert_id, ReanalysisAlert.case_info == case_id
            )
        )
    ).scalars().first()
    if alert is None:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.read_at is None:
        alert.read_at = datetime.utcnow()
        await db.commit()
        await db.refresh(alert)
    return schemas.ReanalysisAlertRead.model_validate(alert)


@router.get("/{case_id}/summary", response_model=schemas.CaseArchiveSummary)
async def case_summary(
    case_id: uuid.UUID,
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Counters for the case view: variants, followed, unread alerts, last run."""
    await _get_case_or_403(db, case_id, user)
    variants = (
        await db.execute(select(CaseVariant).where(CaseVariant.case_info == case_id))
    ).scalars().all()
    by_class: dict[str, int] = {}
    for variant in variants:
        latest = await _latest_assessment(db, variant.id)
        if latest is not None:
            by_class[latest.acmg_class] = by_class.get(latest.acmg_class, 0) + 1

    n_alerts = (
        await db.execute(
            select(func.count(ReanalysisAlert.id)).where(
                ReanalysisAlert.case_info == case_id, ReanalysisAlert.read_at.is_(None)
            )
        )
    ).scalar_one()
    last_run = (
        await db.execute(
            select(ReanalysisRun).order_by(ReanalysisRun.started_at.desc()).limit(1)
        )
    ).scalars().first()
    return schemas.CaseArchiveSummary(
        n_variants=len(variants),
        n_followed=sum(1 for v in variants if v.follow),
        n_alerts_unread=n_alerts,
        last_run=(
            schemas.ReanalysisRunRead.model_validate(last_run) if last_run is not None else None
        ),
        by_class=by_class,
    )


@router.get("/data-versions", response_model=list[schemas.DataVersionRead])
async def list_data_versions(
    db: AsyncSession = Depends(deps.get_db),
    user: User = Depends(current_active_user),
):
    """Versions of the reference databases seen by the instance."""
    rows = (
        await db.execute(
            select(DataVersion).order_by(DataVersion.source, DataVersion.first_seen_at.desc())
        )
    ).scalars().all()
    return [schemas.DataVersionRead.model_validate(r) for r in rows]
