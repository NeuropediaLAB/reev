"""Models for the case archive built on top of case info and bookmarks.

A case (``CaseInfo``) keeps its phenotype (HPO terms), and gains a set of
followed variants plus a history of ACMG classifications.  When the underlying
reference databases change, the variants are re-analysed and, when the ACMG
class changes, an alert is raised for the case owner.
"""

import uuid as uuid_module
from datetime import datetime
from typing import Any

from fastapi_users_db_sqlalchemy.generics import GUID  # noqa
from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class CaseVariant(Base):
    """A variant followed within a case."""

    __tablename__ = "case_variant"
    __table_args__ = (
        UniqueConstraint("case_info", "obj_type", "obj_id", name="uq_case_variant"),
    )

    #: UUID of the case variant.
    id: Mapped[uuid_module.UUID] = mapped_column(
        GUID, primary_key=True, index=True, default=uuid_module.uuid4
    )
    #: Case this variant belongs to.
    case_info: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("caseinfo.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: Optional bookmark this entry was created from.
    bookmark: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("bookmarks.id", ondelete="SET NULL"), nullable=True
    )
    #: Owner of the entry (denormalised for permission checks).
    user: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("user.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: ``seqvar``, ``strucvar`` or ``gene``.
    obj_type: Mapped[str] = mapped_column(String(32), nullable=False)
    #: Identifier of the object, as used by the bookmarks.
    obj_id: Mapped[str] = mapped_column(String(512), nullable=False)
    #: ``grch37`` or ``grch38``.
    genome_build: Mapped[str] = mapped_column(String(16), nullable=False, default="grch37")
    #: Gene symbol, when known.
    gene_symbol: Mapped[str | None] = mapped_column(String(64), nullable=True)
    #: HGNC id, when known.
    hgnc_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    #: Transcript used for the classification.
    transcript: Mapped[str | None] = mapped_column(String(64), nullable=True)
    #: Free-text label.
    label: Mapped[str | None] = mapped_column(String(255), nullable=True)
    #: Free-text notes.
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    #: Whether the variant takes part in automatic re-analysis.
    follow: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    #: When the entry was created.
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    #: When the variant was last re-analysed.
    last_analyzed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class AcmgAssessment(Base):
    """One ACMG classification of a case variant (append-only history)."""

    __tablename__ = "acmg_assessment"

    id: Mapped[uuid_module.UUID] = mapped_column(
        GUID, primary_key=True, index=True, default=uuid_module.uuid4
    )
    case_variant: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("case_variant.id", ondelete="CASCADE"), nullable=False, index=True
    )
    run: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("reanalysis_run.id", ondelete="SET NULL"), nullable=True, index=True
    )
    #: ``Pathogenic``, ``Likely pathogenic``, ``Uncertain significance``, ...
    acmg_class: Mapped[str] = mapped_column(String(64), nullable=False)
    #: Criteria flags as returned by the ACMG service (``{"pvs1": true, ...}``).
    criteria: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    #: ``auto-acmg``, ``intervar``, ``wintervar`` or ``manual``.
    source: Mapped[str] = mapped_column(String(32), nullable=False, default="auto-acmg")
    #: Version of the classification engine / criteria set.
    engine_version: Mapped[str] = mapped_column(
        String(64), nullable=False, default="reev-acmg-1"
    )
    #: Signature of the reference data used for this assessment.
    data_signature: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    #: Per-database versions (``{"clinvar": "2024-12-20", ...}``).
    data_versions: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    #: Whether the source reported conflicting classifications.
    is_conflicting: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )


class ReanalysisRun(Base):
    """A batch re-analysis of case variants."""

    __tablename__ = "reanalysis_run"

    id: Mapped[uuid_module.UUID] = mapped_column(
        GUID, primary_key=True, index=True, default=uuid_module.uuid4
    )
    #: ``scheduled``, ``manual`` or ``publish``.
    trigger: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
    #: ``running``, ``success``, ``partial`` or ``failed``.
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="running")
    data_signature: Mapped[str | None] = mapped_column(String(64), nullable=True)
    data_versions: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    n_variants: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    n_changed: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    n_failed: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class ReanalysisAlert(Base):
    """Notification that the ACMG class of a followed variant changed."""

    __tablename__ = "reanalysis_alert"

    id: Mapped[uuid_module.UUID] = mapped_column(
        GUID, primary_key=True, index=True, default=uuid_module.uuid4
    )
    user: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("user.id", ondelete="CASCADE"), nullable=False, index=True
    )
    case_info: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("caseinfo.id", ondelete="CASCADE"), nullable=False, index=True
    )
    case_variant: Mapped[uuid_module.UUID] = mapped_column(
        Uuid, ForeignKey("case_variant.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assessment: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("acmg_assessment.id", ondelete="CASCADE"), nullable=True
    )
    previous_assessment: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("acmg_assessment.id", ondelete="SET NULL"), nullable=True
    )
    run: Mapped[uuid_module.UUID | None] = mapped_column(
        Uuid, ForeignKey("reanalysis_run.id", ondelete="SET NULL"), nullable=True
    )
    old_class: Mapped[str | None] = mapped_column(String(64), nullable=True)
    new_class: Mapped[str] = mapped_column(String(64), nullable=False)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    #: ``info``, ``warning`` or ``critical`` (pathogenic gained/lost).
    severity: Mapped[str] = mapped_column(String(16), nullable=False, default="info")
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )


class DataVersion(Base):
    """Known version of a reference database, used to detect updates."""

    __tablename__ = "data_version"
    __table_args__ = (UniqueConstraint("source", "version", name="uq_data_version"),)

    id: Mapped[uuid_module.UUID] = mapped_column(
        GUID, primary_key=True, index=True, default=uuid_module.uuid4
    )
    source: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    version: Mapped[str] = mapped_column(String(128), nullable=False)
    genome_build: Mapped[str] = mapped_column(String(16), nullable=False, default="grch37")
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


#: All models of the archive, for Alembic autogenerate / metadata imports.
ALL_MODELS = (CaseVariant, AcmgAssessment, ReanalysisRun, ReanalysisAlert, DataVersion)
