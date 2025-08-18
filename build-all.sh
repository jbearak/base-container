#!/bin/bash
# Build all combinations: 2 architectures × 2 targets = 4 images
# Builds: full-container and r-container for both arm64 and amd64

# Exit immediately if any command fails (fail-fast behavior)
# This prevents the script from continuing with remaining builds if one fails unexpectedly
# Note: We handle expected build failures gracefully with explicit error checking
set -e

# Configuration
TARGETS=("full-container" "r-container")
PLATFORMS=("linux/arm64" "linux/amd64")
BUILD_ARGS="--build-arg DEBIAN_FRONTEND=noninteractive --build-arg DEBCONF_NONINTERACTIVE_SEEN=true"

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

# Function to get architecture suffix for image naming
get_arch_suffix() {
    local platform="$1"
    case "$platform" in
        "linux/arm64") echo "arm64" ;;
        "linux/amd64") echo "amd64" ;;
        *) echo "unknown" ;;
    esac
}

# Function to build a single target for a single platform
build_single() {
    local target="$1"
    local platform="$2"
    local arch_suffix=$(get_arch_suffix "$platform")
    local image_tag="${target}-${arch_suffix}"
    
    print_status "Building ${target} for ${platform}..."
    
    if docker buildx build \
        --platform "${platform}" \
        --target "${target}" \
        ${BUILD_ARGS} \
        --load \
        -t "${image_tag}" \
        . ; then
        print_success "✅ ${image_tag} built successfully"
        return 0
    else
        print_error "❌ Failed to build ${image_tag}"
        return 1
    fi
}

# Parse command line arguments
PARALLEL=false
TEST_IMAGES=false
PUSH_IMAGES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            PARALLEL=true
            print_warning "Parallel builds may consume significant system resources"
            shift
            ;;
        --test)
            TEST_IMAGES=true
            shift
            ;;
        --push)
            PUSH_IMAGES=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build all combinations of targets and architectures:"
            echo "  - full-container (arm64, amd64)"
            echo "  - r-container (arm64, amd64)"
            echo ""
            echo "OPTIONS:"
            echo "  --parallel    Build all images in parallel (resource intensive)"
            echo "  --test        Test each image after building"
            echo "  --push        Push images to registry after building"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build all 4 images sequentially"
            echo "  $0 --parallel         # Build all 4 images in parallel"
            echo "  $0 --test             # Build and test all images"
            echo "  $0 --parallel --test  # Build in parallel and test"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main build logic
print_status "Starting build of all combinations..."
print_status "Targets: ${TARGETS[*]}"
print_status "Platforms: ${PLATFORMS[*]}"
print_status "Total images to build: $((${#TARGETS[@]} * ${#PLATFORMS[@]}))"

if [ "$PARALLEL" = true ]; then
    print_status "Building in parallel mode..."
    
    # Build all combinations in parallel
    pids=()
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            build_single "$target" "$platform" &
            pids+=($!)
        done
    done
    
    # Wait for all builds to complete
    failed_builds=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed_builds++))
        fi
    done
    
    if [ $failed_builds -eq 0 ]; then
        print_success "🎉 All parallel builds completed successfully!"
    else
        print_error "❌ $failed_builds build(s) failed"
        exit 1
    fi
else
    print_status "Building sequentially..."
    
    # Build all combinations sequentially
    failed_builds=0
    total_builds=0
    
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            ((total_builds++))
            arch_suffix=$(get_arch_suffix "$platform")
            
            echo ""
            print_status "Building $total_builds of $((${#TARGETS[@]} * ${#PLATFORMS[@]})): ${target}-${arch_suffix}"
            
            if ! build_single "$target" "$platform"; then
                ((failed_builds++))
                print_error "Build failed, continuing with remaining builds..."
            fi
        done
    done
    
    echo ""
    if [ $failed_builds -eq 0 ]; then
        print_success "🎉 All $total_builds builds completed successfully!"
    else
        print_error "❌ $failed_builds out of $total_builds build(s) failed"
        exit 1
    fi
fi

# Test images if requested
if [ "$TEST_IMAGES" = true ]; then
    echo ""
    print_status "Testing built images..."
    
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            arch_suffix=$(get_arch_suffix "$platform")
            image_tag="${target}-${arch_suffix}"
            
            print_status "Testing ${image_tag}..."
            
            # Test basic functionality
            if docker run --rm "$image_tag" uname -m >/dev/null 2>&1; then
                print_success "✅ ${image_tag} test passed"
            else
                print_error "❌ ${image_tag} test failed"
            fi
        done
    done
fi

# Push images if requested
if [ "$PUSH_IMAGES" = true ]; then
    echo ""
    print_status "Pushing images to registry..."
    print_warning "Push functionality requires registry configuration"
    print_warning "This is a placeholder - implement push logic as needed"
fi

# Summary
echo ""
print_success "🏁 Build summary:"
for target in "${TARGETS[@]}"; do
    for platform in "${PLATFORMS[@]}"; do
        arch_suffix=$(get_arch_suffix "$platform")
        image_tag="${target}-${arch_suffix}"
        echo "  📦 ${image_tag}"
    done
done

echo ""
print_status "💡 Usage examples:"
echo "  docker run -it --rm full-container-arm64"
echo "  docker run -it --rm full-container-amd64"
echo "  docker run -it --rm r-container-arm64"
echo "  docker run -it --rm r-container-amd64"

echo ""
print_status "📤 To push these multi-platform images to registry:"
print_warning "The built images are platform-specific (e.g., full-container-amd64)"
print_warning "To push as multi-platform manifests, use:"
echo "  ./push-to-ghcr.sh -a                    # Push both targets, both platforms"
echo "  ./push-to-ghcr.sh -a -t full-container  # Push specific target, both platforms"
echo ""
print_status "Note: The -a flag builds and pushes fresh multi-platform images"
print_status "      It does not use the locally built platform-specific images"
