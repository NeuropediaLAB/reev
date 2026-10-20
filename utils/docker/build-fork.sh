#!/usr/bin/bash
# Build a REEV image from this fork.
#
#   ./utils/docker/build-fork.sh            # tag neuropedialab/reev:<git describe>
#   TAG=neuropedialab/reev:dev ./utils/docker/build-fork.sh
#   ./utils/docker/build-fork.sh --no-cache
#
# The single image contains the backend (uvicorn, port 8080) and the built
# frontend in /home/reev/ui (SERVE_FRONTEND), so it replaces both
# ghcr.io/bihealth/reev:0.6.0 and the hand-patched UI bundle.
set -euo pipefail

cd "$(dirname "$0")/../.."

_VERSION=$(git describe --tags --dirty 2>/dev/null || echo 0.0.0-$(git rev-parse --short HEAD))
TAG=${TAG:-neuropedialab/reev:${_VERSION}}

# The Dockerfile copies ${version_file} into /VERSION and uses it as the
# frontend build version.
git describe --tags --dirty > VERSION

echo ">> building ${TAG} from $(git rev-parse --short HEAD) ($(git branch --show-current))"
docker build . \
    --build-arg version_file=VERSION \
    --file utils/docker/Dockerfile \
    --tag "${TAG}" \
    "$@"

echo ">> built ${TAG}"
echo ">> deploy: set image: ${TAG} for reev-backend/reev-celery-* in the reev-deploy compose"
