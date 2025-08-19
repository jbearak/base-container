#!/usr/bin/env bash
# Simplified native amd64 build script (Option A)
# Purpose: Build single-arch (linux/amd64) targets without buildx complexity.
# Usage: ./build-amd64.sh [full-container|r-container]
# Env Vars:
#   R_BUILD_JOBS   (default 2) limit parallel package compilation in Dockerfile
#   EXPORT_TAR=1   also export docker save tarball <image>.tar after build
#   TAG_SUFFIX     optional extra suffix (e.g. '-dev') appended to image tag

set -euo pipefail

TARGET="${1:-full-container}"
case "$TARGET" in
        full-container|r-container) ;;
        *) echo "❌ Invalid target '$TARGET' (expected full-container|r-container)" >&2; exit 1;;
esac

# Ensure we are on native amd64 host (since we drop cross-build logic)
if [ "$(uname -m)" != "x86_64" ]; then
        echo "❌ Host architecture $(uname -m) is not x86_64; this simplified script only handles native amd64." >&2
        echo "   Use the legacy (buildx) script for cross-building." >&2
        exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
        echo "❌ docker CLI not found in PATH" >&2; exit 3
fi

if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker daemon not reachable. Start Docker and retry." >&2; exit 4
fi

R_BUILD_JOBS="${R_BUILD_JOBS:-2}"
IMAGE_TAG_BASE="${TARGET}-amd64"
IMAGE_TAG="${IMAGE_TAG_BASE}${TAG_SUFFIX:-}"

echo "🏗️  Building target='${TARGET}' arch='linux/amd64' tag='${IMAGE_TAG}' (R_BUILD_JOBS=${R_BUILD_JOBS})"
time DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1} docker build \
        --target "${TARGET}" \
        --build-arg R_BUILD_JOBS="${R_BUILD_JOBS}" \
        -t "${IMAGE_TAG}" .

echo "✅ Build complete: ${IMAGE_TAG}"

if [ "${EXPORT_TAR:-0}" = "1" ]; then
        TAR_NAME="${IMAGE_TAG}.tar"
        echo "📦 Exporting tar archive: ${TAR_NAME}"
        docker save "${IMAGE_TAG}" -o "${TAR_NAME}"
        echo "✅ Wrote ${TAR_NAME}" 
fi

echo "🧪 Quick test (architecture): docker run --rm ${IMAGE_TAG} uname -m"
echo "ℹ️  To push: docker push ${IMAGE_TAG} (add your registry prefix/tag first if needed)"
echo "(Expect: x86_64)"
