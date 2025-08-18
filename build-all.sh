#!/bin/bash
# Build all combinations: 2 architectures × 2 targets = 4 images
# Builds: full-container and r-container for both arm64 and amd64
#
# WHY THIS SCRIPT EXISTS:
# Docker containers are platform-specific (arm64 vs amd64). When you build a container
# on an Apple Silicon Mac, it creates an arm64 image. When you build on an Intel Mac
# or most cloud servers, it creates an amd64 image. This script builds both versions
# of both container types, so you have local images for testing regardless of your platform.
#
# WHY WE BUILD LOCALLY INSTEAD OF USING MULTI-PLATFORM:
# Multi-platform builds (docker buildx --platform linux/amd64,linux/arm64) can only
# push directly to a registry - they can't create local images you can test with
# "docker run". This script creates local images with clear names like:
# - full-container-arm64 (for Apple Silicon)
# - full-container-amd64 (for Intel/cloud)
# - r-container-arm64
# - r-container-amd64

# Exit immediately if any command fails (fail-fast behavior)
# NOTE: In parallel mode, background processes (&) are not affected by set -e
# We handle their failures explicitly with wait and exit code checking
set -e

# Configuration
# These arrays define what we're building - 2 targets × 2 platforms = 4 total images
TARGETS=("full-container" "r-container")  # Two different container variants
PLATFORMS=("linux/arm64" "linux/amd64")  # Two CPU architectures
# Build arguments that make Docker installs non-interactive (no prompts during build)
BUILD_ARGS="--build-arg DEBIAN_FRONTEND=noninteractive --build-arg DEBCONF_NONINTERACTIVE_SEEN=true"

# Color codes for pretty terminal output
# These make success messages green, errors red, etc.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
# These functions make terminal output easier to read by adding colors and consistent formatting
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
# WHY WE NEED THIS: Docker images need unique names. Since we're building for multiple
# architectures, we add the architecture to the image name (e.g., "full-container-arm64")
# so you can tell them apart and run the right one for your system.
get_arch_suffix() {
    local platform="$1"
    case "$platform" in
        "linux/arm64") echo "arm64" ;;  # Apple Silicon Macs, newer ARM servers
        "linux/amd64") echo "amd64" ;;  # Intel Macs, most cloud servers, Windows
        *) 
            # If someone tries to build for an unsupported platform, fail immediately
            # with a clear error message rather than creating confusing image names
            print_error "Unsupported platform: $platform"
            print_error "Supported platforms: linux/arm64, linux/amd64"
            exit 1
            ;;
    esac
}

# Function to build a single target for a single platform
# WHY THIS IS A FUNCTION: We need to build 4 different combinations (2 targets × 2 platforms).
# Rather than copy-paste the docker build command 4 times, we put it in a function.
# This makes the code easier to maintain and ensures all builds use the same settings.
build_single() {
    local target="$1"      # e.g., "full-container" or "r-container"
    local platform="$2"    # e.g., "linux/arm64" or "linux/amd64"
    
    # Convert platform to a short suffix for the image name
    local arch_suffix=$(get_arch_suffix "$platform")
    local image_tag="${target}-${arch_suffix}"  # e.g., "full-container-arm64"
    
    print_status "Building ${target} for ${platform}..."
    
    # The actual Docker build command
    # --platform: tells Docker which CPU architecture to build for
    # --target: which stage of our multi-stage Dockerfile to build
    # --build-arg: passes variables into the Dockerfile (makes installs non-interactive)
    # -t: tags the image with a name so we can reference it later
    # --load: saves the image locally (vs pushing to registry)
    # . : build context (current directory contains the Dockerfile)
    if docker buildx build \
        --platform "${platform}" \
        --target "${target}" \
        ${BUILD_ARGS} \
        --load \
        -t "${image_tag}" \
        . ; then
        print_success "✅ ${image_tag} built successfully"
        return 0  # Success exit code
    else
        print_error "❌ Failed to build ${image_tag}"
        return 1  # Failure exit code
    fi
}

# Parse command line arguments
# WHY WE PARSE ARGUMENTS: This lets users customize how the script runs.
# For example: ./build-all.sh --parallel --test
PARALLEL=false    # Default: build images one at a time (safer, uses less resources)
TEST_IMAGES=false # Default: don't test images after building (faster)

