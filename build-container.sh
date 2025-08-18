#!/bin/bash
# This script builds the development container image. It supports building specific Dockerfile targets and optional post-build tests.

# build-container.sh - Build and optionally test the dev container

set -e

CONTAINER_NAME="base-container"
IMAGE_TAG="latest"
BUILD_TARGET="" # Will be set to build both full-container and r-container if not specified
# Note: BUILD_MULTIPLE starts as false but gets set to true later if BUILD_TARGET remains empty.
# This allows the script to default to building both containers when no specific target is given,
# while still supporting single-target builds when a specific --target flag is used.
BUILD_MULTIPLE=false
DEBUG_MODE=""
CACHE_REGISTRY=""
CACHE_MODE=""

# Helpers to reduce duplication in docker run checks
build_single_target() {
  local target="$1"
  # For the current targets, container_name and image_tag are the same as target
  local container_name="$target"
  local image_tag="$target"
  
  echo "🏗️  Building target: ${target}..."
  
  # Use target-specific cache keys for better cache isolation
  local TARGET_CACHE_MODE=""
  # -n = "Not empty" (has coNteNt), -z = "Zero length" (empty)
  if [ -n "$CACHE_REGISTRY" ]; then  # If CACHE_REGISTRY is NOT empty (user provided a registry URL)
    if [[ "$CACHE_MODE" == *"--cache-from"* ]]; then
      TARGET_CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache:${target}"
    fi
    if [[ "$CACHE_MODE" == *"--cache-to"* ]]; then
      TARGET_CACHE_MODE="${TARGET_CACHE_MODE} --cache-to type=registry,ref=${CACHE_REGISTRY}/cache:${target},mode=max"
    fi
  else  # If CACHE_REGISTRY IS empty (no registry specified)
    # If no registry cache is specified, use local cache by default (unless --no-cache is used)
    if [ -z "$NO_CACHE" ]; then  # If NO_CACHE is empty (meaning caching is enabled)
      # Use per-target cache paths to avoid cross-target contamination
      local cache_path="/tmp/.buildx-cache/${target}"
      TARGET_CACHE_MODE="--cache-from type=local,src=${cache_path} --cache-to type=local,dest=${cache_path},mode=max"
      echo "🗂️  Using local BuildKit cache at ${cache_path}"
    else  # If NO_CACHE has content (meaning --no-cache was used)
      TARGET_CACHE_MODE="$CACHE_MODE"
    fi
  fi

  # Image reference and metadata file path
  IMAGE_REF="${container_name}:${image_tag}"
  METADATA_FILE="build/build_metadata_${target}.json"
  mkdir -p "$(dirname "$METADATA_FILE")"

  # Build the image with BuildKit metadata for compressed size, and load locally
  if docker buildx build ${NO_CACHE} ${DEBUG_MODE} ${TARGET_CACHE_MODE} \
    --progress=plain \
    --target "${target}" \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --metadata-file "${METADATA_FILE}" \
    --load \
    -t "${IMAGE_REF}" \
    .; then
    echo "✅ Container built successfully for target: ${target}!"
  else
    build_exit_code=$?
    echo
    echo "❌ Container build failed for target: ${target}!"
    return $build_exit_code
  fi

  # Print size information
  print_size_info "$IMAGE_REF" "$METADATA_FILE"
  
  return 0
}

