"""Pydantic schemas for the case archive (followed variants, ACMG history, alerts)."""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.bookmark import BookmarkTypes


class CaseVariantCreate(BaseModel):
    """Payload to follow a variant within a case."""

    obj_type: BookmarkTypes = BookmarkTypes.seqvar
    obj_id: str = Field(min_length=1, max_length=512)
    genome_build: str | None = Field(default=None, pattern="^(grch37|grch38)$")
    gene_symbol: str | None = None
    hgnc_id: str | None = None
    transcript: str | None = None
    label: str | None = None
    notes: str | None = None
    follow: bool = True


class CaseVariantUpdate(BaseModel):
    """Editable fields of a followed variant."""

    follow: bool | None = None
    gene_symbol: str | None = None
    transcript: str | None = None
    label: str | None = None
    notes: str | None = None

    model_config = ConfigDict(populate_by_name=True)


class CaseVariantImport(BaseModel):
    """Import the bookmarks of the current user into a case."""

    obj_types: list[BookmarkTypes] = Field(
        default_factory=lambda: [BookmarkTypes.seqvar], description="Bookmark types to import"
    )
    overwrite: bool = False


class AcmgAssessmentRead(BaseModel):
    """One stored ACMG classification."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    acmg_class: str
    criteria: dict[str, Any] | None = None
    source: str
    engine_version: str
    data_signature: str | None = None
    data_versions: dict[str, Any] | None = None
    is_conflicting: bool = False
    created_at: datetime


class CaseVariantRead(BaseModel):
    """A followed variant with its latest classification."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    case_info: uuid.UUID
    bookmark: uuid.UUID | None = None
    obj_type: str
    obj_id: str
    genome_build: str
    gene_symbol: str | None = None
    hgnc_id: str | None = None
    transcript: str | None = None
    label: str | None = None
    notes: str | None = None
    follow: bool
    added_at: datetime
    last_analyzed_at: datetime | None = None
    latest: AcmgAssessmentRead | None = None


class ReanalysisRunRead(BaseModel):
    """A batch re-analysis."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    trigger: str
    status: str
    data_signature: str | None = None
    data_versions: dict[str, Any] | None = None
    n_variants: int
    n_changed: int
    n_failed: int
    error: str | None = None
    started_at: datetime
    finished_at: datetime | None = None


class ReanalysisAlertRead(BaseModel):
    """An alert about a changed classification."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    case_info: uuid.UUID
    case_variant: uuid.UUID
    old_class: str | None = None
    new_class: str
    message: str | None = None
    severity: str
    read_at: datetime | None = None
    created_at: datetime


class DataVersionRead(BaseModel):
    """A known version of a reference database."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    source: str
    version: str
    genome_build: str
    first_seen_at: datetime
    last_seen_at: datetime
    is_current: bool


class CaseArchiveSummary(BaseModel):
    """Counters shown in the case view."""

    n_variants: int
    n_followed: int
    n_alerts_unread: int
    last_run: ReanalysisRunRead | None = None
    by_class: dict[str, int]
