"""Case archive: ACMG re-analysis and change detection.

Two entry points are used by the Celery tasks:

* :func:`poll_data_versions` — asks the local Annonars instance for the versions
  of the reference databases it serves and computes a signature.  When the
  signature changes (ClinVar, gnomAD, ... were updated), a re-analysis is
  triggered.
* :func:`run_reanalysis` — re-runs the ACMG classification that REEV already
  provides (auto-acmg, WinterVar as fallback) for every followed variant, stores
  a new :class:`~app.models.casearchive.AcmgAssessment` and raises an alert when
  the class changed.
"""

import hashlib
import json
import logging
from datetime import datetime
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.casearchive.acmg import classify, severity_for
from app.core.config import settings
from app.models.casearchive import (
    AcmgAssessment,
    CaseVariant,
    DataVersion,
    ReanalysisAlert,
    ReanalysisRun,
)

logger = logging.getLogger(__name__)

#: Version of the criteria set / rules implemented in :mod:`app.casearchive.acmg`.
ENGINE_VERSION = "reev-acmg-1"

ANNONARS_URL = getattr(settings, "ANNONARS_URL", "http://annonars:8080")
MEHARI_URL = getattr(settings, "MEHARI_URL", "http://mehari:8080")
DOTTY_URL = getattr(settings, "DOTTY_URL", "http://dotty:8080")

#: Genome releases that are watched for reference-data changes.
GENOME_RELEASES = ("grch37", "grch38")


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)


def signature_of(payload: Any) -> str:
    """Stable short hash of a reference-data description."""
    return hashlib.sha256(_canonical(payload).encode()).hexdigest()[:32]


async def fetch_data_versions(client: httpx.AsyncClient) -> dict[str, Any]:
    """Return the versions of the reference databases served by Annonars.

    ``/annos/db-info`` reports which database build is loaded for each bucket
    (clinvar, gnomad, dbnsfp, ...).  Entries that are missing are kept as
    ``None`` so that a database disappearing also changes the signature.
    """
    versions: dict[str, Any] = {}
    for release in GENOME_RELEASES:
        url = f"{ANNONARS_URL}/annos/db-info?genome_release={release}"
        try:
            resp = await client.get(url, timeout=httpx.Timeout(60.0))
            if resp.is_error:
                versions[release] = {"error": resp.status_code}
                continue
            versions[release] = resp.json()
        except Exception as e:  # noqa: BLE001 - the caller records the error
            versions[release] = {"error": str(e)}
    return versions


async def record_data_versions(
    session: AsyncSession, versions: dict[str, Any]
) -> list[DataVersion]:
    """Persist the observed versions, returning the ones that are new."""
    seen: list[DataVersion] = []
    for release, payload in versions.items():
        if not isinstance(payload, dict) or "error" in payload:
            continue
        for source, version in _flatten_versions(payload).items():
            stmt = select(DataVersion).where(
                DataVersion.source == source,
                DataVersion.version == str(version),
                DataVersion.genome_build == release,
            )
            existing = (await session.execute(stmt)).scalars().first()
            if existing is not None:
                existing.last_seen_at = datetime.utcnow()
                continue
            row = DataVersion(
                source=source,
                version=str(version),
                genome_build=release,
                payload=payload,
                first_seen_at=datetime.utcnow(),
                last_seen_at=datetime.utcnow(),
                is_current=True,
            )
            session.add(row)
            seen.append(row)
    # Mark previous versions of a source as no longer current.
    for row in seen:
        stmt = select(DataVersion).where(
            DataVersion.source == row.source,
            DataVersion.genome_build == row.genome_build,
            DataVersion.id != row.id,
        )
        for other in (await session.execute(stmt)).scalars().all():
            other.is_current = False
    await session.commit()
    return seen


def _flatten_versions(payload: dict[str, Any]) -> dict[str, Any]:
    """``{"clinvar": {"version": "..."}}`` -> ``{"clinvar": "..."}``."""
    out: dict[str, Any] = {}
    for key, value in payload.items():
        if isinstance(value, dict):
            version = value.get("version") or value.get("release") or value.get("build")
            if version is not None:
                out[key] = version
            else:
                out[key] = signature_of(value)[:12]
        elif value is not None:
            out[key] = value
    return out


async def _criteria_for_variant(
    client: httpx.AsyncClient, variant: CaseVariant
) -> tuple[dict[str, bool], str] | None:
    """Ask the ACMG service REEV already uses for the criteria of a variant."""
    from app.api.internal.endpoints.remote import _call_auto_acmg, default_acmg_rating

    if variant.obj_type != "seqvar":
        return None
    import re

    match = re.match(
        r"^(grch37|grch38)-([^-]+)-(\d+)-([CGAT]+)-([CGAT]+)$", variant.obj_id
    )
    if not match:
        return None
    build, chrom, pos, ref, alt = match.groups()
    rating = await _call_auto_acmg(client, chrom, pos, ref, alt, build)
    if rating is None:
        return None
    source = "auto-acmg"
    criteria = {**default_acmg_rating(), **rating}
    return criteria, source