# Function to print size information
print_size_info() {
  local image_ref="$1"
  local metadata_file="$2"
  
  # Print compressed (push) size from BuildKit metadata if available
  # command -v checks if 'jq' (JSON processor) is installed, >/dev/null 2>&1 hides output
  # [ -s "${metadata_file}" ] checks if the metadata file exists and is not empty
  if command -v jq >/dev/null 2>&1 && [ -s "${metadata_file}" ]; then
    # jq extracts the container image size from JSON metadata
    # -r = raw output (no quotes), // empty = fallback if field doesn't exist
    # || true prevents script from failing if jq command has issues
    compressed_bytes=$(jq -r '."containerimage.descriptor".size // empty' "${metadata_file}" || true)
    # Check if we got a valid size value (not empty and not JSON null)
    if [ -n "${compressed_bytes}" ] && [ "${compressed_bytes}" != "null" ]; then
      echo "📦 Compressed (push) size: $(human_size "${compressed_bytes}")"
    else
      echo "📦 Compressed (push) size: unavailable (no descriptor in metadata)"
    fi
  else
    echo "📦 Compressed (push) size: unavailable (metadata file missing or jq not installed)"
  fi

  # Print uncompressed local image size
  uncompressed_bytes=$(docker image inspect "${image_ref}" --format '{{.Size}}' 2>/dev/null || true)
  if [ -n "${uncompressed_bytes}" ]; then
    echo "🗜️  Uncompressed (local) size: $(human_size "${uncompressed_bytes}")"
  else
    echo "🗜️  Uncompressed (local) size: unavailable"
  fi

  # Show recent layer sizes/commands for quick feedback
  if docker history --no-trunc "${image_ref}" >/dev/null 2>&1; then
    echo "📚 Layer history (most recent first):"
    docker history --no-trunc "${image_ref}" | sed -n '1,15p'
  fi
}
run_in_container() {
  local container_ref="$1"
  local my_cmd="$2"
  docker run --rm "${container_ref}" bash -lc "$my_cmd"
}

check_cmd() {
  local my_description="$1"
  local container_ref="$2"
  local my_cmd="$3"
  echo "$my_description"
  if run_in_container "$container_ref" "$my_cmd" >/dev/null 2>&1; then
    return 0
  else
    echo "⚠️  ${my_description} failed"
    return 1
  fi
}

test_vscode() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "📦 Testing VS Code server installation..."
  if ! run_in_container "$container_ref" "ls -la /home/me/.vscode-server/bin/"; then
    echo "⚠️  VS Code server test failed"
    return 1
  fi
  return 0
}

test_latex_basic() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "📄 Testing LaTeX installation..."
  if ! run_in_container "$container_ref" "xelatex --version | head -n 1"; then
    echo "⚠️  XeLaTeX test failed"
    return 1
  fi
  return 0
}

test_pandoc() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "📄 Testing Pandoc installation and functionality..."
  run_in_container "$container_ref" "pandoc --version | head -n 1" || {
    echo "⚠️  Pandoc version test failed"
    return 1
  }
  echo "📝 Running comprehensive Pandoc tests (docx, pdf, citations)..."
  if docker run --rm -v "$(pwd)":/workspace -w /workspace "$container_ref" ./test_pandoc.sh; then
    return 0
  else
    echo "⚠️  Comprehensive Pandoc tests failed"
    return 1
  fi
}

test_pandoc_plus() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "🔍 Testing tlmgr soul package..."
  run_in_container "$container_ref" "kpsewhich soul.sty" || {
    echo "⚠️ soul.sty missing"
    return 1
  }
}

test_python313() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "🐍 Testing Python 3.13 installation..."
  run_in_container "$container_ref" "python3.13 --version" || {
    echo "⚠️ Python 3.13 not available"
    return 1
  }
  run_in_container "$container_ref" "python3.13 -c 'import sys; print(f\"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}\")'" || {
    echo "⚠️ Python 3.13 execution test failed"
    return 1
  }
}

test_nvim_and_plugins() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "📝 Testing nvim and plugins..."
  run_in_container "$container_ref" "nvim --version" || {
    echo "⚠️  nvim not available"
    return 1
  }
  run_in_container "$container_ref" "ls -la /home/me/.local/share/nvim/lazy/" || {
    echo "⚠️  lazy.nvim plugins not found"
    return 1
  }
}

