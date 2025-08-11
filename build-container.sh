#!/bin/bash
# This script builds the development container image. It supports building specific Dockerfile targets and optional post-build tests.

# build-container.sh - Build and optionally test the dev container

set -e

CONTAINER_NAME="base-container"
IMAGE_TAG="latest"
BUILD_TARGET="full" # Default to full build
DEBUG_MODE=""
CACHE_REGISTRY=""
CACHE_MODE=""

# Helpers to reduce duplication in docker run checks
run_in_container() {
    local my_cmd="$1"
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" bash -lc "$my_cmd"
}

check_cmd() {
    local my_description="$1"
    local my_cmd="$2"
    echo "$my_description"
    if run_in_container "$my_cmd" >/dev/null 2>&1; then
        return 0
    else
        echo "⚠️  ${my_description} failed"
        return 1
    fi
}

test_vscode() {
    echo "📦 Testing VS Code server installation..."
    run_in_container "ls -la /home/me/.vscode-server/bin/" || echo "⚠️  VS Code server test failed"
}

test_latex_basic() {
    echo "📄 Testing LaTeX installation..."
    run_in_container "xelatex --version | head -n 1" || echo "⚠️  XeLaTeX test failed"
}

test_pandoc() {
    echo "📄 Testing Pandoc installation and functionality..."
    run_in_container "pandoc --version | head -n 1" || { echo "⚠️  Pandoc version test failed"; return 1; }
    echo "📝 Running comprehensive Pandoc tests (docx, pdf, citations)..."
    if docker run --rm -v "$(pwd)":/workspace -w /workspace "${CONTAINER_NAME}:${IMAGE_TAG}" ./test_pandoc.sh; then
        return 0
    else
        echo "⚠️  Comprehensive Pandoc tests failed"
        return 1
    fi
}

test_pandoc_plus() {
    echo "🔍 Testing tlmgr soul package..."
    run_in_container "kpsewhich soul.sty" || { echo "⚠️ soul.sty missing"; return 1; }
}

test_python313() {
    echo "🐍 Testing Python 3.13 installation..."
    run_in_container "python3.13 --version" || { echo "⚠️ Python 3.13 not available"; return 1; }
    run_in_container "python3.13 -c 'import sys; print(f\"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}\")'" || { echo "⚠️ Python 3.13 execution test failed"; return 1; }
}

test_nvim_and_plugins() {
    echo "📝 Testing nvim and plugins..."
    run_in_container "nvim --version" || { echo "⚠️  nvim not available"; return 1; }
    run_in_container "ls -la /home/me/.local/share/nvim/lazy/" || { echo "⚠️  lazy.nvim plugins not found"; return 1; }
}

