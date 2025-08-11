#!/opt/homebrew/bin/bash
# test_build_performance.sh - Build Performance Testing
# Phase 4 implementation for pak migration (Issue #2)
#
# This script tests Docker build performance comparing pak-based vs traditional
# R package installation, measuring build times, cache effectiveness, and
# resource utilization.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/build_performance_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SESSION_DIR="${RESULTS_DIR}/${TIMESTAMP}"

# Configuration
ITERATIONS=${ITERATIONS:-3}
ENABLE_CACHE_TESTS=${ENABLE_CACHE_TESTS:-true}
ENABLE_MULTIARCH_TESTS=${ENABLE_MULTIARCH_TESTS:-false}
VERBOSE=${VERBOSE:-false}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$1" | tee -a "${SESSION_DIR}/build_performance.log"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    log "${RED}❌ $1${NC}"
}

log_header() {
    log ""
    log "${BLUE}$1${NC}"
    log "${BLUE}$(echo "$1" | sed 's/./=/g')${NC}"
}

# Initialize test environment
init_performance_testing() {
    # Create directories first before any logging
    mkdir -p "$SESSION_DIR"/{logs,metrics,reports}
    
    log_header "🚀 Build Performance Testing - Phase 4"
    log_info "Session: $TIMESTAMP"
    log_info "Results directory: $SESSION_DIR"
    
    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required but not installed"
        exit 1
    fi
    
    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker BuildKit is required but not available"
        exit 1
    fi
    
    log_success "Performance testing environment initialized"
}

# Measure build time and resource usage
measure_build() {
    local dockerfile="$1"
    local tag="$2"
    local description="$3"
    local cache_option="$4"
    
    log_info "Building: $description"
    log_info "Dockerfile: $dockerfile"
    log_info "Tag: $tag"
    log_info "Cache: $cache_option"
    
    local start_time=$(date +%s.%N)
    local build_log="${SESSION_DIR}/logs/build_${tag//[^a-zA-Z0-9]/_}.log"
    
    # Build with timing and resource monitoring
    local build_cmd="docker buildx build"
    if [[ -n "$cache_option" ]]; then
        build_cmd="$build_cmd $cache_option"
    fi
    build_cmd="$build_cmd -f $dockerfile -t $tag ."
    
    log_info "Running: $build_cmd"
    
    # Monitor system resources during build
    local monitor_pid=""
    if command -v top >/dev/null 2>&1; then
        {
            while true; do
                echo "$(date +%s.%N),$(top -l 1 -n 0 | grep "CPU usage" | head -1 || echo "CPU: N/A")"
                sleep 5
            done
        } > "${SESSION_DIR}/metrics/resources_${tag//[^a-zA-Z0-9]/_}.csv" &
        monitor_pid=$!
    fi
    
    # Execute build
    local build_success=false
    if eval "$build_cmd" > "$build_log" 2>&1; then
        build_success=true
    fi
    
    # Stop resource monitoring
    if [[ -n "$monitor_pid" ]]; then
        kill $monitor_pid 2>/dev/null || true
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ "$build_success" == "true" ]]; then
        log_success "Build completed in ${duration}s"
        
        # Get image size
        local image_size=$(docker images --format "table {{.Size}}" "$tag" | tail -n +2 | head -1)
        
        # Extract build metrics from log
        local cache_hits=$(grep -c "CACHED" "$build_log" 2>/dev/null || echo "0")
        local total_steps=$(grep -c "Step [0-9]" "$build_log" 2>/dev/null || echo "0")
        
        # Save metrics
        cat > "${SESSION_DIR}/metrics/build_${tag//[^a-zA-Z0-9]/_}.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "description": "$description",
    "dockerfile": "$dockerfile",
    "tag": "$tag",
    "cache_option": "$cache_option",
    "duration_seconds": $duration,
    "image_size": "$image_size",
    "cache_hits": $cache_hits,
    "total_steps": $total_steps,
    "cache_hit_rate": $(echo "scale=2; $cache_hits * 100 / $total_steps" | bc -l 2>/dev/null || echo "0"),
    "success": true
}
EOF
        
        return 0
    else
        log_error "Build failed after ${duration}s"
        
        # Save failure metrics
        cat > "${SESSION_DIR}/metrics/build_${tag//[^a-zA-Z0-9]/_}.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "description": "$description",
    "dockerfile": "$dockerfile", 
    "tag": "$tag",
    "cache_option": "$cache_option",
    "duration_seconds": $duration,
    "success": false,
    "error": "Build failed"
}
EOF
        
        return 1
    fi
}

