#!/bin/bash
# verify_cache_management.sh - Comprehensive cache management verification for Phase 5.1

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="cache_verification_${TIMESTAMP}"
REGISTRY="${REGISTRY:-ghcr.io/jbearak/base-container}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Create results directory
mkdir -p "$RESULTS_DIR"

# Usage function
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --registry <url>    Override default registry ($REGISTRY)"
    echo "  --verbose           Enable verbose output"
    echo "  --help             Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  REGISTRY           Registry URL for cache verification"
    echo "  VERBOSE            Enable verbose output (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Basic cache verification"
    echo "  $0 --verbose                          # Verbose cache verification"
    echo "  $0 --registry ghcr.io/user/repo      # Custom registry"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Test results tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_info "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    if [ "$result" -eq "$expected_result" ]; then
        log_success "✅ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "PASS: $test_name" >> "$RESULTS_DIR/test_results.txt"
    else
        log_error "❌ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $test_name" >> "$RESULTS_DIR/test_results.txt"
    fi
}

# Function to measure and log performance
measure_performance() {
    local operation="$1"
    local command="$2"
    
    log_info "Measuring performance: $operation"
    local start_time=$(date +%s)
    
    if eval "$command" >/dev/null 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "✅ $operation completed in ${duration}s"
        echo "$operation: ${duration}s" >> "$RESULTS_DIR/performance_metrics.txt"
        return 0
    else
        log_error "❌ $operation failed"
        echo "$operation: FAILED" >> "$RESULTS_DIR/performance_metrics.txt"
        return 1
    fi
}