async def assess_variant(
    session: AsyncSession,
    client: httpx.AsyncClient,
    variant: CaseVariant,
    run: ReanalysisRun | None,
    data_signature: str | None,
    data_versions: dict[str, Any] | None,
    raise_alerts: bool = True,
) -> tuple[AcmgAssessment | None, bool]:
    """Classify one variant and store the result, alerting on class changes.

    Returns the stored assessment (``None`` when the ACMG service gave no
    answer) and whether the ACMG class changed with respect to the previous one.
    """
    result = await _criteria_for_variant(client, variant)
    if result is None:
        logger.warning("No ACMG result for case variant %s (%s)", variant.id, variant.obj_id)
        return None, False
    criteria, source = result
    new_class, conflicting = classify(criteria)

    previous = (
        await session.execute(
            select(AcmgAssessment)
            .where(AcmgAssessment.case_variant == variant.id)
            .order_by(AcmgAssessment.created_at.desc())
            .limit(1)
        )
    ).scalars().first()

    assessment = AcmgAssessment(
        case_variant=variant.id,
        run=run.id if run is not None else None,
        acmg_class=new_class,
        criteria=criteria,
        source=source,
        engine_version=ENGINE_VERSION,
        data_signature=data_signature,
        data_versions=data_versions,
        is_conflicting=conflicting,
        created_at=datetime.utcnow(),
    )
    session.add(assessment)
    variant.last_analyzed_at = datetime.utcnow()
    await session.flush()

    changed = previous is not None and previous.acmg_class != new_class
    if raise_alerts and changed:
        assert previous is not None
        session.add(
            ReanalysisAlert(
                user=variant.user,
                case_info=variant.case_info,
                case_variant=variant.id,
                assessment=assessment.id,
                previous_assessment=previous.id,
                run=run.id if run is not None else None,
                old_class=previous.acmg_class,
                new_class=new_class,
                message=(
                    f"{variant.obj_id}: clasificación ACMG actualizada de "
                    f"«{previous.acmg_class}» a «{new_class}»."
                ),
                severity=severity_for(previous.acmg_class, new_class),
            )
        )
    return assessment, changed


async def run_reanalysis(
    session: AsyncSession,
    trigger: str = "manual",
    user_id: Any = None,
    case_ids: list[Any] | None = None,
    raise_alerts: bool = True,
) -> ReanalysisRun:
    """Re-analyse followed variants, optionally limited to some cases."""
    run = ReanalysisRun(trigger=trigger, status="running", created_by=user_id)
    session.add(run)
    await session.flush()

    async with httpx.AsyncClient() as client:
        versions = await fetch_data_versions(client)
        signature = signature_of(versions)
        run.data_signature = signature
        run.data_versions = versions

        stmt = select(CaseVariant).where(CaseVariant.follow.is_(True))
        if case_ids:
            stmt = stmt.where(CaseVariant.case_info.in_(case_ids))
        variants = (await session.execute(stmt)).scalars().all()
        run.n_variants = len(variants)

        for variant in variants:
            try:
                assessment, changed = await assess_variant(
                    session, client, variant, run, signature, versions, raise_alerts
                )
                if assessment is None:
                    run.n_failed += 1
                elif changed:
                    run.n_changed += 1
            except Exception as e:  # noqa: BLE001 - one bad variant must not abort the run
                logger.exception("Re-analysis failed for case variant %s: %s", variant.id, e)
                run.n_failed += 1

    run.status = "success" if run.n_failed == 0 else "partial"
    run.finished_at = datetime.utcnow()
    await session.commit()
    return run


async def poll_and_maybe_reanalyze(
    session: AsyncSession,
) -> dict[str, Any]:
    """Record the current reference-data versions and re-analyse when they change.

    The signature of the versions reported by Annonars is compared with the one
    of the last successful run.  A change means ClinVar/gnomAD/dbNSFP/... were
    updated, so the followed variants are re-analysed; otherwise nothing is done
    beyond updating ``last_seen_at``.
    """
    async with httpx.AsyncClient() as client:
        versions = await fetch_data_versions(client)
    signature = signature_of(versions)
    new_versions = await record_data_versions(session, versions)

    last_run = (
        await session.execute(
            select(ReanalysisRun)
            .where(ReanalysisRun.status.in_(("success", "partial")))
            .order_by(ReanalysisRun.started_at.desc())
            .limit(1)
        )
    ).scalars().first()

    if last_run is not None and last_run.data_signature == signature:
        return {
            "signature": signature,
            "changed": False,
            "new_versions": [f"{v.source}={v.version}" for v in new_versions],
        }

    run = await run_reanalysis(session, trigger="publish")
    return {
        "signature": signature,
        "changed": True,
        "new_versions": [f"{v.source}={v.version}" for v in new_versions],
        "run": str(run.id),
        "status": run.status,
        "n_variants": run.n_variants,
        "n_changed": run.n_changed,
        "n_failed": run.n_failed,
    }