# Loop through all command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            # Build all 4 images at the same time instead of one-by-one
            # PRO: Much faster if you have a powerful machine
            # CON: Uses lots of CPU, memory, and disk I/O simultaneously
            PARALLEL=true
            print_warning "Parallel builds may consume significant system resources"
            shift  # Move to next argument
            ;;
        --test)
            # After building each image, test it by running "uname -m" inside it
            # This verifies the image works and shows which architecture it's running
            TEST_IMAGES=true
            shift
            ;;
        -h|--help)
            # Show usage information and exit
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build all combinations of targets and architectures:"
            echo "  - full-container (arm64, amd64)"
            echo "  - r-container (arm64, amd64)"
            echo ""
            echo "OPTIONS:"
            echo "  --parallel    Build all images in parallel (resource intensive)"
            echo "  --test        Test each image after building"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build all 4 images sequentially"
            echo "  $0 --parallel         # Build all 4 images in parallel"
            echo "  $0 --test             # Build and test all images"
            echo "  $0 --parallel --test  # Build in parallel and test"
            echo ""
            echo "To push images after building, use:"
            echo "  ./push-to-ghcr.sh -a  # Push multi-platform manifests"
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
# WHY WE SHOW THIS SUMMARY: Building 4 images takes time. This summary helps users
# understand what's about to happen and how long it might take.
print_status "Starting build of all combinations..."
print_status "Targets: ${TARGETS[*]}"        # Shows: full-container r-container
print_status "Platforms: ${PLATFORMS[*]}"    # Shows: linux/arm64 linux/amd64
print_status "Total images to build: $((${#TARGETS[@]} * ${#PLATFORMS[@]}))"  # Shows: 4

# Choose build strategy based on user preference
if [ "$PARALLEL" = true ]; then
    # PARALLEL BUILD STRATEGY:
    # Start all 4 builds at the same time using background processes (&)
    # This is much faster but uses lots of system resources
    print_status "Building in parallel mode..."
    
    # Build all combinations in parallel
    # Array to store background process IDs so we can wait for them
    pids=()
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            # The & at the end runs this in the background
            build_single "$target" "$platform" &
            pids+=($!)  # Store the process ID
        done
    done
    
    # Wait for all builds to complete
    # WHY WE WAIT: We need to know if any builds failed before continuing
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
    # SEQUENTIAL BUILD STRATEGY:
    # Build images one at a time. This is slower but safer and uses fewer resources.
    # Good for older machines or when you want to see each build's output clearly.
    print_status "Building sequentially..."
    
    # Build all combinations sequentially
    failed_builds=0
    total_builds=0
    
    # Nested loops: for each target, build it for each platform
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            ((total_builds++))  # Count how many we've attempted
            arch_suffix=$(get_arch_suffix "$platform")
            
            echo ""  # Blank line for readability
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
# WHY WE TEST: Building an image doesn't guarantee it works. Testing runs a simple
# command inside each container to verify it starts correctly and shows which
# architecture it's actually running (arm64 vs amd64).
if [ "$TEST_IMAGES" = true ]; then
    echo ""
    print_status "Testing built images..."
    
    # Test each image we just built
    for target in "${TARGETS[@]}"; do
        for platform in "${PLATFORMS[@]}"; do
            arch_suffix=$(get_arch_suffix "$platform")
            image_tag="${target}-${arch_suffix}"
            
            print_status "Testing ${image_tag}..."
            
            # Test basic functionality
            # Run "uname -m" inside the container to show its architecture
            # This verifies the container starts and shows if it's arm64 or x86_64
            if docker run --rm "$image_tag" uname -m >/dev/null 2>&1; then
                print_success "✅ ${image_tag} test passed"
            else
                print_error "❌ ${image_tag} test failed"
            fi
        done
    done
fi

# Summary
# WHY WE SHOW A SUMMARY: After building 4 images, it's helpful to see what was created
# and get examples of how to use them.
echo ""
print_success "🏁 Build summary:"
# List all the images we built with their exact names
for target in "${TARGETS[@]}"; do
    for platform in "${PLATFORMS[@]}"; do
        arch_suffix=$(get_arch_suffix "$platform")
        image_tag="${target}-${arch_suffix}"
        echo "  📦 ${image_tag}"  # e.g., "📦 full-container-arm64"
    done
done

echo ""
print_status "💡 Usage examples:"
# Show users how to run the containers they just built
# -it: interactive terminal (so you can type commands)
# --rm: automatically delete the container when you exit
echo "  docker run -it --rm full-container-arm64"
echo "  docker run -it --rm full-container-amd64"
echo "  docker run -it --rm r-container-arm64"
echo "  docker run -it --rm r-container-amd64"

echo ""
# Explain the relationship between local images and registry images
# WHY THIS IS IMPORTANT: Users often get confused about the difference between
# local platform-specific images and multi-platform registry images.
print_status "These local images are platform-specific, but you can create multi-platform registry images:"
echo "  ./push-to-ghcr.sh -a                    # Push both targets, both platforms"
echo "  ./push-to-ghcr.sh -a -t full-container  # Push specific target, both platforms"
echo ""
print_status "💡 The -a flag builds fresh multi-platform images and pushes them to the registry"
print_status "   (It doesn't use these local platform-specific images)"
# WHY THE -a FLAG WORKS DIFFERENTLY:
# Local builds create images you can test with "docker run"
# Registry builds create multi-platform manifests that work on any architecture
# but can't be stored locally - they must be pushed to a registry immediately