test_dev_tools() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "🛠️  Testing development tools..."
  local my_fail=0
  check_cmd "Checking Yarn..." "$container_ref" "yarn --version" || my_fail=1
  check_cmd "Checking fd..." "$container_ref" 'env PATH="/home/me/.local/bin:$PATH" fd --version' || my_fail=1
  check_cmd "Checking eza..." "$container_ref" "eza --version" || my_fail=1
  # gotests does not support --version; -h confirms presence
  check_cmd "Checking gotests..." "$container_ref" 'env GOPATH="/home/me/go" PATH="/home/me/go/bin:/usr/local/go/bin:$PATH" gotests -h >/dev/null' || my_fail=1
  check_cmd "Checking tree-sitter..." "$container_ref" 'env PATH="/home/me/.local/bin:$PATH" tree-sitter --version' || my_fail=1
  return $my_fail
}

test_r_container_optimized() {
  local container_ref="${1:-${CONTAINER_NAME}:${IMAGE_TAG}}"
  echo "🔬 Testing r-container optimizations..."
  local my_fail=0
  
  # Test that build tools are removed
  echo "  Verifying build tools removal..."
  if run_in_container "$container_ref" "command -v gcc >/dev/null 2>&1"; then
    echo "    ❌ gcc still present"
    my_fail=1
  else
    echo "    ✅ gcc removed"
  fi
  
  if run_in_container "$container_ref" "command -v make >/dev/null 2>&1"; then
    echo "    ❌ make still present"
    my_fail=1
  else
    echo "    ✅ make removed"
  fi
  
  if run_in_container "$container_ref" "dpkg -l | grep -q r-base-dev"; then
    echo "    ❌ r-base-dev still present"
    my_fail=1
  else
    echo "    ✅ r-base-dev removed"
  fi
  
  # Test that git-lfs is present
  echo "  Verifying git-lfs availability..."
  if run_in_container "$container_ref" "git lfs version >/dev/null 2>&1"; then
    echo "    ✅ git-lfs available"
  else
    echo "    ❌ git-lfs missing"
    my_fail=1
  fi
  
  # Test that essential R packages work (including geospatial)
  echo "  Testing essential R packages (including geospatial)..."
  if run_in_container "$container_ref" 'R -e "library(dplyr); library(ggplot2); library(sf); cat(\"✅ Essential packages including geospatial loaded\\n\")"' >/dev/null 2>&1; then
    echo "    ✅ Essential R packages including geospatial working"
  else
    echo "    ❌ Essential R packages failed"
    my_fail=1
  fi
  
  # Test that only Stan packages are excluded
  echo "  Verifying only Stan packages exclusion..."
  if run_in_container "$container_ref" 'R -e "quit(status=if(require(rstan, quietly=TRUE)) 1 else 0)"' >/dev/null 2>&1; then
    echo "    ✅ Stan packages excluded (as expected)"
  else
    echo "    ❌ Stan packages still present"
    my_fail=1
  fi
  
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

  --base-nvim-tex)
    BUILD_TARGET="base-nvim-tex"
    IMAGE_TAG="base-nvim-tex"
    echo "📚 Building image with LaTeX stack (no Pandoc)..."
    shift
    ;;
  --base-nvim-tex-pandoc)
    BUILD_TARGET="base-nvim-tex-pandoc"
    IMAGE_TAG="base-nvim-tex-pandoc"
    echo "📚 Building image with LaTeX + Pandoc..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell"
    echo "📚⚡ Building image with LaTeX + Pandoc + Haskell..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref"
    echo "📚🔀 Building image with LaTeX + Pandoc + Haskell + pandoc-crossref..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref-plus)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref-plus"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref-plus"
    echo "📚➕ Building image with extra LaTeX packages..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref-plus-py)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref-plus-py"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref-plus-py"
    echo "🐍 Building image with Python 3.13..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref-plus-py-r"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref-plus-py-r"
    echo "📐 Building image with R installation..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak"
    echo "📦 Building image with R packages installed..."
    shift
    ;;
  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode)
    BUILD_TARGET="base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode"
    IMAGE_TAG="base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode"
    echo "🖥️  Building image with VS Code server and extensions..."
    shift
    ;;
  --r-container)
    BUILD_TARGET="r-container"
    IMAGE_TAG="r-container"
    CONTAINER_NAME="r-container"
    echo "📊 Building optimized R container for CI/CD (build tools removed after package installation)..."
    shift
    ;;
  --full)
    BUILD_TARGET="full-container"
    IMAGE_TAG="full-container"
    CONTAINER_NAME="full-container"
    echo "🏗️  Building complete development environment..."
    shift
    ;;
  --full-container)
    BUILD_TARGET="full-container"
    IMAGE_TAG="full-container"
    CONTAINER_NAME="full-container"
    echo "🏗️  Building complete development environment..."
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
    echo "  --base-nvim-tex                      Build base + nvim + LaTeX (no Pandoc)"
    echo "  --base-nvim-tex-pandoc               Build base + nvim + LaTeX + Pandoc"
    echo "  --base-nvim-tex-pandoc-haskell       Build base + nvim + LaTeX + Pandoc + Haskell"
    echo "  --base-nvim-tex-pandoc-haskell-crossref Build base + nvim + LaTeX + Pandoc + Haskell + crossref"
    echo "  --base-nvim-tex-pandoc-haskell-crossref-plus   Build base + nvim + LaTeX + Pandoc + extra packages"
    echo "  --base-nvim-tex-pandoc-haskell-crossref-plus-py Build base + nvim + LaTeX + Pandoc + extra packages + Python 3.13"
    echo "  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r Build base + nvim + LaTeX + Pandoc + extra packages + Python 3.13 + R installation"
    echo "  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak Build base + nvim + LaTeX + Pandoc + extra packages + Python 3.13 + R installation + R packages"
    echo "  --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode Build base + nvim + LaTeX + Pandoc + extra packages + Python 3.13 + R installation + R packages + VS Code"

    echo "  --r-container                        Build optimized R container for CI/CD (aggressive size optimization)"
    echo "  --full-container                     Build complete development environment"
    echo "  --full                               alias for --full-container"
    echo ""
    echo "Other Options:"
    echo "  --debug                              Show verbose R package installation logs (default: quiet)"
    echo "  --test                               Run tests after building"
    echo "  --no-cache                           Build without using any cache (local or registry)"
    echo "  --cache-from <registry>              Use registry cache from specified registry (e.g., ghcr.io/user/repo)"
    echo "  --cache-to <registry>                Push cache to specified registry"
    echo "  --cache-from-to <registry>           Use and update registry cache"
    echo "  -h, --help                           Show this help message"
    echo ""
    echo "Caching:"
    echo "  By default, local BuildKit cache is used for faster rebuilds."
    echo "  Use --no-cache to disable all caching."
    echo "  Use --cache-from-to <registry> for shared registry cache."
    echo ""
    echo "Examples:"
    echo "  $0 --base                         # Quick build for testing base system"
    echo "  $0 --base-nvim                    # Build with nvim plugins installed"
    echo "  $0 --base-nvim-tex --test          # Build with nvim + LaTeX and test it"
    echo "  $0 --base-nvim-tex-pandoc-haskell-crossref-plus-py  # Build with Python 3.13"
    echo "  $0 --base-nvim-tex-pandoc-haskell-crossref-plus-py-r  # Build with Python + R installation"
    echo "  $0 --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak  # Build with Python + R + R packages"
    echo "  $0 --full --no-cache              # Full clean build"
    echo "  $0 --full --cache-from-to ghcr.io/user/repo  # Use registry cache"
    echo "  $0                                # Build both full-container and r-container (default)"
    exit 0
    ;;
  *)
    echo "Unknown option $1"
    echo "Use --help for usage information"
    exit 1
    ;;
  esac
