#!/bin/bash
# Simple script to build for amd64 platform on Apple Silicon
#
# WHY THIS SCRIPT EXISTS:
# If you have an Apple Silicon Mac (M1, M2, M3) but need to build a container that will
# run on Intel/AMD servers (most cloud providers), you need to cross-compile.
# This script uses Docker's emulation to build x86_64 containers on ARM machines.
#
# WHEN TO USE THIS:
# - You're on an Apple Silicon Mac
# - You need to test how your container works on Intel/AMD architecture
# - You're preparing containers for deployment to cloud servers (AWS, GCP, etc.)
#
# NOTE: Cross-compilation is slower than native builds, but it works reliably.

set -e  # Exit if any command fails

# Configuration
PLATFORM="linux/amd64"           # Target Intel/AMD 64-bit architecture
TARGET="${1:-full-container}"    # Default to full-container if no argument provided

# Validate the target is one we support
# WHY WE VALIDATE: Better to fail early with a clear error than build something unexpected
case "$TARGET" in
    "full-container"|"r-container")
        # Valid targets - continue
        ;;
    *)
        echo "❌ ERROR: Invalid target '$TARGET'"
        echo "Valid targets: full-container, r-container"
        echo "Usage: $0 [full-container|r-container]"
        exit 1
        ;;
esac

IMAGE_TAG="${TARGET}-amd64"      # Name the image to show its architecture

echo "🏗️  Building ${TARGET} for ${PLATFORM}..."

# Build with specific platform and environment variables to help with emulation
# WHY THESE FLAGS:
# --platform: Forces Docker to build for Intel/AMD even on Apple Silicon
# --target: Which stage of the multi-stage Dockerfile to build
# --build-arg: Makes package installations non-interactive (no prompts)
# --load: Saves the image locally so you can test it with "docker run"
# -t: Tags the image with a name that includes the architecture
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
# WHY TEST WITH uname -m: This shows the architecture inside the container.
# Should show "x86_64" even when running on Apple Silicon, proving emulation works.