# Test traditional build performance
test_traditional_build() {
    log_header "📊 Testing Traditional Build Performance"
    
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        log_error "Original Dockerfile not found"
        return 1
    fi
    
    local total_time=0
    local successful_builds=0
    
    for i in $(seq 1 $ITERATIONS); do
        log_info "Traditional build iteration $i/$ITERATIONS"
        
        # Clean build (no cache)
        if measure_build "$SCRIPT_DIR/Dockerfile" "base-container-traditional-$i" "Traditional build #$i" "--no-cache"; then
            successful_builds=$((successful_builds + 1))
            local duration=$(jq -r '.duration_seconds' "${SESSION_DIR}/metrics/build_base-container-traditional-$i.json")
            total_time=$(echo "$total_time + $duration" | bc -l)
        fi
        
        # Clean up image to ensure fair comparison
        docker rmi "base-container-traditional-$i" 2>/dev/null || true
    done
    
    if [[ $successful_builds -gt 0 ]]; then
        local avg_time=$(echo "scale=2; $total_time / $successful_builds" | bc -l)
        log_success "Traditional build average: ${avg_time}s ($successful_builds/$ITERATIONS successful)"
        
        echo "$avg_time" > "${SESSION_DIR}/metrics/traditional_avg_time.txt"
    else
        log_error "No successful traditional builds"
        return 1
    fi
}

# Test pak build performance
test_pak_build() {
    log_header "🚀 Testing Pak Build Performance"
    
    if [[ ! -f "$SCRIPT_DIR/Dockerfile.pak" ]]; then
        log_error "Pak Dockerfile not found"
        return 1
    fi
    
    local total_time=0
    local successful_builds=0
    
    for i in $(seq 1 $ITERATIONS); do
        log_info "Pak build iteration $i/$ITERATIONS"
        
        # Clean build (no cache)
        if measure_build "$SCRIPT_DIR/Dockerfile.pak" "base-container-pak-$i" "Pak build #$i" "--no-cache"; then
            successful_builds=$((successful_builds + 1))
            local duration=$(jq -r '.duration_seconds' "${SESSION_DIR}/metrics/build_base-container-pak-$i.json")
            total_time=$(echo "$total_time + $duration" | bc -l)
        fi
        
        # Clean up image to ensure fair comparison
        docker rmi "base-container-pak-$i" 2>/dev/null || true
    done
    
    if [[ $successful_builds -gt 0 ]]; then
        local avg_time=$(echo "scale=2; $total_time / $successful_builds" | bc -l)
        log_success "Pak build average: ${avg_time}s ($successful_builds/$ITERATIONS successful)"
        
        echo "$avg_time" > "${SESSION_DIR}/metrics/pak_avg_time.txt"
    else
        log_error "No successful pak builds"
        return 1
    fi
}

# Test cache effectiveness
test_cache_effectiveness() {
    if [[ "$ENABLE_CACHE_TESTS" != "true" ]]; then
        log_warning "Cache tests disabled"
        return 0
    fi
    
    log_header "💾 Testing Cache Effectiveness"
    
    # Test pak with cache
    log_info "Testing pak build with cache..."
    
    # First build to populate cache
    if measure_build "$SCRIPT_DIR/Dockerfile.pak" "base-container-pak-cache-1" "Pak build with cache (first)" ""; then
        log_success "First pak build completed (cache population)"
        
        # Second build to test cache effectiveness
        if measure_build "$SCRIPT_DIR/Dockerfile.pak" "base-container-pak-cache-2" "Pak build with cache (second)" ""; then
            log_success "Second pak build completed (cache utilization)"
            
            # Compare times
            local first_time=$(jq -r '.duration_seconds' "${SESSION_DIR}/metrics/build_base-container-pak-cache-1.json")
            local second_time=$(jq -r '.duration_seconds' "${SESSION_DIR}/metrics/build_base-container-pak-cache-2.json")
            local cache_improvement=$(echo "scale=1; ($first_time - $second_time) * 100 / $first_time" | bc -l)
            
            log_success "Cache improvement: ${cache_improvement}% (${first_time}s → ${second_time}s)"
            
            # Save cache effectiveness metrics
            cat > "${SESSION_DIR}/metrics/cache_effectiveness.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "first_build_time": $first_time,
    "second_build_time": $second_time,
    "cache_improvement_percent": $cache_improvement,
    "cache_effective": $(echo "$cache_improvement > 10" | bc -l)
}
EOF
        fi
    fi
    
    # Clean up cache test images
    docker rmi base-container-pak-cache-1 base-container-pak-cache-2 2>/dev/null || true
}