done

# If no target was specified, build both full-container and r-container
if [ -z "$BUILD_TARGET" ]; then
  BUILD_MULTIPLE=true
  echo "🏗️  No target specified - building both full-container and r-container..."
else
  echo "🏗️  Building dev container image (target: ${BUILD_TARGET})..."
fi

# Helper function to print container usage examples
# print_container_usage
# Prints usage examples for a given container image.
# Arguments:
#   $1 - container_name: Name of the container (e.g., "r-container" or "full-container").
#   $2 - image_tag: Tag of the container image (e.g., "latest").
#   $3 - is_single_target (optional): If "true", prints additional commands for testing and pushing the image.
#        If omitted or "false", prints only basic usage examples.
print_container_usage() {
  local container_name="$1"
  local image_tag="$2"
  local is_single_target="${3:-false}"
  
  case "$container_name" in
    "r-container")
      echo "  • Test the R container: docker run -it --rm -v \$(pwd):/workspace ${container_name}:${image_tag}"
      if [ "$is_single_target" = "true" ]; then
        echo "  • Test R installation: docker run --rm ${container_name}:${image_tag} R --version"
        echo "  • Test R packages: docker run --rm ${container_name}:${image_tag} R -e 'installed.packages()[1:5,1]'"
        echo "  • Tag and push to GitHub Container Registry:"
        echo "    docker tag ${container_name}:${image_tag} ghcr.io/jbearak/${container_name}:${image_tag}"
        echo "    docker push ghcr.io/jbearak/${container_name}:${image_tag}"
      fi
      ;;
    "full-container")
      echo "  • Test the full development container: docker run -it --rm -v \$(pwd):/workspaces/project ${container_name}:${image_tag}"
      if [ "$is_single_target" = "true" ]; then
        echo "  • Tag and push to GitHub Container Registry:"
        echo "    docker tag ${container_name}:${image_tag} ghcr.io/jbearak/${container_name}:${image_tag}"
        echo "    docker push ghcr.io/jbearak/${container_name}:${image_tag}"
      fi
      ;;
  esac
}

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

