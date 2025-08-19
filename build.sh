#!/usr/bin/env bash
# Unified build script (best-practice simplified approach)
# Purpose: Single entry-point to build either target (full-container | r-container)
#          for host architecture (default) or explicitly for amd64 via --amd64.
# Philosophy:
#   * Keep local developer workflow simple: one script, obvious flags.
#   * Avoid buildx unless cross-arch output is explicitly requested.
#   * Provide predictable image naming: <target>-<arch> locally.
#   * Leave multi-platform manifest creation to push script (buildx there).
#
# Usage:
#   ./build.sh full-container          # build host arch full-container
#   ./build.sh r-container             # build host arch r-container
#   ./build.sh --amd64 full-container  # force build for linux/amd64 (requires buildx on non-amd64 hosts)
#   ./build.sh --no-cache full-container
#   R_BUILD_JOBS=4 ./build.sh full-container
#   EXPORT_TAR=1 ./build.sh r-container
#
# Environment:
#   R_BUILD_JOBS   Limit parallel R package compilation (passed as build-arg, default 2)
#   EXPORT_TAR=1   After build, export docker save tarball <image>.tar
#   TAG_SUFFIX     Append suffix to local tag (e.g. -dev)
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERR]${NC} $*" >&2; }
succ(){ echo -e "${GREEN}[OK]${NC} $*"; }

usage(){ cat <<EOF
Unified build script

Usage: $0 [--amd64] [--no-cache] [--debug] <full-container|r-container>

Options:
  --amd64        Build linux/amd64 image (even on arm64 host). Uses buildx if host != amd64.
  --no-cache     Disable Docker build cache.
  --debug        Pass DEBUG_PACKAGES=true (verbose R package logs) to Dockerfile.
  -h, --help     Show this help.

Environment:
  R_BUILD_JOBS (default 2)  Parallel R package compile jobs.
  EXPORT_TAR=1              Export image tar after build.
  TAG_SUFFIX                Extra suffix for local tag (e.g. -dev).

Examples:
  ./build.sh full-container
  ./build.sh --amd64 r-container
  R_BUILD_JOBS=6 ./build.sh full-container
  EXPORT_TAR=1 TAG_SUFFIX=-test ./build.sh r-container
EOF
}

# Defaults
FORCE_AMD64=false
NO_CACHE=false
DEBUG_PACKAGES=false
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --amd64) FORCE_AMD64=true; shift;;
    --no-cache) NO_CACHE=true; shift;;
    --debug) DEBUG_PACKAGES=true; shift;;
    -h|--help) usage; exit 0;;
    full-container|r-container) TARGET="$1"; shift;;
    *) err "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [ -z "$TARGET" ]; then
  usage; err "Target required"; exit 1
fi

if ! command -v docker >/dev/null 2>&1; then err "docker CLI not found"; exit 2; fi
if ! docker info >/dev/null 2>&1; then err "Docker daemon unreachable"; exit 3; fi

HOST_ARCH_RAW="$(uname -m)"
case "$HOST_ARCH_RAW" in
  x86_64) HOST_ARCH=amd64;;
  aarch64|arm64) HOST_ARCH=arm64;;
  *) err "Unsupported host arch: $HOST_ARCH_RAW"; exit 4;;
esac || true

# Determine build platform
if $FORCE_AMD64; then
  BUILD_PLATFORM=linux/amd64
else
  BUILD_PLATFORM="linux/${HOST_ARCH}"
fi

# Decide if buildx is needed
NEED_BUILDX=false
if [ "$BUILD_PLATFORM" = "linux/amd64" ] && [ "$HOST_ARCH" != "amd64" ]; then
  NEED_BUILDX=true
fi

if $NEED_BUILDX && ! docker buildx version >/dev/null 2>&1; then
  err "buildx required for cross-building to amd64 from $HOST_ARCH. Install Docker buildx."; exit 5
fi

R_BUILD_JOBS="${R_BUILD_JOBS:-2}"
IMAGE_ARCH_SUFFIX=${BUILD_PLATFORM#linux/}
IMAGE_TAG_BASE="${TARGET}-${IMAGE_ARCH_SUFFIX}"
IMAGE_TAG="${IMAGE_TAG_BASE}${TAG_SUFFIX:-}"

BUILD_ARGS=( --target "$TARGET" --build-arg R_BUILD_JOBS="$R_BUILD_JOBS" )
$DEBUG_PACKAGES && BUILD_ARGS+=( --build-arg DEBUG_PACKAGES=true ) || true
$NO_CACHE && BUILD_ARGS+=( --no-cache ) || true

info "Building target=$TARGET platform=$BUILD_PLATFORM tag=$IMAGE_TAG (R_BUILD_JOBS=$R_BUILD_JOBS)"

if $NEED_BUILDX; then
  info "Using buildx for cross-arch build"
  time docker buildx build --platform "$BUILD_PLATFORM" "${BUILD_ARGS[@]}" --load -t "$IMAGE_TAG" .
else
  time docker build "${BUILD_ARGS[@]}" -t "$IMAGE_TAG" .
fi

succ "Built $IMAGE_TAG"

if [ "${EXPORT_TAR:-0}" = "1" ]; then
  TAR_NAME="${IMAGE_TAG}.tar"
  info "Exporting $TAR_NAME"
  docker save "$IMAGE_TAG" -o "$TAR_NAME"
  succ "Exported $TAR_NAME"
fi

echo
succ "Quick test suggestion: docker run --rm $IMAGE_TAG uname -m"
[ "$TARGET" = "r-container" ] && echo "Run R: docker run --rm $IMAGE_TAG R -q -e 'sessionInfo()'" || true
echo "Push (single-arch): docker tag $IMAGE_TAG ghcr.io/OWNER/base-container:${TARGET#full-container} && docker push ghcr.io/OWNER/base-container:..."
echo "For multi-arch distribution use: ./push-to-ghcr.sh -a"
