#!/bin/bash
# Push container images to GitHub Container Registry (GHCR)

set -e

# Configuration
REGISTRY="ghcr.io"
REPO_OWNER="${REPO_OWNER:-${GITHUB_REPOSITORY_OWNER:-jbearak}}"  # Auto-detects in GitHub Actions
REPOSITORY="${REPO_OWNER}/base-container"
LOCAL_IMAGE_NAME="base-container"
DEFAULT_TAG="latest"
DEFAULT_TARGET="full-container"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Push Docker images to GitHub Container Registry (GHCR)

OPTIONS:
    -t, --target TARGET     Push specific target only (default: push all targets)
                           Available targets: full-container, r-container
    -g, --tag TAG          Tag for the image (default: $DEFAULT_TAG)
    -b, --build            Build the image before pushing
    -f, --force            Force push even if image doesn't exist locally
    -h, --help             Show this help message

EXAMPLES:
    $0                                         # Push all targets with latest tag
    $0 -t full-container                       # Push only full-container:latest
    $0 -t r-container -g v1.0.0              # Push only r-container:v1.0.0
    $0 -b                                     # Build and push all targets
    $0 --build --target full-container --tag dev   # Build and push only full-container:dev

PREREQUISITES:
    1. Docker must be installed and running
    2. You must be logged in to GHCR: docker login ghcr.io
    3. You must have push permissions to the repository

EOF
}

# Function to check if user is logged in to GHCR
check_ghcr_login() {
    print_status "Checking GHCR authentication..."
    
    # Check if credentials exist in Docker config
    if [[ -f ~/.docker/config.json ]] && grep -q "ghcr.io" ~/.docker/config.json 2>/dev/null; then
        print_success "GHCR authentication verified"
        return 0
    fi
    
    print_error "Not logged in to GHCR. Please run: docker login ghcr.io"
    exit 1
}

# Function to check if local image exists
check_local_image() {
    local target="$1"
    local tag="$2"

    # Try standard naming pattern (e.g., "base-container:latest")
    if docker image inspect "${LOCAL_IMAGE_NAME}:${tag}" >/dev/null 2>&1; then
        return 0
    fi

    # Try target-specific naming patterns (e.g., "full-container:full-container")
    local image_names=("${LOCAL_IMAGE_NAME}:${target}" "${target}:${tag}" "${target}:${target}")
    for image in "${image_names[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Function to build image
build_image() {
    local target="$1"
    local tag="$2"
    
    print_status "Building image for target: $target"
    
    if [[ -f "./build-container.sh" ]]; then
        print_status "Using existing build script..."
        case "$target" in
            "full-container")
                ./build-container.sh --full-container
                ;;
            "r-container")
                ./build-container.sh --r-container
                ;;
            *)
                print_error "Unknown target for build script: $target"
                return 1
                ;;
        esac
    else
        print_status "Building directly with docker..."
        docker build --target "$target" -t "${LOCAL_IMAGE_NAME}:${tag}" .
    fi
    
    print_success "Build completed for target: $target"
}

# Function to push image
push_image() {
    local target="$1"
    local tag="$2"
    local force="$3"
    
    local local_tag="$tag"
    local remote_image="${REGISTRY}/${REPOSITORY}:${tag}"
    
    # For r-container, use a different repository
    if [[ "$target" == "r-container" ]]; then
        remote_image="${REGISTRY}/${REPO_OWNER}/r-container:${tag}"
    fi
    
    # Check if local image exists
    if ! check_local_image "$target" "$tag" && [[ "$force" != "true" ]]; then
        print_error "Local image ${LOCAL_IMAGE_NAME}:${tag} not found. Use -b to build or -f to force."
        return 1
    fi
    
    # Determine which local image to use
    local source_image
    if docker image inspect "${LOCAL_IMAGE_NAME}:${tag}" >/dev/null 2>&1; then
        source_image="${LOCAL_IMAGE_NAME}:${tag}"
    elif docker image inspect "${LOCAL_IMAGE_NAME}:${target}" >/dev/null 2>&1; then
        source_image="${LOCAL_IMAGE_NAME}:${target}"
    elif docker image inspect "${target}:${tag}" >/dev/null 2>&1; then
        source_image="${target}:${tag}"
    elif docker image inspect "${target}:${target}" >/dev/null 2>&1; then
        source_image="${target}:${target}"
    else
        print_error "No suitable local image found"
        return 1
    fi
    
    print_status "Tagging image: $source_image -> $remote_image"
    docker tag "$source_image" "$remote_image"
    
    print_status "Pushing image: $remote_image"
    docker push "$remote_image"
    
    print_success "Successfully pushed: $remote_image"
}

# Parse command line arguments
TARGET=""  # Empty means push all targets (consistent with build script)
TAG="$DEFAULT_TAG"
BUILD_FIRST=false
PUSH_ALL=true  # Default to pushing all targets
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            PUSH_ALL=false  # Specific target means don't push all
            shift 2
            ;;
        -g|--tag)
            TAG="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_FIRST=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate target
VALID_TARGETS=("full-container" "r-container")
if [[ "$PUSH_ALL" == "false" ]]; then
    # Specific target was provided with -t flag
    if [[ ! " ${VALID_TARGETS[@]} " =~ " ${TARGET} " ]]; then
        print_error "Invalid target: $TARGET"
        print_error "Valid targets: ${VALID_TARGETS[*]}"
        exit 1
    fi
fi

# Main execution
print_status "Starting GHCR push process..."
print_status "Registry: $REGISTRY"
print_status "Repository: $REPOSITORY"

# Check prerequisites
check_ghcr_login

if [[ "$PUSH_ALL" == "true" ]]; then
    print_status "Pushing all targets..."
    for target in "${VALID_TARGETS[@]}"; do
        echo
        print_status "Processing target: $target"
        
        if [[ "$BUILD_FIRST" == "true" ]]; then
            build_image "$target" "$target"
        fi
        
        push_image "$target" "$TAG" "$FORCE"
    done
else
    print_status "Processing single target: $TARGET"
    
    if [[ "$BUILD_FIRST" == "true" ]]; then
        build_image "$TARGET" "$TAG"
    fi
    
    push_image "$TARGET" "$TAG" "$FORCE"
fi

print_success "All operations completed successfully!"

if [[ "$PUSH_ALL" == "true" ]]; then
    print_status "Pushed both containers:"
    print_status "  - full-container:${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
    print_status "  - r-container:${TAG} → https://github.com/${REPO_OWNER}/r-container/pkgs/container/r-container"
else
    print_status "Pushed single container:"
    if [[ "$TARGET" == "r-container" ]]; then
        print_status "  - ${TARGET}:${TAG} → https://github.com/${REPO_OWNER}/r-container/pkgs/container/r-container"
    else
        print_status "  - ${TARGET}:${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
    fi
    echo
    print_status "💡 To push both containers, run without -t flag: $0"
fi