# Main build logic
if [ "$BUILD_MULTIPLE" = "true" ]; then
  # Build both targets - continue even if one fails to get aggregate result
  BUILD_FAILED=0
  
  echo "🚀 Building full-container..."
  if ! build_single_target "full-container"; then
    echo "❌ Failed to build full-container"
    BUILD_FAILED=1
  else
    echo "✅ full-container built successfully!"
  fi
  
  echo ""
  echo "🚀 Building r-container..."
  if ! build_single_target "r-container"; then
    echo "❌ Failed to build r-container"
    BUILD_FAILED=1
  else
    echo "✅ r-container built successfully!"
  fi
  
  echo ""
  if [ "$BUILD_FAILED" -eq 0 ]; then
    echo "✅ Both containers built successfully!"
  else
    echo "❌ One or more container builds failed"
    exit 1
  fi
  
else
  # Build single target
  # Set container name and image tag based on target
  case "$BUILD_TARGET" in
    "r-container")
      CONTAINER_NAME="r-container"
      IMAGE_TAG="r-container"
      ;;
    "full-container")
      CONTAINER_NAME="full-container"
      IMAGE_TAG="full-container"
      ;;
  esac
  
  if ! build_single_target "$BUILD_TARGET"; then
    echo "❌ Failed to build $BUILD_TARGET"
    exit 1
  fi
fi

