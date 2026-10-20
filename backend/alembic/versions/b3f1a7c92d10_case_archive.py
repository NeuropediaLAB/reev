"""case archive: followed variants, ACMG history, re-analysis

Revision ID: b3f1a7c92d10
Revises: 850ccab0221d
Create Date: 2026-10-20 18:40:00.000000+02:00

"""
import fastapi_users_db_sqlalchemy.generics  # noqa
import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision = "b3f1a7c92d10"
down_revision = "850ccab0221d"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "case_variant",
        sa.Column("id", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column(
            "case_info", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False
        ),
        sa.Column(
            "bookmark", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=True
        ),
        sa.Column("user", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column("obj_type", sa.String(length=32), nullable=False),
        sa.Column("obj_id", sa.String(length=512), nullable=False),
        sa.Column("genome_build", sa.String(length=16), nullable=False),
        sa.Column("gene_symbol", sa.String(length=64), nullable=True),
        sa.Column("hgnc_id", sa.String(length=64), nullable=True),
        sa.Column("transcript", sa.String(length=64), nullable=True),
        sa.Column("label", sa.String(length=255), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("follow", sa.Boolean(), nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_analyzed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["bookmark"], ["bookmarks.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["case_info"], ["caseinfo.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("case_info", "obj_type", "obj_id", name="uq_case_variant"),
    )
    op.create_index(
        op.f("ix_case_variant_case_info"), "case_variant", ["case_info"], unique=False
    )
    op.create_index(
        op.f("ix_case_variant_id"), "case_variant", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_case_variant_user"), "case_variant", ["user"], unique=False
    )

    op.create_table(
        "reanalysis_run",
        sa.Column("id", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column("trigger", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("data_signature", sa.String(length=64), nullable=True),
        sa.Column("data_versions", sa.JSON(), nullable=True),
        sa.Column("n_variants", sa.Integer(), nullable=False),
        sa.Column("n_changed", sa.Integer(), nullable=False),
        sa.Column("n_failed", sa.Integer(), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column(
            "created_by", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=True
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["created_by"], ["user.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_reanalysis_run_id"), "reanalysis_run", ["id"], unique=False
    )

    op.create_table(
        "data_version",
        sa.Column("id", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column("source", sa.String(length=64), nullable=False),
        sa.Column("version", sa.String(length=128), nullable=False),
        sa.Column("genome_build", sa.String(length=16), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_current", sa.Boolean(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("source", "version", name="uq_data_version"),
    )
    op.create_index(
        op.f("ix_data_version_id"), "data_version", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_data_version_source"), "data_version", ["source"], unique=False
    )

    op.create_table(
        "acmg_assessment",
        sa.Column("id", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column(
            "case_variant", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False
        ),
        sa.Column(
            "run", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=True
        ),
        sa.Column("acmg_class", sa.String(length=64), nullable=False),
        sa.Column("criteria", sa.JSON(), nullable=True),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("engine_version", sa.String(length=64), nullable=False),
        sa.Column("data_signature", sa.String(length=64), nullable=True),
        sa.Column("data_versions", sa.JSON(), nullable=True),
        sa.Column("is_conflicting", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["case_variant"], ["case_variant.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["run"], ["reanalysis_run.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_acmg_assessment_case_variant"),
        "acmg_assessment",
        ["case_variant"],
        unique=False,
    )
    op.create_index(
        op.f("ix_acmg_assessment_data_signature"),
        "acmg_assessment",
        ["data_signature"],
        unique=False,
    )
    op.create_index(
        op.f("ix_acmg_assessment_id"), "acmg_assessment", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_acmg_assessment_run"), "acmg_assessment", ["run"], unique=False
    )

    op.create_table(
        "reanalysis_alert",
        sa.Column("id", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column("user", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
        sa.Column(
            "case_info", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False
        ),
        sa.Column(
            "case_variant", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False
        ),
        sa.Column(
            "assessment", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=True
        ),
        sa.Column(
            "previous_assessment",
            fastapi_users_db_sqlalchemy.generics.GUID(),
            nullable=True,
        ),
        sa.Column("run", fastapi_users_db_sqlalchemy.generics.GUID(), nullable=True),
        sa.Column("old_class", sa.String(length=64), nullable=True),
        sa.Column("new_class", sa.String(length=64), nullable=False),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("severity", sa.String(length=16), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["assessment"], ["acmg_assessment.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["case_info"], ["caseinfo.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["case_variant"], ["case_variant.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["previous_assessment"], ["acmg_assessment.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["run"], ["reanalysis_run.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_reanalysis_alert_case_info"),
        "reanalysis_alert",
        ["case_info"],
        unique=False,
    )
    op.create_index(
        op.f("ix_reanalysis_alert_case_variant"),
        "reanalysis_alert",
        ["case_variant"],
        unique=False,
    )
    op.create_index(
        op.f("ix_reanalysis_alert_id"), "reanalysis_alert", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_reanalysis_alert_user"), "reanalysis_alert", ["user"], unique=False
    )


def downgrade():
    op.drop_index(op.f("ix_reanalysis_alert_user"), table_name="reanalysis_alert")
    op.drop_index(op.f("ix_reanalysis_alert_id"), table_name="reanalysis_alert")
    op.drop_index(
        op.f("ix_reanalysis_alert_case_variant"), table_name="reanalysis_alert"
    )
    op.drop_index(
        op.f("ix_reanalysis_alert_case_info"), table_name="reanalysis_alert"
    )
    op.drop_table("reanalysis_alert")

    op.drop_index(op.f("ix_acmg_assessment_run"), table_name="acmg_assessment")
    op.drop_index(op.f("ix_acmg_assessment_id"), table_name="acmg_assessment")
    op.drop_index(
        op.f("ix_acmg_assessment_data_signature"), table_name="acmg_assessment"
    )
    op.drop_index(
        op.f("ix_acmg_assessment_case_variant"), table_name="acmg_assessment"
    )
    op.drop_table("acmg_assessment")

    op.drop_index(op.f("ix_data_version_source"), table_name="data_version")
    op.drop_index(op.f("ix_data_version_id"), table_name="data_version")
    op.drop_table("data_version")

    op.drop_index(op.f("ix_reanalysis_run_id"), table_name="reanalysis_run")
    op.drop_table("reanalysis_run")

    op.drop_index(op.f("ix_case_variant_user"), table_name="case_variant")
    op.drop_index(op.f("ix_case_variant_id"), table_name="case_variant")
    op.drop_index(op.f("ix_case_variant_case_info"), table_name="case_variant")
    op.drop_table("case_variant")