test_dev_tools() {
    echo "🛠️  Testing development tools..."
    local my_fail=0
    check_cmd "Checking Yarn..." "yarn --version" || my_fail=1
    check_cmd "Checking fd..." 'env PATH="/home/me/.local/bin:$PATH" fd --version' || my_fail=1
    check_cmd "Checking eza..." "eza --version" || my_fail=1
    # gotests does not support --version; -h confirms presence
    check_cmd "Checking gotests..." 'env GOPATH="/home/me/go" PATH="/home/me/go/bin:/usr/local/go/bin:$PATH" gotests -h >/dev/null' || my_fail=1
    check_cmd "Checking tree-sitter..." 'env PATH="/home/me/.local/bin:$PATH" tree-sitter --version' || my_fail=1
    return $my_fail
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --base)
    BUILD_TARGET="base"
    IMAGE_TAG="base"
    echo "🚀 Building base image (system tools only)..."
    shift
    ;;
  --base-nvim)
    BUILD_TARGET="base-nvim"
    IMAGE_TAG="base-nvim"
    echo "📝 Building image with nvim plugins installed..."
    shift
    ;;
  --base-nvim-vscode)
    BUILD_TARGET="base-nvim-vscode"
    IMAGE_TAG="base-nvim-vscode"
    echo "🔧 Building image with nvim + VS Code server and extensions..."
    shift
    ;;
  --base-nvim-vscode-tex)
    BUILD_TARGET="base-nvim-vscode-tex"
    IMAGE_TAG="base-nvim-vscode-tex"
    echo "📚 Building image with LaTeX stack (no Pandoc)..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc"
    echo "📚 Building image with LaTeX + Pandoc..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-haskell)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-haskell"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-haskell"
    echo "📚⚡ Building image with LaTeX + Pandoc + Haskell..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-haskell-crossref)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-haskell-crossref"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-haskell-crossref"
    echo "📚🔀 Building image with LaTeX + Pandoc + Haskell + pandoc-crossref..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-haskell-crossref-plus"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-haskell-crossref-plus"
    echo "📚➕ Building image with extra LaTeX packages..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r"
    echo "📐 Building image with R packages installed..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py"
    echo "🐍 Building image with Python 3.13..."
    shift
    ;;
  --full)
    BUILD_TARGET="full"
    IMAGE_TAG="full"
    echo "🏗️  Building full image..."
    shift
    ;;
  --debug)
    DEBUG_MODE="--build-arg DEBUG_PACKAGES=true"
    echo "🐛 Debug mode enabled - R package logs will be shown"
    shift
    ;;
  --test)
    TEST_CONTAINER=true
    shift
    ;;
  --no-cache)
    NO_CACHE="--no-cache"
    shift
    ;;
  --cache-from)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache"
    echo "🗂️  Using registry cache from: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  --cache-to)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-to type=registry,ref=${CACHE_REGISTRY}/cache,mode=max"
    echo "💾 Pushing cache to: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  --cache-from-to)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache --cache-to type=registry,ref=${CACHE_REGISTRY}/cache,mode=max"
    echo "🔄 Using and updating registry cache: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  -h | --help)
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Stage Options:"
    echo "  --base                               Build only the base stage (system tools only)"
    echo "  --base-nvim                          Build base + nvim with plugins installed"
    echo "  --base-nvim-vscode                   Build base + nvim + VS Code server and extensions"
    echo "  --base-nvim-vscode-tex               Build base + nvim + VS Code + LaTeX (no Pandoc)"
    echo "  --base-nvim-vscode-tex-pandoc        Build base + nvim + VS Code + LaTeX + Pandoc"
    echo "  --base-nvim-vscode-tex-pandoc-haskell        Build base + nvim + VS Code + LaTeX + Pandoc + Haskell"
    echo "  --base-nvim-vscode-tex-pandoc-haskell-crossref Build base + nvim + VS Code + LaTeX + Pandoc + Haskell + crossref"
    echo "  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus   Build base + nvim + VS Code + LaTeX + Pandoc + extra packages"
    echo "  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r Build base + nvim + VS Code + LaTeX + Pandoc + extra packages + R packages"
    echo "  --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py Build base + nvim + VS Code + LaTeX + Pandoc + extra packages + R packages + Python 3.13"
    echo "  --full                               Build the full stage"
    echo ""
    echo "Other Options:"
    echo "  --debug                              Show verbose R package installation logs (default: quiet)"
    echo "  --test                               Run tests after building"
    echo "  --no-cache                           Build without using Docker cache"
    echo "  --cache-from <registry>              Use registry cache from specified registry (e.g., ghcr.io/user/repo)"
    echo "  --cache-to <registry>                Push cache to specified registry"
    echo "  --cache-from-to <registry>           Use and update registry cache"
    echo "  -h, --help                           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --base                         # Quick build for testing base system"
    echo "  $0 --base-nvim                    # Build with nvim plugins installed"
    echo "  $0 --base-nvim-vscode --test      # Build with nvim + VS Code and test it"
    echo "  $0 --full --no-cache              # Full clean build"
    echo "  $0 --full --cache-from-to ghcr.io/user/repo  # Use registry cache"
    exit 0
    ;;
  *)
    echo "Unknown option $1"
    echo "Use --help for usage information"
    exit 1
    ;;
  esac
