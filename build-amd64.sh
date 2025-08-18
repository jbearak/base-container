#!/bin/bash
# Simple script to build for amd64 platform on Apple Silicon

set -e

PLATFORM="linux/amd64"
TARGET="${1:-base}"
IMAGE_TAG="${TARGET}-amd64"

echo "🏗️  Building ${TARGET} for ${PLATFORM}..."

# Build with specific platform and environment variables to help with emulation
docker buildx build \
    --platform "${PLATFORM}" \
    --target "${TARGET}" \
    --build-arg DEBIAN_FRONTEND=noninteractive \
    --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
    --load \
    -t "${IMAGE_TAG}" \
    .

echo "✅ Build completed!"
echo "🐳 Image: ${IMAGE_TAG}"
echo "🧪 Test with: docker run --rm ${IMAGE_TAG} uname -m"
