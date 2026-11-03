"""data_version: incluir genome_build en la clave única

Revision ID: c4d2e6b81f0a
Revises: b3f1a7c92d10
Create Date: 2026-11-03 07:45:00.000000+01:00

Annonars reporta la misma versión para una base en los dos ensamblados (mismo
release upstream), así que con (source, version) el segundo insert violaba la
restricción y el poll de versiones fallaba con IntegrityError: nunca se
registraban las versiones ni se disparaba el reanálisis.
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "c4d2e6b81f0a"
down_revision = "b3f1a7c92d10"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint("uq_data_version", "data_version", type_="unique")
    op.create_unique_constraint(
        "uq_data_version", "data_version", ["source", "version", "genome_build"]
    )


def downgrade():
    op.drop_constraint("uq_data_version", "data_version", type_="unique")
    op.create_unique_constraint("uq_data_version", "data_version", ["source", "version"])
