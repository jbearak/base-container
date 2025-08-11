#!/bin/bash
# build-pak-container.sh - Build script for pak-based R container (Phase 2)

set -euo pipefail

# Configuration
IMAGE_NAME="base-container"
TAG_PREFIX="pak-phase2"
DEBUG_PACKAGES=false
BUILD_ARGS=""
CACHE_MODE=""
CACHE_REGISTRY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build pak-based R container with BuildKit cache optimization.

Options:
    -h, --help              Show this help message
    -d, --debug             Enable debug mode for R package installation
    -t, --tag TAG           Custom tag suffix (default: pak-phase2)
    --no-cache              Disable BuildKit cache
    --cache-from-to <registry>  Use and update registry cache
    --build-arg ARG=VALUE   Pass build argument to Docker

Examples:
    $0                      # Build with default settings
    $0 --debug              # Build with debug output
    $0 --tag test           # Build with custom tag
    $0 --no-cache           # Build without cache
    $0 --cache-from-to ghcr.io/jbearak/base-container  # Use registry cache

Targets:
    pak-base                # pak-based R installation only
    pak-full                # Complete pak-based container (default)

EOF
}

# Parse command line arguments
USE_CACHE=true
TARGET="pak-full"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--debug)
            DEBUG_PACKAGES=true
            shift
            ;;
        -t|--tag)
            TAG_PREFIX="$2"
            shift 2
            ;;
        --no-cache)
            USE_CACHE=false
            shift
            ;;
        --cache-from-to)
            CACHE_REGISTRY="$2"
            CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache:pak-full --cache-to type=registry,ref=${CACHE_REGISTRY}/cache:pak-full,mode=max"
            print_status "🔄 Using and updating registry cache: ${CACHE_REGISTRY}/cache:pak-full"
            shift 2
            ;;
        --build-arg)
            BUILD_ARGS="$BUILD_ARGS --build-arg $2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate Docker and BuildKit
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if BuildKit is available
    if ! docker buildx version >/dev/null 2>&1; then
        print_warning "Docker BuildKit not available, falling back to legacy builder"
        USE_CACHE=false
    fi
    
    print_success "Prerequisites check passed"
}

# Build the container
build_container() {
    local dockerfile="Dockerfile.pak"
    local full_tag="${IMAGE_NAME}:${TAG_PREFIX}"
    
    print_status "Building pak-based container..."
    print_status "  Dockerfile: $dockerfile"
    print_status "  Target: $TARGET"
    print_status "  Tag: $full_tag"
    print_status "  Debug packages: $DEBUG_PACKAGES"
    print_status "  Use cache: $USE_CACHE"
    
    # Prepare build command
    local build_cmd="docker"
    
    if [[ "$USE_CACHE" == "true" ]]; then
        build_cmd="$build_cmd buildx build"
        # Add cache options if specified
        if [[ -n "$CACHE_MODE" ]]; then
            build_cmd="$build_cmd $CACHE_MODE"
        fi
    else
        build_cmd="$build_cmd build --no-cache"
    fi
    
    # Add build arguments
    build_cmd="$build_cmd --build-arg DEBUG_PACKAGES=$DEBUG_PACKAGES"
    build_cmd="$build_cmd $BUILD_ARGS"
    
    # Add target and tag
    build_cmd="$build_cmd --target $TARGET"
    build_cmd="$build_cmd --tag $full_tag"
    
    # Add dockerfile and context
    build_cmd="$build_cmd --file $dockerfile ."
    
    print_status "Executing: $build_cmd"
    echo
    
    # Record start time
    local start_time=$(date +%s)
    
    # Execute build
    if eval "$build_cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        echo
        print_success "Container built successfully!"
        print_success "  Image: $full_tag"
        print_success "  Build time: ${minutes}m ${seconds}s"
        
        # Show image size
        local image_size=$(docker images --format "table {{.Size}}" "$full_tag" | tail -n 1)
        print_success "  Image size: $image_size"
        
    else
        print_error "Container build failed!"
        exit 1
    fi
}

# Show build summary
show_summary() {
    local full_tag="${IMAGE_NAME}:${TAG_PREFIX}"
    
    echo
    print_status "=== BUILD SUMMARY ==="
    print_status "Image: $full_tag"
    print_status "Target: $TARGET"
    print_status "Features:"
    print_status "  ✓ pak-based R package management"
    print_status "  ✓ BuildKit cache optimization"
    print_status "  ✓ Architecture-segregated site libraries"
    print_status "  ✓ Enhanced error handling"
    
    echo
    print_status "To run the container:"
    echo "  docker run -it --rm $full_tag"
    
    echo
    print_status "To use with VS Code Dev Containers:"
    echo '  "image": "'$full_tag'"'
    
    echo
    print_status "To test R package installation:"
    echo "  docker run -it --rm $full_tag R -e 'library(pak); library(dplyr); library(ggplot2)'"
}

# Main execution
main() {
    print_status "🚀 pak-based R Container Builder (Phase 2)"
    echo
    
    check_prerequisites
    build_container
    show_summary
    
    print_success "🎉 Build completed successfully!"
}

# Run main function
main "$@"