# Optionally test the container
if [ "$TEST_CONTAINER" = "true" ]; then
  if [ "$BUILD_MULTIPLE" = "true" ]; then
    echo "🧪 Testing both containers..."
    
    # Track overall test results
    OVERALL_TEST_FAIL=0
    
    # Test full-container
    echo "🧪 Testing full-container..."
    BUILD_TARGET="full-container"
    CONTAINER_NAME="full-container"
    IMAGE_TAG="full-container"
    TEST_FAIL=0
    local full_container_ref="full-container:full-container"
    
    echo "🔧 Testing basic system tools..."
    run_in_container "$full_container_ref" "which zsh"
    run_in_container "$full_container_ref" "R --version"
    
    test_vscode "$full_container_ref" || TEST_FAIL=1
    test_latex_basic "$full_container_ref" || TEST_FAIL=1
    test_pandoc "$full_container_ref" || TEST_FAIL=1
    test_pandoc_plus "$full_container_ref" || TEST_FAIL=1
    test_nvim_and_plugins "$full_container_ref" || TEST_FAIL=1
    test_dev_tools "$full_container_ref" || TEST_FAIL=1
    test_python313 "$full_container_ref" || TEST_FAIL=1
    
    echo "📋 Checking for copied configuration files..."
    run_in_container "$full_container_ref" 'ls -la /home/me/ | grep -E "\.(zprofile|tmux\.conf|lintr|Rprofile|bash_profile|npmrc)$"'
    
    if [ "$TEST_FAIL" -eq 0 ]; then
      echo "✅ full-container tests passed!"
    else
      echo "❌ full-container tests failed"
      OVERALL_TEST_FAIL=1
    fi
    
    # Test r-container
    echo ""
    echo "🧪 Testing r-container..."
    BUILD_TARGET="r-container"
    CONTAINER_NAME="r-container"
    IMAGE_TAG="r-container"
    TEST_FAIL=0
    local r_container_ref="r-container:r-container"
    
    echo "🔧 Testing basic system tools..."
    run_in_container "$r_container_ref" "which zsh"
    run_in_container "$r_container_ref" "R --version"
    
    test_r_container_optimized "$r_container_ref" || TEST_FAIL=1
    
    if [ "$TEST_FAIL" -eq 0 ]; then
      echo "✅ r-container tests passed!"
    else
      echo "❌ r-container tests failed"
      OVERALL_TEST_FAIL=1
    fi
    
    # Report aggregate test results
    if [ "$OVERALL_TEST_FAIL" -eq 0 ]; then
      echo "✅ All container tests passed!"
    else
      echo "❌ One or more container tests failed"
      exit 1
    fi
    
  else
    # Single target testing (existing logic)
    echo "🧪 Testing container..."
    TEST_FAIL=0
    local container_ref="${CONTAINER_NAME}:${IMAGE_TAG}"

    echo "🔧 Testing basic system tools..."
    run_in_container "$container_ref" "which zsh"
    run_in_container "$container_ref" "R --version"

    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_vscode "$container_ref" || TEST_FAIL=1
    fi

    # LaTeX presence by stages
    if [ "$BUILD_TARGET" = "base-nvim-tex" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_latex_basic "$container_ref" || TEST_FAIL=1

      if [ "$BUILD_TARGET" = "base-nvim-tex" ]; then
        echo "🚫 Verifying Pandoc is NOT installed in tex stage..."
        if run_in_container "$container_ref" "which pandoc"; then
          echo "⚠️  Pandoc found but should not be in tex stage"
          TEST_FAIL=1
        else
          echo "✅ Pandoc correctly absent from tex stage"
        fi
      fi
    fi

    # Pandoc tests
    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_pandoc "$container_ref" || TEST_FAIL=1
    fi

    # Extra LaTeX packages
    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_pandoc_plus "$container_ref" || TEST_FAIL=1
    fi

    echo "📋 Checking for copied configuration files..."
    run_in_container "$container_ref" 'ls -la /home/me/ | grep -E "\.(zprofile|tmux\.conf|lintr|Rprofile|bash_profile|npmrc)$"'

    # nvim stages and later
    if [ "$BUILD_TARGET" = "base-nvim" ] || [ "$BUILD_TARGET" = "base-nvim-tex" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_nvim_and_plugins "$container_ref" || TEST_FAIL=1
    fi

    # Dev tools are intentionally not present in r-container
    if [ "$BUILD_TARGET" != "r-container" ]; then
      test_dev_tools "$container_ref" || TEST_FAIL=1
    fi

    # R installation tests (new stage 10)
    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "full-container" ] || [ "$BUILD_TARGET" = "r-container" ]; then
      echo "📐 Testing R installation..."
      run_in_container "$container_ref" "R --version" || TEST_FAIL=1
      # CmdStan is not included in r-container
      if [ "$BUILD_TARGET" != "r-container" ]; then
        run_in_container "$container_ref" "ls -la /opt/cmdstan/bin/" || TEST_FAIL=1
      fi
      run_in_container "$container_ref" "which jags" || TEST_FAIL=1
    fi

    # R package tests (moved to stage 11)
    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "full-container" ] || [ "$BUILD_TARGET" = "r-container" ]; then
      echo "📦 Testing R package installation..."
      if ! run_in_container "$container_ref" 'R -e "cat(\"Installed packages:\", length(.packages(all.available=TRUE)), \"\n\")"'; then
        TEST_FAIL=1
      fi
    fi

    # r-container specific optimization tests
    if [ "$BUILD_TARGET" = "r-container" ]; then
      test_r_container_optimized "$container_ref" || TEST_FAIL=1
    fi

    # Python tests (moved to stage 9)
    if [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r" ] || [ "$BUILD_TARGET" = "base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak" ] || [ "$BUILD_TARGET" = "full-container" ]; then
      test_python313 "$container_ref" || TEST_FAIL=1
    fi

    if [ "$TEST_FAIL" -eq 0 ]; then
      echo "✅ Container tests passed!"
    else
      echo "❌ Container tests failed"
      exit 1
    fi
  fi
fi

echo "🎉 Done! You can now:"

if [ "$BUILD_MULTIPLE" = "true" ]; then
  print_container_usage "full-container" "full-container"
  print_container_usage "r-container" "r-container"
  echo "  • Tag and push both containers to GitHub Container Registry:"
  echo "    ./push-to-ghcr.sh -a"
  echo "  • Reference in other projects' devcontainer.json files"
else
  case "$BUILD_TARGET" in
"base")
  echo "  • Test the base stage with: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Build with nvim plugins next with: ./build-container.sh --base-nvim"
  ;;
