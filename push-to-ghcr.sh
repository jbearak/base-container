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
    -a, --all-platforms    Build and push multi-platform images (linux/amd64,linux/arm64)
    -h, --help             Show this help message

EXAMPLES:
    $0                                         # Push all targets (host platform only)
    $0 -a                                      # Build and push all targets (both platforms)
    $0 -t full-container                       # Push only full-container (host platform)
    $0 -a -t full-container                    # Build and push full-container (both platforms)
    $0 -t r-container -g v1.0.0              # Push only r-container:v1.0.0 (host platform)
    $0 -b                                     # Build and push all targets (host platform)
    $0 -a -b                                  # Build and push all targets (both platforms)

PREREQUISITES:
    1. Docker must be installed and running
    2. You must be logged in to GHCR: docker login ghcr.io
    3. You must have push permissions to the repository
    4. For multi-platform builds: docker buildx with multi-platform support

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

# Function to get host architecture for consistent naming
get_host_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unknown" ;;
    esac
}

# Function to get display tag for success messages
get_display_tag() {
    local target="$1"
    local tag="$2"
    
    if [[ "$target" == "r-container" ]]; then
        echo "r-${tag}"
    else
        echo "${tag}"
    fi
}

# Function to check if local image exists
check_local_image() {
    local target="$1"
    local tag="$2"
    local host_arch=$(get_host_arch)

    # Check for arch-specific naming pattern (e.g., "full-container-arm64")
    local arch_specific_name="${target}-${host_arch}"
    if docker image inspect "${arch_specific_name}" >/dev/null 2>&1; then
        return 0
    fi

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
    local host_arch=$(get_host_arch)
    
    local remote_image="${REGISTRY}/${REPOSITORY}:${tag}"
    
    # For r-container, use a different tag but same repository
    if [[ "$target" == "r-container" ]]; then
        remote_image="${REGISTRY}/${REPOSITORY}:r-${tag}"
    fi
    
    # Check if local image exists
    if ! check_local_image "$target" "$tag" && [[ "$force" != "true" ]]; then
        print_error "Local image not found. Use -b to build or -f to force."
        return 1
    fi
    
    # Use arch-specific naming
    local source_image="${target}-${host_arch}"
    
    if ! docker image inspect "${source_image}" >/dev/null 2>&1; then
        print_error "Expected image ${source_image} not found"
        print_error "Make sure to build with the current build scripts that create arch-specific names"
        return 1
    fi
    
    print_status "Tagging image: $source_image -> $remote_image"
    docker tag "$source_image" "$remote_image"
    
    print_status "Pushing image: $remote_image"
    docker push "$remote_image"
    
    print_success "Successfully pushed: $remote_image"
}

# Function to build and push multi-platform image
build_and_push_multiplatform() {
    local target="$1"
    local tag="$2"
    
    local remote_image="${REGISTRY}/${REPOSITORY}:${tag}"
    
    # For r-container, use a different tag but same repository
    if [[ "$target" == "r-container" ]]; then
        remote_image="${REGISTRY}/${REPOSITORY}:r-${tag}"
    fi
    
    print_status "Building and pushing multi-platform image for target: $target"
    print_status "Platforms: linux/amd64,linux/arm64"
    print_status "Destination: $remote_image"
    
    # Build and push multi-platform image directly to registry
    if docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --target "$target" \
        --build-arg DEBIAN_FRONTEND=noninteractive \
        --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
        --push \
        -t "$remote_image" \
        . ; then
        print_success "✅ Multi-platform image pushed successfully: $remote_image"
        return 0
    else
        print_error "❌ Failed to build and push multi-platform image: $remote_image"
        return 1
    fi
}

# Parse command line arguments
TARGET=""  # Empty means push all targets (consistent with build script)
TAG="$DEFAULT_TAG"
BUILD_FIRST=false
PUSH_ALL=true  # Default to pushing all targets
FORCE=false
ALL_PLATFORMS=false  # New option for multi-platform builds

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
        -a|--all-platforms)
            ALL_PLATFORMS=true
            print_status "Multi-platform mode enabled (linux/amd64,linux/arm64)"
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

# Multi-platform builds require buildx and don't use local images
if [[ "$ALL_PLATFORMS" == "true" ]]; then
    print_status "Multi-platform mode: Building and pushing directly to registry..."
    
    # Check if buildx is available
    if ! docker buildx version >/dev/null 2>&1; then
        print_error "docker buildx is required for multi-platform builds"
        exit 1
    fi
    
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Building and pushing all targets (multi-platform)..."
        failed_builds=0
        
        for target in "${VALID_TARGETS[@]}"; do
            echo
            print_status "Processing target: $target (multi-platform)"
            
            if ! build_and_push_multiplatform "$target" "$TAG"; then
                ((failed_builds++))
                print_error "Failed to build and push $target, continuing..."
            fi
        done
        
        if [ $failed_builds -eq 0 ]; then
            print_success "All multi-platform builds completed successfully!"
        else
            print_error "$failed_builds multi-platform build(s) failed"
            exit 1
        fi
    else
        print_status "Building and pushing single target: $TARGET (multi-platform)"
        
        if ! build_and_push_multiplatform "$TARGET" "$TAG"; then
            print_error "Failed to build and push $TARGET"
            exit 1
        fi
    fi
else
    # Default behavior: push existing local images (host platform)
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushing all targets (host platform)..."
        for target in "${VALID_TARGETS[@]}"; do
            echo
            print_status "Processing target: $target"
            
            if [[ "$BUILD_FIRST" == "true" ]]; then
                build_image "$target" "$target"
            fi
            
            push_image "$target" "$TAG" "$FORCE"
        done
    else
        print_status "Processing single target: $TARGET (host platform)"
        
        if [[ "$BUILD_FIRST" == "true" ]]; then
            build_image "$TARGET" "$TAG"
        fi
        
        push_image "$TARGET" "$TAG" "$FORCE"
    fi
fi

print_success "All operations completed successfully!"

# Success message
if [[ "$ALL_PLATFORMS" == "true" ]]; then
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushed both containers (multi-platform: linux/amd64,linux/arm64):"
        print_status "  - full-container:${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
        print_status "  - r-container:r-${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
    else
        print_status "Pushed single container (multi-platform: linux/amd64,linux/arm64):"
        local display_tag="${TAG}"
        [[ "$TARGET" == "r-container" ]] && display_tag="r-${TAG}"
        print_status "  - ${TARGET}:${display_tag} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
    fi
else
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushed both containers (host platform only):"
        print_status "  - full-container:${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
        print_status "  - r-container:r-${TAG} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
    else
        print_status "Pushed single container (host platform only):"
        local display_tag="${TAG}"
        [[ "$TARGET" == "r-container" ]] && display_tag="r-${TAG}"
        print_status "  - ${TARGET}:${display_tag} → https://github.com/${REPO_OWNER}/base-container/pkgs/container/base-container"
        echo
        print_status "💡 To push both containers, run without -t flag: $0"
        print_status "💡 To push multi-platform images, add -a flag: $0 -a"
    fi
fi