# Main verification function
main() {
    log_info "Starting cache management verification - Phase 5.1"
    log_info "Results will be saved to: $RESULTS_DIR"
    log_info "Registry: $REGISTRY"
    
    echo "=== Cache Management Verification Report ===" > "$RESULTS_DIR/verification_report.txt"
    echo "Timestamp: $(date)" >> "$RESULTS_DIR/verification_report.txt"
    echo "Registry: $REGISTRY" >> "$RESULTS_DIR/verification_report.txt"
    echo "" >> "$RESULTS_DIR/verification_report.txt"
    
    # 1. Docker and BuildKit Verification
    log_info "=== 1. Docker and BuildKit Verification ==="
    
    run_test "Docker availability" "docker --version"
    run_test "BuildKit availability" "docker buildx version"
    run_test "BuildKit builder active" "docker buildx ls | grep -q 'default.*running'"
    
    # 2. Cache Mount Support Verification
    log_info "=== 2. Cache Mount Support Verification ==="
    
    run_test "Cache mount syntax support" "docker buildx build --help | grep -q 'mount=type=cache'"
    
    # Test cache mount functionality with a simple build
    cat > "$RESULTS_DIR/test_cache_mount.Dockerfile" << 'EOF'
FROM alpine:latest
RUN --mount=type=cache,target=/tmp/test-cache \
    echo "Testing cache mount" > /tmp/test-cache/test.txt && \
    ls -la /tmp/test-cache/
EOF
    
    run_test "Cache mount functionality" "docker buildx build -f '$RESULTS_DIR/test_cache_mount.Dockerfile' '$RESULTS_DIR'"
    
    # 3. pak Cache Verification
    log_info "=== 3. pak Cache Verification ==="
    
    # Check if pak-based container exists
    if docker image inspect base-container:pak >/dev/null 2>&1; then
        run_test "pak container availability" "docker image inspect base-container:pak"
        run_test "pak library availability" "docker run --rm base-container:pak R -e 'library(pak)'"
        run_test "pak cache directory exists" "docker run --rm base-container:pak test -d /root/.cache/R/pak"
        
        # Test pak cache functionality
        log_verbose "Testing pak cache functionality..."
        docker run --rm base-container:pak R -e 'pak::cache_summary()' > "$RESULTS_DIR/pak_cache_summary.txt" 2>&1
        if [ -s "$RESULTS_DIR/pak_cache_summary.txt" ]; then
            log_success "✅ pak cache summary generated"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "❌ pak cache summary failed"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
    else
        log_warning "pak-based container not found, skipping pak-specific tests"
    fi
    
    # 4. BuildKit Cache Persistence Verification
    log_info "=== 4. BuildKit Cache Persistence Verification ==="
    
    # Test cache persistence across builds
    if [ -f "Dockerfile.pak" ]; then
        log_info "Testing cache persistence with Dockerfile.pak"
        
        # First build (should populate cache)
        measure_performance "Cold build with cache population" \
            "docker buildx build --file Dockerfile.pak --target pak-full --tag test-cache-verification:cold ."
        
        # Second build (should use cache)
        measure_performance "Warm build with cache utilization" \
            "docker buildx build --file Dockerfile.pak --target pak-full --tag test-cache-verification:warm ."
        
        # Analyze cache effectiveness
        log_info "Analyzing cache effectiveness..."
        docker buildx build --progress=plain --file Dockerfile.pak --target pak-full . 2>&1 | \
            grep -E "(CACHED|cache)" > "$RESULTS_DIR/cache_analysis.txt" || true
        
        if [ -s "$RESULTS_DIR/cache_analysis.txt" ]; then
            cache_hits=$(grep -c "CACHED" "$RESULTS_DIR/cache_analysis.txt" || echo "0")
            log_success "✅ Cache analysis completed - $cache_hits cache hits detected"
            echo "Cache hits detected: $cache_hits" >> "$RESULTS_DIR/verification_report.txt"
        fi
    else
        log_warning "Dockerfile.pak not found, skipping build cache tests"
    fi
    
    # 5. Registry Cache Verification
    log_info "=== 5. Registry Cache Verification ==="
    
    # Test registry connectivity
    run_test "Registry connectivity" "docker pull alpine:latest"
    
    # Test registry cache access (if available)
    if docker buildx imagetools inspect "$REGISTRY/cache:pak-full" >/dev/null 2>&1; then
        log_success "✅ Registry cache available at $REGISTRY/cache:pak-full"
        run_test "Registry cache inspection" "docker buildx imagetools inspect '$REGISTRY/cache:pak-full'"
        echo "Registry cache: AVAILABLE" >> "$RESULTS_DIR/verification_report.txt"
    else
        log_warning "Registry cache not available at $REGISTRY/cache:pak-full"
        echo "Registry cache: NOT AVAILABLE" >> "$RESULTS_DIR/verification_report.txt"
    fi
    
    # 6. Cache Size and Efficiency Verification
    log_info "=== 6. Cache Size and Efficiency Verification ==="
    
    # Check Docker system cache usage
    docker system df > "$RESULTS_DIR/docker_system_df.txt"
    log_info "Docker system usage saved to docker_system_df.txt"
    
    # Check buildx cache usage
    if command -v docker buildx du >/dev/null 2>&1; then
        docker buildx du > "$RESULTS_DIR/buildx_cache_usage.txt" 2>/dev/null || true
        log_info "BuildKit cache usage saved to buildx_cache_usage.txt"
    fi
    
    # Extract cache size information
    cache_size=$(docker system df --format "{{.Type}}\t{{.Size}}" | grep "Build Cache" | awk '{print $2}' || echo "Unknown")
    log_info "Current build cache size: $cache_size"
    echo "Build cache size: $cache_size" >> "$RESULTS_DIR/verification_report.txt"
    
    # 7. Cache Pruning Verification
    log_info "=== 7. Cache Pruning Verification ==="
    
    # Test cache pruning functionality
    run_test "Cache pruning dry-run" "docker builder prune --dry-run"
    
    # Test cache helper script if available
    if [ -f "cache-helper.sh" ]; then
        run_test "Cache helper script availability" "test -x cache-helper.sh"
        run_test "Cache helper list command" "./cache-helper.sh list"
    else
        log_warning "cache-helper.sh not found"
    fi
    
    # 8. Performance Benchmarking
    log_info "=== 8. Performance Benchmarking ==="
    
    if [ -f "test_build_performance.sh" ]; then
        log_info "Running performance benchmark..."
        if timeout 1800 ./test_build_performance.sh --quick >/dev/null 2>&1; then
            log_success "✅ Performance benchmark completed"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_warning "⚠️ Performance benchmark timed out or failed"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
    else
        log_warning "test_build_performance.sh not found, skipping performance benchmark"
    fi
    
    # 9. Generate Final Report
    log_info "=== 9. Generating Final Report ==="
    
    {
        echo ""
        echo "=== Test Results Summary ==="
        echo "Total tests: $TESTS_TOTAL"
        echo "Passed: $TESTS_PASSED"
        echo "Failed: $TESTS_FAILED"
        echo "Success rate: $(echo "scale=2; $TESTS_PASSED / $TESTS_TOTAL * 100" | bc)%"
        echo ""
        echo "=== Cache Management Status ==="
        if [ "$TESTS_FAILED" -eq 0 ]; then
            echo "Status: ✅ ALL TESTS PASSED - Cache management fully verified"
        elif [ "$TESTS_FAILED" -lt 3 ]; then
            echo "Status: ⚠️ MINOR ISSUES - Cache management mostly functional"
        else
            echo "Status: ❌ MAJOR ISSUES - Cache management needs attention"
        fi
        echo ""
        echo "=== Recommendations ==="
        if [ "$TESTS_FAILED" -gt 0 ]; then
            echo "- Review failed tests in test_results.txt"
            echo "- Check troubleshooting guide for solutions"
            echo "- Consider running with --verbose for more details"
        else
            echo "- Cache management is fully functional"
            echo "- Consider implementing automated monitoring"
            echo "- Review performance metrics for optimization opportunities"
        fi
    } >> "$RESULTS_DIR/verification_report.txt"
    
    # Display final results
    echo ""
    log_info "=== Cache Management Verification Complete ==="
    log_info "Results saved to: $RESULTS_DIR/"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        log_success "🎉 All tests passed! Cache management is fully verified."
        echo "✅ Phase 5.1 Cache Management Verification: COMPLETE"
    elif [ "$TESTS_FAILED" -lt 3 ]; then
        log_warning "⚠️ Minor issues detected. Cache management is mostly functional."
        echo "⚠️ Phase 5.1 Cache Management Verification: PARTIAL"
    else
        log_error "❌ Major issues detected. Cache management needs attention."
        echo "❌ Phase 5.1 Cache Management Verification: FAILED"
        exit 1
    fi
    
    echo ""
    echo "Summary:"
    echo "- Total tests: $TESTS_TOTAL"
    echo "- Passed: $TESTS_PASSED"
    echo "- Failed: $TESTS_FAILED"
    echo "- Success rate: $(echo "scale=2; $TESTS_PASSED / $TESTS_TOTAL * 100" | bc)%"
    echo ""
    echo "For detailed results, see: $RESULTS_DIR/verification_report.txt"
    
    # Cleanup test images
    docker rmi test-cache-verification:cold test-cache-verification:warm >/dev/null 2>&1 || true
}

# Trap to cleanup on exit
cleanup() {
    log_info "Cleaning up temporary files..."
    docker rmi test-cache-verification:cold test-cache-verification:warm >/dev/null 2>&1 || true
}

trap cleanup EXIT

# Run main function
main "$@"