"base-nvim")
  echo "  • Test the base-nvim stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test nvim with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} nvim --version"
  echo "  • Build with LaTeX next with: ./build-container.sh --base-nvim-tex"
  ;;
"base-nvim-tex")
  echo "  • Test the base-nvim-tex stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test LaTeX with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} xelatex --version | head -n 1"
  echo "  • Build with Pandoc next with: ./build-container.sh --base-nvim-tex-pandoc"
  ;;
"base-nvim-tex-pandoc")
  echo "  • Test the base-nvim-tex-pandoc stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Pandoc with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc --version | head -n 1"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus"
  ;;
"base-nvim-tex-pandoc-haskell")
  echo "  • Test the base-nvim-tex-pandoc-haskell stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Stack with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} stack --version"
  echo "  • Build with pandoc-crossref next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref"
  ;;
"base-nvim-tex-pandoc-haskell-crossref")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test pandoc-crossref with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc-crossref --version"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus"
  ;;
"base-nvim-tex-pandoc-haskell-crossref-plus")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref-plus stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test soul package with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} kpsewhich soul.sty"
  echo "  • Build with Python 3.13 next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus-py"
  ;;
"base-nvim-tex-pandoc-haskell-crossref-plus-py")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref-plus-py stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Python 3.13 with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} python3.13 --version"
  echo "  • Build with R installation next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus-py-r"
  ;;
"base-nvim-tex-pandoc-haskell-crossref-plus-py-r")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref-plus-py-r stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test R installation with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} R --version"
  echo "  • Test CmdStan with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} ls -la /opt/cmdstan/bin/"
  echo "  • Test JAGS with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} which jags"
  echo "  • Build with R packages next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak"
  ;;
"base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test R packages with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} R -e 'cat(\"Installed packages:\", length(.packages(all.available=TRUE)), \"\n\")'"
  echo "  • Build with VS Code next with: ./build-container.sh --base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode"
  ;;
"base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode")
  echo "  • Test the base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test VS Code with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} ls -la /home/me/.vscode-server/bin/"
  echo "  • Build full environment next with: ./build-container.sh --full"
  ;;
"r-container")
  print_container_usage "r-container" "${IMAGE_TAG}" "true"
  ;;
  "full-container")
    print_container_usage "full-container" "${IMAGE_TAG}" "true"
    ;;
  esac
  echo "  • Reference in other projects' devcontainer.json files"
fi
