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

set -euo pipefail  # Stricter safety

# Retry configuration (helps with transient Docker EOF/export failures)
MAX_RETRIES="${MAX_RETRIES:-2}"   # Number of build attempts
SLEEP_BETWEEN="${SLEEP_BETWEEN:-5}" # Seconds to wait before retry

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

# Buildx cache directory (persists layers across daemon crashes / retries)
BUILDX_CACHE_DIR="${BUILDX_CACHE_DIR:-.buildx-cache}"
mkdir -p "${BUILDX_CACHE_DIR}" || true

# Enable/disable registry fallback (push/pull via local registry) after tar fallback failure
ENABLE_REGISTRY_FALLBACK="${ENABLE_REGISTRY_FALLBACK:-1}"
LOCAL_REGISTRY_NAME="${LOCAL_REGISTRY_NAME:-local-registry}"
LOCAL_REGISTRY_PORT="${LOCAL_REGISTRY_PORT:-5000}"
LOCAL_REGISTRY_ADDR="localhost:${LOCAL_REGISTRY_PORT}"

echo "🏗️  Building ${TARGET} for ${PLATFORM} (will try up to ${MAX_RETRIES} time(s))..."

# IMAGE OUTPUT MODE (choose how to export the result to avoid large --load streaming crashes)
# Supported values:
#   load  - (default legacy path) load into local docker daemon (streams large image; least stable for huge images)
#   tar   - write legacy docker archive  <image>.tar (not loaded)
#   oci   - write OCI image layout       <image>.oci (recommended: smaller metadata, no daemon streaming) [default]
#   push  - push directly to registry (requires PUSH_TAG env var)
#   none  - build and keep result only in build cache (no export)
IMAGE_OUTPUT="${IMAGE_OUTPUT:-oci}"
PUSH_TAG="${PUSH_TAG:-}"  # e.g. ghcr.io/you/base-container:latest

# Optional: Rootless/buildkitd (dockerless) direct invocation support.
# If ROOTLESS_BUILDKIT=1 and buildctl is available, attempt to use it for non-load outputs,
# bypassing the Docker daemon entirely (avoids daemon export instability). Only supported for
# IMAGE_OUTPUT in (oci, tar, none, push) where we can map outputs to buildctl frontends.
ROOTLESS_BUILDKIT="${ROOTLESS_BUILDKIT:-0}"
BUILDKIT_BIN="${BUILDKIT_BIN:-buildctl}"   # override if custom path
if [ "$ROOTLESS_BUILDKIT" = "1" ] && [ "$IMAGE_OUTPUT" = "load" ]; then
        echo "⚠️  ROOTLESS_BUILDKIT requested but IMAGE_OUTPUT=load requires daemon; disabling rootless for this run." >&2
        ROOTLESS_BUILDKIT=0
fi