done

echo "🏗️  Building dev container image (target: ${BUILD_TARGET})..."

# Use target-specific cache keys for better cache isolation
TARGET_CACHE_MODE=""
if [ -n "$CACHE_REGISTRY" ]; then
  if [[ "$CACHE_MODE" == *"--cache-from"* ]]; then
    TARGET_CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache:${BUILD_TARGET}"
  fi
  if [[ "$CACHE_MODE" == *"--cache-to"* ]]; then
    TARGET_CACHE_MODE="${TARGET_CACHE_MODE} --cache-to type=registry,ref=${CACHE_REGISTRY}/cache:${BUILD_TARGET},mode=max"
  fi
else
  TARGET_CACHE_MODE="$CACHE_MODE"
fi

# Use docker buildx for better caching support
# Image reference and metadata file path
IMAGE_REF="${CONTAINER_NAME}:${IMAGE_TAG}"
METADATA_FILE="build/build_metadata.json"
mkdir -p "$(dirname "$METADATA_FILE")"

# Build the image with BuildKit metadata for compressed size, and load locally
if docker buildx build ${NO_CACHE} ${DEBUG_MODE} ${TARGET_CACHE_MODE} \
  --progress=plain \
  --target "${BUILD_TARGET}" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --metadata-file "${METADATA_FILE}" \
  --load \
  -t "${IMAGE_REF}" \
  .; then
  echo "✅ Container built successfully!"
else
  build_exit_code=$?
  echo
  echo "❌ Container build failed!"
  exit $build_exit_code
fi

# Helper to render bytes to human size without requiring numfmt
human_size() {
  local my_bytes="$1"
  awk -v b="$my_bytes" '
    function human(x){
      split("B K M G T P", u, " ")
      i=1
      while (x>=1024 && i<6){ x/=1024; i++ }
      if (x>=100) printf("%.0f%s\n", x, u[i]);
      else if (x>=10) printf("%.1f%s\n", x, u[i]);
      else printf("%.2f%s\n", x, u[i]);
    } BEGIN { human(b) }'
}

# Print compressed (push) size from BuildKit metadata if available
if command -v jq >/dev/null 2>&1 && [ -s "${METADATA_FILE}" ]; then
  compressed_bytes=$(jq -r '."containerimage.descriptor".size // empty' "${METADATA_FILE}" || true)
  if [ -n "${compressed_bytes}" ] && [ "${compressed_bytes}" != "null" ]; then
    echo "📦 Compressed (push) size: $(human_size "${compressed_bytes}")"
  else
    echo "📦 Compressed (push) size: unavailable (no descriptor in metadata)"
  fi
else
  echo "📦 Compressed (push) size: unavailable (metadata file missing or jq not installed)"
fi

# Print uncompressed local image size
uncompressed_bytes=$(docker image inspect "${IMAGE_REF}" --format '{{.Size}}' 2>/dev/null || true)
if [ -n "${uncompressed_bytes}" ]; then
  echo "🗜️  Uncompressed (local) size: $(human_size "${uncompressed_bytes}")"
else
  echo "🗜️  Uncompressed (local) size: unavailable"
fi

# Show recent layer sizes/commands for quick feedback
if docker history --no-trunc "${IMAGE_REF}" >/dev/null 2>&1; then
  echo "📚 Layer history (most recent first):"
  docker history --no-trunc "${IMAGE_REF}" | sed -n '1,15p'
fi