# Test multi-architecture builds
test_multiarch_builds() {
    if [[ "$ENABLE_MULTIARCH_TESTS" != "true" ]]; then
        log_warning "Multi-architecture tests disabled"
        return 0
    fi
    
    log_header "🏗️ Testing Multi-Architecture Builds"
    
    local platforms="linux/amd64,linux/arm64"
    
    log_info "Testing multi-arch pak build for platforms: $platforms"
    
    local start_time=$(date +%s.%N)
    local build_log="${SESSION_DIR}/logs/build_multiarch_pak.log"
    
    if docker buildx build \
        --platform "$platforms" \
        -f "$SCRIPT_DIR/Dockerfile.pak" \
        -t "base-container-pak-multiarch" \
        . > "$build_log" 2>&1; then
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        
        log_success "Multi-arch pak build completed in ${duration}s"
        
        # Save multi-arch metrics
        cat > "${SESSION_DIR}/metrics/multiarch_build.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "platforms": "$platforms",
    "duration_seconds": $duration,
    "success": true
}
EOF
    else
        log_error "Multi-arch pak build failed"
        return 1
    fi
}

# Generate performance report
generate_performance_report() {
    log_header "📊 Generating Performance Report"
    
    local report_file="${SESSION_DIR}/reports/performance_report.html"
    local summary_file="${SESSION_DIR}/reports/performance_summary.txt"
    
    # Calculate performance comparison
    local traditional_avg=""
    local pak_avg=""
    local improvement=""
    
    if [[ -f "${SESSION_DIR}/metrics/traditional_avg_time.txt" ]] && [[ -f "${SESSION_DIR}/metrics/pak_avg_time.txt" ]]; then
        traditional_avg=$(cat "${SESSION_DIR}/metrics/traditional_avg_time.txt")
        pak_avg=$(cat "${SESSION_DIR}/metrics/pak_avg_time.txt")
        improvement=$(echo "scale=1; ($traditional_avg - $pak_avg) * 100 / $traditional_avg" | bc -l)
    fi
    
    # Generate text summary
    {
        echo "=== Build Performance Testing Report ==="
        echo "Session: $TIMESTAMP"
        echo "Generated: $(date)"
        echo "Iterations: $ITERATIONS"
        echo ""
        echo "=== Performance Summary ==="
        if [[ -n "$traditional_avg" ]] && [[ -n "$pak_avg" ]]; then
            echo "Traditional average build time: ${traditional_avg}s"
            echo "Pak average build time: ${pak_avg}s"
            echo "Performance improvement: ${improvement}%"
            echo ""
            if (( $(echo "$improvement > 0" | bc -l) )); then
                echo "✅ Pak builds are faster than traditional builds"
            else
                echo "⚠️  Pak builds are slower than traditional builds"
            fi
        else
            echo "❌ Unable to calculate performance comparison"
        fi
        echo ""
        echo "=== Cache Effectiveness ==="
        if [[ -f "${SESSION_DIR}/metrics/cache_effectiveness.json" ]]; then
            local cache_improvement=$(jq -r '.cache_improvement_percent' "${SESSION_DIR}/metrics/cache_effectiveness.json")
            echo "Cache improvement: ${cache_improvement}%"
            if (( $(echo "$cache_improvement > 20" | bc -l) )); then
                echo "✅ Cache is highly effective"
            elif (( $(echo "$cache_improvement > 10" | bc -l) )); then
                echo "✅ Cache is moderately effective"
            else
                echo "⚠️  Cache effectiveness is low"
            fi
        else
            echo "❌ Cache effectiveness not measured"
        fi
        echo ""
        echo "=== Multi-Architecture Support ==="
        if [[ -f "${SESSION_DIR}/metrics/multiarch_build.json" ]]; then
            local multiarch_time=$(jq -r '.duration_seconds' "${SESSION_DIR}/metrics/multiarch_build.json")
            echo "Multi-arch build time: ${multiarch_time}s"
            echo "✅ Multi-architecture builds successful"
        else
            echo "⚠️  Multi-architecture builds not tested"
        fi
    } > "$summary_file"
    
    # Generate HTML report
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Build Performance Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .metrics { display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; min-width: 150px; }
        .metric h3 { margin: 0; color: #2c5aa0; }
        .metric .value { font-size: 24px; font-weight: bold; color: #1a365d; }
        .improvement { background: #d4edda; color: #155724; }
        .regression { background: #f8d7da; color: #721c24; }
        .chart { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        pre { background: #f1f1f1; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Build Performance Testing Report</h1>
        <p><strong>Session:</strong> $TIMESTAMP</p>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Iterations:</strong> $ITERATIONS</p>
    </div>
    
    <div class="metrics">
EOF
    
    if [[ -n "$traditional_avg" ]] && [[ -n "$pak_avg" ]]; then
        local improvement_class="improvement"
        if (( $(echo "$improvement < 0" | bc -l) )); then
            improvement_class="regression"
        fi
        
        cat >> "$report_file" << EOF
        <div class="metric">
            <h3>Traditional Build</h3>
            <div class="value">${traditional_avg}s</div>
        </div>
        <div class="metric">
            <h3>Pak Build</h3>
            <div class="value">${pak_avg}s</div>
        </div>
        <div class="metric $improvement_class">
            <h3>Improvement</h3>
            <div class="value">${improvement}%</div>
        </div>
EOF
    fi
    
    cat >> "$report_file" << EOF
    </div>
    
    <div class="chart">
        <h2>📊 Performance Analysis</h2>
        <pre>$(cat "$summary_file")</pre>
    </div>
    
    <div class="chart">
        <h2>📁 Test Artifacts</h2>
        <p>Detailed metrics and logs are available in: <code>$SESSION_DIR</code></p>
        <ul>
            <li><strong>Build Logs:</strong> Individual build logs in <code>logs/</code></li>
            <li><strong>Metrics:</strong> JSON metrics in <code>metrics/</code></li>
            <li><strong>Reports:</strong> Summary reports in <code>reports/</code></li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log_success "Performance report generated: $report_file"
    log_success "Performance summary generated: $summary_file"
    
    # Display summary
    echo ""
    cat "$summary_file"
}

# Main execution
main() {
    init_performance_testing
    
    # Run performance tests
    test_traditional_build
    test_pak_build
    test_cache_effectiveness
    test_multiarch_builds
    
    # Generate report
    generate_performance_report
    
    log_header "🎯 Build Performance Testing Complete"
    log_success "Results available in: $SESSION_DIR"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Build Performance Testing Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --iterations N          Number of build iterations (default: 3)"
        echo "  --no-cache              Disable cache effectiveness tests"
        echo "  --enable-multiarch      Enable multi-architecture tests"
        echo "  --verbose               Enable verbose output"
        echo ""
        echo "Environment Variables:"
        echo "  ITERATIONS=N"
        echo "  ENABLE_CACHE_TESTS=true|false"
        echo "  ENABLE_MULTIARCH_TESTS=true|false"
        echo "  VERBOSE=true|false"
        exit 0
        ;;
    --iterations)
        ITERATIONS="$2"
        shift 2
        ;;
    --no-cache)
        ENABLE_CACHE_TESTS=false
        ;;
    --enable-multiarch)
        ENABLE_MULTIARCH_TESTS=true
        ;;
    --verbose)
        VERBOSE=true
        ;;
esac

# Ensure required tools are available
for tool in bc jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "$tool is required but not installed"
        exit 1
    fi
done

# Run main function
main "$@"