if [ "$IMAGE_OUTPUT" != "load" ]; then
        echo "🚫 Skipping native docker build / --load export because IMAGE_OUTPUT=$IMAGE_OUTPUT"
        if [ "$ROOTLESS_BUILDKIT" = "1" ]; then
                if command -v "$BUILDKIT_BIN" >/dev/null 2>&1; then
                        echo "🛠️  Using rootless BuildKit ('$BUILDKIT_BIN') path (daemon bypass)."
                        # Map IMAGE_OUTPUT to buildctl output spec
                        artifact_path=""
                        output_type=""
                        case "$IMAGE_OUTPUT" in
                                oci)
                                        artifact_path="${IMAGE_TAG}.oci"; output_type="oci" ;;
                                tar)
                                        artifact_path="${IMAGE_TAG}.tar"; output_type="docker" ;;
                                none)
                                        output_type="local"; artifact_path="/dev/null" ;;
                                push)
                                        if [ -z "$PUSH_TAG" ]; then
                                                echo "❌ IMAGE_OUTPUT=push requires PUSH_TAG." >&2; exit 1; fi
                                        output_type="image" ;;
                        esac
                        # buildctl requires a context and Dockerfile; we assume working dir root.
                        # Use inline frontend parameters for target & platform.
                        attempt=1
                        while :; do
                                echo "🔁 Rootless build attempt ${attempt}/${MAX_RETRIES} (${IMAGE_OUTPUT})..."
                                set +e
                                if [ "$IMAGE_OUTPUT" = push ]; then
                                        "$BUILDKIT_BIN" build \
                                                --progress=plain \
                                                --frontend=dockerfile.v0 \
                                                --local context=. \
                                                --local dockerfile=. \
                                                --opt target="${TARGET}" \
                                                --opt platform="${PLATFORM}" \
                                                --output type=image,name="${PUSH_TAG}",push=true
                                else
                                        "$BUILDKIT_BIN" build \
                                                --progress=plain \
                                                --frontend=dockerfile.v0 \
                                                --local context=. \
                                                --local dockerfile=. \
                                                --opt target="${TARGET}" \
                                                --opt platform="${PLATFORM}" \
                                                --output type="${output_type}",dest="${artifact_path}"
                                fi
                                status=$?
                                set -e
                                if [ $status -eq 0 ]; then
                                        echo "✅ Rootless build succeeded (${IMAGE_OUTPUT})."
                                        if [ -n "$artifact_path" ] && [ -f "$artifact_path" ] && [ "$artifact_path" != /dev/null ]; then
                                                echo "📦 Artifact: $artifact_path"
                                        fi
                                        [ "$IMAGE_OUTPUT" = push ] && echo "🚀 Pushed: $PUSH_TAG"
                                        echo "Done."; exit 0
                                fi
                                echo "❌ Rootless attempt ${attempt} failed (status $status)."
                                if [ $attempt -lt $MAX_RETRIES ]; then
                                        echo "⏱️  Retrying after ${SLEEP_BETWEEN}s..."; sleep "$SLEEP_BETWEEN"; attempt=$((attempt+1))
                                else
                                        echo "🛑 Exhausted rootless retries; falling back to docker buildx path." >&2
                                        break
                                fi
                        done
                else
                        echo "⚠️  ROOTLESS_BUILDKIT=1 but buildctl not found; continuing with docker buildx." >&2
                fi
        fi
        # Reuse (or define lightweight) helpers early for this branch. We'll later re-define a more
        # robust restart_docker_if_needed for the legacy --load path (harmless re-definition).
        restart_docker_if_needed() {
                if ! docker info >/dev/null 2>&1; then
                        echo "⚠️  Docker daemon unavailable. Attempting restart..."
                        if [ -x /usr/local/share/docker-init.sh ]; then
                                sudo /usr/local/share/docker-init.sh || true
                                sleep 4
                        fi
                fi
        }
        ensure_builder() {
                local builder_name=${BUILDX_BUILDER_NAME:-resilient-builder}
                if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
                        echo "🧱 Creating buildx builder '$builder_name' (driver=docker-container)..."
                        docker buildx create --name "$builder_name" --driver docker-container --use >/dev/null 2>&1 || {
                                echo "⚠️  Could not create dedicated builder; falling back to default." >&2
                        }
                else
                        docker buildx use "$builder_name" >/devnull 2>&1 || true
                fi
        }
        ensure_builder

        # Decide output flags
        output_flags=()
        artifact_path=""
        case "$IMAGE_OUTPUT" in
                tar)
                        artifact_path="${IMAGE_TAG}.tar"
                        output_flags=(--output type=docker,dest="${artifact_path}") ;;
                oci)
                        artifact_path="${IMAGE_TAG}.oci"
                        output_flags=(--output type=oci,dest="${artifact_path}") ;;
                push)
                        if [ -z "$PUSH_TAG" ]; then
                                echo "❌ IMAGE_OUTPUT=push but PUSH_TAG not set." >&2
                                exit 1
                        fi
                        output_flags=(--push -t "$PUSH_TAG") ;;
                none)
                        echo "ℹ️  IMAGE_OUTPUT=none: no export, build for cache only." ;;
                *)
                        echo "❌ Unknown IMAGE_OUTPUT='$IMAGE_OUTPUT'" >&2; exit 1 ;;
        esac

        attempt=1
        while :; do
                echo "🔁 Build attempt ${attempt}/${MAX_RETRIES} (buildx output: ${IMAGE_OUTPUT})..."
                # Ensure daemon (used for buildx driver=docker-container) is healthy each attempt
                restart_docker_if_needed || true
                set +e
                docker buildx build \
                        --platform "${PLATFORM}" \
                        --target "${TARGET}" \
                        --build-arg DEBIAN_FRONTEND=noninteractive \
                        --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
                        --cache-from type=local,src="${BUILDX_CACHE_DIR}" \
                        --cache-to type=local,dest="${BUILDX_CACHE_DIR}",mode=max \
                        -t "${IMAGE_TAG}" \
                        "${output_flags[@]}" \
                        .
                status=$?
                set -e
                if [ $status -eq 0 ]; then
                        echo "✅ Build succeeded (mode=${IMAGE_OUTPUT})."
                        if [ -n "$artifact_path" ] && [ -f "$artifact_path" ]; then
                                echo "📦 Artifact: $artifact_path"
                        fi
                        if [ "$IMAGE_OUTPUT" = push ]; then
                                echo "🚀 Pushed: $PUSH_TAG"
                        fi
                        echo "Done."; exit 0
                fi
                echo "❌ Attempt ${attempt} failed (status ${status})."
                if [ $attempt -lt $MAX_RETRIES ]; then
                        echo "⏱️  Retrying after ${SLEEP_BETWEEN}s..."
                        sleep "$SLEEP_BETWEEN"; attempt=$((attempt+1))
                else
                        echo "🛑 Exhausted retries." >&2; exit $status
                fi
        done