# Optionally test the container
if [ "$TEST_CONTAINER" = "true" ]; then
  echo "🧪 Testing container..."
  TEST_FAIL=0

  echo "🔧 Testing basic system tools..."
  run_in_container "which zsh"
  run_in_container "R --version"

  if [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_vscode || TEST_FAIL=1
  fi

  # LaTeX presence by stages
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_latex_basic || TEST_FAIL=1

    if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ]; then
      echo "🚫 Verifying Pandoc is NOT installed in tex stage..."
      if run_in_container "which pandoc"; then
        echo "⚠️  Pandoc found but should not be in tex stage"
        TEST_FAIL=1
      else
        echo "✅ Pandoc correctly absent from tex stage"
      fi
    fi
  fi

  # Pandoc tests
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_pandoc || TEST_FAIL=1
  fi

  # Extra LaTeX packages
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_pandoc_plus || TEST_FAIL=1
  fi

  echo "📋 Checking for copied configuration files..."
  run_in_container 'ls -la /home/me/ | grep -E "\.(zprofile|tmux\.conf|lintr|Rprofile|bash_profile|npmrc)$"'

  # nvim stages and later
  if [ "$BUILD_TARGET" = "base-nvim" ] || [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_nvim_and_plugins || TEST_FAIL=1
  fi

  test_dev_tools || TEST_FAIL=1

  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "📦 Testing R package installation..."
    if ! run_in_container 'R -e "cat(\"Installed packages:\", length(.packages(all.available=TRUE)), \"\n\")"'; then
      TEST_FAIL=1
    fi
  fi

  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_python313 || TEST_FAIL=1
  fi

  if [ "$TEST_FAIL" -eq 0 ]; then
    echo "✅ Container tests passed!"
  else
    echo "❌ Container tests failed"
    exit 1
  fi
fi

echo "🎉 Done! You can now:"
case "$BUILD_TARGET" in
"base")
  echo "  • Test the base stage with: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Build with nvim plugins next with: ./build-container.sh --base-nvim"
  ;;
"base-nvim")
  echo "  • Test the base-nvim stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test nvim with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} nvim --version"
  echo "  • Build with VS Code next with: ./build-container.sh --base-nvim-vscode"
  ;;
"base-nvim-vscode")
  echo "  • Test the base-nvim-vscode stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test VS Code with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} ls -la /home/me/.vscode-server/bin/"
  echo "  • Build with LaTeX next with: ./build-container.sh --base-nvim-vscode-tex"
  ;;
"base-nvim-vscode-tex")
  echo "  • Test the base-nvim-vscode-tex stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test LaTeX with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} xelatex --version | head -n 1"
  echo "  • Build with LaTeX + Pandoc next with: ./build-container.sh --base-nvim-vscode-tex-pandoc"
  ;;
"base-nvim-vscode-tex-pandoc")
  echo "  • Test the base-nvim-vscode-tex-pandoc stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Pandoc with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc --version | head -n 1"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref-plus"
  ;;
"base-nvim-vscode-tex-pandoc-haskell")
  echo "  • Test the base-nvim-vscode-tex-pandoc-haskell stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Stack with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} stack --version"
  echo "  • Build with pandoc-crossref next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref"
  ;;
"base-nvim-vscode-tex-pandoc-haskell-crossref")
  echo "  • Test the base-nvim-vscode-tex-pandoc-haskell-crossref stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test pandoc-crossref with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc-crossref --version"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref-plus"
  ;;
"base-nvim-vscode-tex-pandoc-haskell-crossref-plus")
  echo "  • Test the base-nvim-vscode-tex-pandoc-haskell-crossref-plus stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test soul package with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} kpsewhich soul.sty"
  echo "  • Build with R packages next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r"
  ;;
"base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r")
  echo "  • Test the base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test R packages with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} R -e 'cat(\"Installed packages:\", length(.packages(all.available=TRUE)), \"\n\")'"
  echo "  • Build with Python 3.13 next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py"
  ;;
"base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py")
  echo "  • Test the base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Python 3.13 with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} python3.13 --version"
  echo "  • Build the full version with: ./build-container.sh --full"
  ;;
"full")
  echo "  • Test the full stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Tag and push to GitHub Container Registry:"
  echo "    docker tag ${CONTAINER_NAME}:${IMAGE_TAG} ghcr.io/jbearak/${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "    docker push ghcr.io/jbearak/${CONTAINER_NAME}:${IMAGE_TAG}"
  ;;
esac
echo "  • Reference in other projects' devcontainer.json files"