fi

host_arch=$(uname -m)
case "$host_arch" in
    x86_64) host_arch_norm=amd64 ;;
    aarch64|arm64) host_arch_norm=arm64 ;;
    *) host_arch_norm="$host_arch" ;;
esac

# Native fast path: if host arch matches target and not forced to use buildx, use classic docker build (more stable than buildx --load for huge images)
NATIVE_FAST_PATH="${NATIVE_FAST_PATH:-1}"         # set to 0 to disable
FORCE_BUILDX="${FORCE_BUILDX:-0}"

restart_docker_if_needed() {
        if ! docker info >/dev/null 2>&1; then
                echo "⚠️  Docker daemon unavailable. Attempting restart..."
                if [ -x /usr/local/share/docker-init.sh ]; then
                        sudo /usr/local/share/docker-init.sh || true
                        # give it a moment
                        sleep 4
                fi
                local tries=1
                while ! docker info >/dev/null 2>&1; do
                        if [ $tries -ge 5 ]; then
                                echo "❌ Docker daemon failed to start after ${tries} attempts." >&2
                                return 1
                        fi
                        echo "⏳ Waiting for docker daemon (attempt ${tries})..."
                        sleep 3
                        tries=$((tries+1))
                done
                echo "✅ Docker daemon restored."
        fi
}

ensure_builder() {
        local builder_name=${BUILDX_BUILDER_NAME:-resilient-builder}
        if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
                echo "🧱 Creating buildx builder '$builder_name' (driver=docker-container)..."
                docker buildx create --name "$builder_name" --driver docker-container --use >/dev/null 2>&1 || {
                        echo "⚠️  Could not create dedicated builder; falling back to default." >&2
                }
        else
                docker buildx use "$builder_name" >/dev/null 2>&1 || true
        fi
}

if [ "$host_arch_norm" = "amd64" ] && [[ "$PLATFORM" == *"amd64"* ]] && [ "$NATIVE_FAST_PATH" = "1" ] && [ "$FORCE_BUILDX" != "1" ]; then
        echo "⚡ Native host arch matches target (host=$host_arch_norm). Using plain 'docker build' fast path (set NATIVE_FAST_PATH=0 to disable)."
        restart_docker_if_needed || true
        if docker build \
                        --target "${TARGET}" \
                        --build-arg DEBIAN_FRONTEND=noninteractive \
                        --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
                        -t "${IMAGE_TAG}" .; then
                echo "✅ Native docker build succeeded."
                fast_path_success=1
        else
                echo "⚠️  Native docker build failed; falling back to buildx strategy." >&2
        fi
fi

if [ -z "${fast_path_success:-}" ]; then
        ensure_builder
        attempt=1
    while :; do
            echo "🔁 Build attempt ${attempt}/${MAX_RETRIES} (buildx --load)..."
                        restart_docker_if_needed || { echo "❌ Docker daemon unavailable; aborting."; exit 2; }

            set +e
            docker buildx build \
                            --platform "${PLATFORM}" \
                            --target "${TARGET}" \
                            --build-arg DEBIAN_FRONTEND=noninteractive \
                            --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
                            --cache-from type=local,src="${BUILDX_CACHE_DIR}" \
                            --cache-to type=local,dest="${BUILDX_CACHE_DIR}",mode=max \
                            --load \
                            -t "${IMAGE_TAG}" \
                            .
            status=$?
            set -e

            if [ $status -eq 0 ]; then
                    echo "✅ Build completed successfully on attempt ${attempt}."
                    break
            fi

            echo "❌ Build attempt ${attempt} failed with status ${status}."

            if [ $attempt -lt $MAX_RETRIES ]; then
                    echo "⏱️  Will retry after ${SLEEP_BETWEEN}s..."
                    docker system df || true
                    sleep "${SLEEP_BETWEEN}"
                    attempt=$((attempt + 1))
            else
                                        echo "🛑 Exhausted buildx retries (${MAX_RETRIES}). Initiating tar fallback export..."
                                                                TAR_FILE="${IMAGE_TAG}.tar"
                                        echo "📦 Fallback: building to local tar archive ($TAR_FILE) using buildx --output type=docker"
                                        restart_docker_if_needed || { echo "❌ Docker daemon unavailable before tar fallback."; exit 3; }
                                        # Use same builder (cache reuse). Avoid --load; use export to tar.
                                        set +e
                                        docker buildx build \
                                                --platform "${PLATFORM}" \
                                                --target "${TARGET}" \
                                                --build-arg DEBIAN_FRONTEND=noninteractive \
                                                --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
                                                                        --cache-from type=local,src="${BUILDX_CACHE_DIR}" \
                                                                        --cache-to type=local,dest="${BUILDX_CACHE_DIR}",mode=max \
                                                --output type=docker,dest="${TAR_FILE}" \
                                                -t "${IMAGE_TAG}" .
                                        tar_status=$?
                                        set -e
                                        if [ $tar_status -eq 0 ]; then
                                                echo "📥 Loading tar archive into daemon..."
                                                restart_docker_if_needed || true
                                                if docker load -i "${TAR_FILE}"; then
                                                        rm -f "${TAR_FILE}" || true
                                                        echo "✅ Tar fallback succeeded."
                                                        break
                                                else
                                                        echo "⚠️  docker load failed; tar file retained at ${TAR_FILE} for manual load." >&2
                                                        exit 4
                                                fi
                                                                else
                                                                        echo "❌ Tar fallback build failed (status $tar_status)." >&2
                                                                        if [ "$ENABLE_REGISTRY_FALLBACK" = "1" ]; then
                                                                                echo "🚢 Attempting registry push/pull fallback..."
                                                                                restart_docker_if_needed || { echo "❌ Docker daemon unavailable before registry fallback."; exit 5; }
                                                                                # Ensure local registry
                                                                                if ! docker ps --format '{{.Names}}' | grep -q "^${LOCAL_REGISTRY_NAME}$"; then
                                                                                        if docker ps -a --format '{{.Names}}' | grep -q "^${LOCAL_REGISTRY_NAME}$"; then
                                                                                                docker start "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1 || true
                                                                                        else
                                                                                                echo "🗄️  Starting local registry '${LOCAL_REGISTRY_NAME}' on port ${LOCAL_REGISTRY_PORT}..."
                                                                                                docker run -d -p ${LOCAL_REGISTRY_PORT}:5000 --restart=always --name "${LOCAL_REGISTRY_NAME}" registry:2 >/dev/null 2>&1 || true
                                                                                        fi
                                                                                        sleep 2
                                                                                fi
                                                                                REGISTRY_TAG="${LOCAL_REGISTRY_ADDR}/${IMAGE_TAG}:latest"
                                                                                echo "🔄 Building & pushing to local registry as ${REGISTRY_TAG} ..."
                                                                                set +e
                                                                                docker buildx build \
                                                                                        --platform "${PLATFORM}" \
                                                                                        --target "${TARGET}" \
                                                                                        --build-arg DEBIAN_FRONTEND=noninteractive \
                                                                                        --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
                                                                                        --cache-from type=local,src="${BUILDX_CACHE_DIR}" \
                                                                                        --cache-to type=local,dest="${BUILDX_CACHE_DIR}",mode=max \
                                                                                        --push \
                                                                                        -t "${REGISTRY_TAG}" .
                                                                                reg_status=$?
                                                                                set -e
                                                                                if [ $reg_status -eq 0 ]; then
                                                                                        echo "📥 Pulling from local registry..."
                                                                                        if docker pull "${REGISTRY_TAG}" && docker tag "${REGISTRY_TAG}" "${IMAGE_TAG}"; then
                                                                                                echo "✅ Registry fallback succeeded (image tagged '${IMAGE_TAG}')."
                                                                                                break
                                                                                        else
                                                                                                echo "❌ Pull/tag from registry failed." >&2
                                                                                                exit 6
                                                                                        fi
                                                                                else
                                                                                        echo "❌ Registry fallback build/push failed (status $reg_status). Aborting." >&2
                                                                                        exit $status
                                                                                fi
                                                                        else
                                                                                echo "❌ Tar fallback failed and registry fallback disabled. Aborting." >&2
                                                                                exit $status
                                                                        fi
                                                                fi
            fi
    done
fi

echo "🐳 Image: ${IMAGE_TAG}"
echo "🧪 Test with: docker run --rm ${IMAGE_TAG} uname -m"
echo "(Expect: x86_64)"
