#!/opt/homebrew/bin/bash
# test_suite_phase4.sh - Comprehensive Testing and Validation Framework
# Phase 4 implementation for pak migration (Issue #2)
#
# This script orchestrates comprehensive testing of the pak-based R package
# installation system, including performance benchmarking, compatibility
# validation, and regression testing.

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="${SCRIPT_DIR}/test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_SESSION_DIR="${TEST_RESULTS_DIR}/${TIMESTAMP}"
LOG_FILE="${TEST_SESSION_DIR}/test_suite.log"

# Test configuration
ENABLE_PERFORMANCE_TESTS=${ENABLE_PERFORMANCE_TESTS:-true}
ENABLE_REGRESSION_TESTS=${ENABLE_REGRESSION_TESTS:-true}
ENABLE_MULTIARCH_TESTS=${ENABLE_MULTIARCH_TESTS:-false}
ENABLE_STRESS_TESTS=${ENABLE_STRESS_TESTS:-false}
VERBOSE=${VERBOSE:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
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
    log "${PURPLE}$1${NC}"
    log "${PURPLE}$(echo "$1" | sed 's/./=/g')${NC}"
}

# Test result tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

declare -A TEST_RESULTS
declare -A TEST_TIMES
declare -A TEST_DETAILS

# Initialize test environment
init_test_environment() {
    # Create test directories first before any logging
    mkdir -p "$TEST_SESSION_DIR"/{logs,reports,artifacts,benchmarks}
    
    log_header "🧪 Phase 4: Comprehensive Testing and Validation Framework"
    log_info "Test session: $TIMESTAMP"
    log_info "Results directory: $TEST_SESSION_DIR"
    
    # System information
    log_info "Collecting system information..."
    {
        echo "=== System Information ==="
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "OS: $(uname -a)"
        echo "Architecture: $(uname -m)"
        echo "CPU Info: $(nproc) cores"
        echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
        echo "Docker Version: $(docker --version 2>/dev/null || echo 'Not available')"
        echo "R Version: $(R --version | head -n1 2>/dev/null || echo 'Not available')"
        echo ""
        echo "=== Environment Variables ==="
        env | grep -E '^(ENABLE_|VERBOSE|R_|PAK_)' | sort
        echo ""
    } > "$TEST_SESSION_DIR/system_info.txt"
    
    log_success "Test environment initialized"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    local test_description="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    log_info "Running test: $test_name"
    if [[ -n "$test_description" ]]; then
        log "   Description: $test_description"
    fi
    
    local start_time=$(date +%s.%N)
    local test_log="${TEST_SESSION_DIR}/logs/${test_name}.log"
    
    if $test_function > "$test_log" 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_RESULTS["$test_name"]="PASSED"
        TEST_TIMES["$test_name"]="$duration"
        TEST_DETAILS["$test_name"]="$test_description"
        
        log_success "Test passed: $test_name (${duration}s)"
    else
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS["$test_name"]="FAILED"
        TEST_TIMES["$test_name"]="$duration"
        TEST_DETAILS["$test_name"]="$test_description"
        
        log_error "Test failed: $test_name (${duration}s)"
        if [[ "$VERBOSE" == "true" ]]; then
            log "   Error details:"
            tail -n 10 "$test_log" | sed 's/^/   /'
        fi
    fi
}

# Skip test wrapper
skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    TEST_RESULTS["$test_name"]="SKIPPED"
    TEST_TIMES["$test_name"]="0"
    TEST_DETAILS["$test_name"]="$reason"
    
    log_warning "Test skipped: $test_name - $reason"
}

# Test functions
test_pak_installation() {
    log "Testing pak installation and basic functionality..."
    
    # Test pak installation
    R --slave --no-restore -e "
    if (!require('pak', quietly = TRUE)) {
        install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')
    }
    library(pak)
    cat('pak version:', as.character(packageVersion('pak')), '\n')
    "
    
    # Test basic pak functionality
    R --slave --no-restore -e "
    library(pak)
    # Test package info retrieval
    info <- pak::pkg_deps('praise')
    cat('Package info retrieval: OK\n')
    
    # Test repository access
    repos <- pak::repo_get()
    cat('Repository access: OK\n')
    
    cat('pak installation test: PASSED\n')
    "
}

test_package_installation_basic() {
    log "Testing basic package installation with pak..."
    
    # Create test package list
    local test_packages_file="/tmp/test_basic_packages.txt"
    cat > "$test_packages_file" << 'EOF'
praise
cli
glue
rlang
EOF
    
    # Test installation
    R --slave --no-restore -e "
    library(pak)
    packages <- readLines('$test_packages_file')
    cat('Installing packages:', paste(packages, collapse = ', '), '\n')
    
    pak::pkg_install(packages)
    
    # Verify installation
    installed <- rownames(installed.packages())
    missing <- setdiff(packages, installed)
    
    if (length(missing) > 0) {
        cat('Missing packages:', paste(missing, collapse = ', '), '\n')
        quit(status = 1)
    }
    
    cat('Basic package installation test: PASSED\n')
    "
    
    rm -f "$test_packages_file"
}

test_special_packages() {
    log "Testing special package installation (GitHub, archive)..."
    
    R --slave --no-restore -e "
    library(pak)
    
    # Test GitHub package
    cat('Installing GitHub package: nx10/httpgd\n')
    pak::pkg_install('nx10/httpgd')
    
    # Test archive package (simulate with a CRAN package)
    cat('Installing archive-style package\n')
    pak::pkg_install('jalvesaq/colorout', ask = FALSE)
    
    # Verify installations
    installed <- rownames(installed.packages())
    required <- c('httpgd', 'colorout')
    missing <- setdiff(required, installed)
    
    if (length(missing) > 0) {
        cat('Missing special packages:', paste(missing, collapse = ', '), '\n')
        quit(status = 1)
    }
    
    cat('Special package installation test: PASSED\n')
    "
}

test_package_loading() {
    log "Testing package loading and functionality..."
    
    R --slave --no-restore -e "
    # Test loading core packages
    test_packages <- c('dplyr', 'ggplot2', 'readr', 'tibble', 'stringr')
    
    for (pkg in test_packages) {
        if (pkg %in% rownames(installed.packages())) {
            tryCatch({
                library(pkg, character.only = TRUE, quietly = TRUE)
                cat('✓ Package', pkg, 'loaded successfully\n')
            }, error = function(e) {
                cat('✗ Package', pkg, 'failed to load:', conditionMessage(e), '\n')
                quit(status = 1)
            })
        } else {
            cat('! Package', pkg, 'not installed, skipping load test\n')
        }
    }
    
    cat('Package loading test: PASSED\n')
    "
}

test_dependency_resolution() {
    log "Testing dependency resolution..."
    
    R --slave --no-restore -e "
    library(pak)
    
    # Test dependency resolution for a package with many dependencies
    cat('Testing dependency resolution for tidyverse...\n')
    deps <- pak::pkg_deps('tidyverse')
    
    cat('Dependencies found:', nrow(deps), '\n')
    
    if (nrow(deps) < 10) {
        cat('ERROR: Expected more dependencies for tidyverse\n')
        quit(status = 1)
    }
    
    # Check for circular dependencies
    if (any(duplicated(deps\$package))) {
        cat('WARNING: Potential circular dependencies detected\n')
    }
    
    cat('Dependency resolution test: PASSED\n')
    "
}

test_cache_functionality() {
    log "Testing pak cache functionality..."
    
    R --slave --no-restore -e "
    library(pak)
    
    # Check cache directory
    cache_dir <- pak::cache_summary()
    cat('Cache directory info:\n')
    print(cache_dir)
    
    # Test cache cleaning
    pak::cache_clean()
    cat('Cache cleaned successfully\n')
    
    # Install a package to populate cache
    pak::pkg_install('jsonlite')
    
    # Check cache again
    cache_after <- pak::cache_summary()
    cat('Cache after installation:\n')
    print(cache_after)
    
    cat('Cache functionality test: PASSED\n')
    "
}

test_error_handling() {
    log "Testing error handling and recovery..."
    
    R --slave --no-restore -e "
    library(pak)
    
    # Test installation of non-existent package
    cat('Testing error handling with non-existent package...\n')
    tryCatch({
        pak::pkg_install('this_package_does_not_exist_12345')
        cat('ERROR: Should have failed for non-existent package\n')
        quit(status = 1)
    }, error = function(e) {
        cat('✓ Correctly handled non-existent package error\n')
    })
    
    # Test recovery from partial failure
    cat('Testing recovery from partial installation failure...\n')
    tryCatch({
        # Mix of valid and invalid packages
        pak::pkg_install(c('praise', 'this_does_not_exist_12345'), ask = FALSE)
    }, error = function(e) {
        cat('✓ Correctly handled partial failure\n')
    })
    
    # Verify that valid package was still installed
    if (!'praise' %in% rownames(installed.packages())) {
        cat('ERROR: Valid package should have been installed despite partial failure\n')
        quit(status = 1)
    }
    
    cat('Error handling test: PASSED\n')
    "
}

test_performance_benchmark() {
    if [[ "$ENABLE_PERFORMANCE_TESTS" != "true" ]]; then
        return 0
    fi
    
    log "Running performance benchmarks..."
    
    local benchmark_file="${TEST_SESSION_DIR}/benchmarks/performance_comparison.json"
    
    R --slave --no-restore -e "
    library(pak)
    library(jsonlite)
    
    # Benchmark package for testing
    test_pkg <- 'praise'
    
    # Remove package if installed
    if (test_pkg %in% rownames(installed.packages())) {
        remove.packages(test_pkg)
    }
    
    # Benchmark pak installation
    cat('Benchmarking pak installation...\n')
    start_time <- Sys.time()
    pak::pkg_install(test_pkg)
    pak_time <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
    
    # Remove for traditional test
    remove.packages(test_pkg)
    
    # Benchmark traditional installation
    cat('Benchmarking traditional installation...\n')
    start_time <- Sys.time()
    install.packages(test_pkg, repos = 'https://cloud.r-project.org/', quiet = TRUE)
    traditional_time <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
    
    # Calculate improvement
    improvement <- ((traditional_time - pak_time) / traditional_time) * 100
    
    # Create benchmark results
    results <- list(
        timestamp = format(Sys.time(), '%Y-%m-%d %H:%M:%S'),
        test_package = test_pkg,
        pak_time_seconds = pak_time,
        traditional_time_seconds = traditional_time,
        improvement_percent = improvement,
        pak_faster = pak_time < traditional_time
    )
    
    # Save results
    write_json(results, '$benchmark_file', pretty = TRUE)
    
    cat('Performance benchmark results:\n')
    cat('  pak time:', sprintf('%.2f', pak_time), 'seconds\n')
    cat('  traditional time:', sprintf('%.2f', traditional_time), 'seconds\n')
    cat('  improvement:', sprintf('%.1f%%', improvement), '\n')
    
    cat('Performance benchmark test: PASSED\n')
    "
}

test_regression_compatibility() {
    if [[ "$ENABLE_REGRESSION_TESTS" != "true" ]]; then
        return 0
    fi
    
    log "Running regression and compatibility tests..."
    
    # Test that all packages from R_packages.txt can be resolved
    if [[ -f "$SCRIPT_DIR/R_packages.txt" ]]; then
        R --slave --no-restore -e "
        library(pak)
        
        # Read package list
        packages <- readLines('$SCRIPT_DIR/R_packages.txt')
        packages <- packages[packages != '' & !grepl('^#', packages)]
        
        cat('Testing dependency resolution for', length(packages), 'packages...\n')
        
        # Test dependency resolution (don't install, just resolve)
        tryCatch({
            deps <- pak::pkg_deps(packages)
            cat('✓ All packages can be resolved\n')
            cat('  Total dependencies:', nrow(deps), '\n')
        }, error = function(e) {
            cat('✗ Dependency resolution failed:', conditionMessage(e), '\n')
            quit(status = 1)
        })
        
        cat('Regression compatibility test: PASSED\n')
        "
    else
        log_warning "R_packages.txt not found, skipping regression test"
        return 1
    fi
}

test_multiarch_support() {
    if [[ "$ENABLE_MULTIARCH_TESTS" != "true" ]]; then
        return 0
    fi
    
    log "Testing multi-architecture support..."
    
    R --slave --no-restore -e "
    # Test architecture detection
    arch <- Sys.info()[['machine']]
    r_version <- paste(R.version\$major, R.version\$minor, sep = '.')
    
    cat('Current architecture:', arch, '\n')
    cat('R version:', r_version, '\n')
    
    # Test site library path construction
    site_lib_path <- file.path('/opt/R/site-library', paste0(r_version, '-', arch))
    cat('Expected site library path:', site_lib_path, '\n')
    
    # Test that packages can be installed to architecture-specific location
    if (dir.exists(dirname(site_lib_path))) {
        cat('✓ Architecture-specific library path structure exists\n')
    } else {
        cat('! Architecture-specific library path not found (may be expected in test environment)\n')
    }
    
    cat('Multi-architecture support test: PASSED\n')
    "
}

test_stress_installation() {
    if [[ "$ENABLE_STRESS_TESTS" != "true" ]]; then
        return 0
    fi
    
    log "Running stress tests..."
    
    # Test installing many packages simultaneously
    R --slave --no-restore -e "
    library(pak)
    
    # Create a list of lightweight packages for stress testing
    stress_packages <- c(
        'praise', 'cli', 'glue', 'rlang', 'lifecycle',
        'vctrs', 'pillar', 'fansi', 'utf8', 'crayon'
    )
    
    cat('Stress testing with', length(stress_packages), 'packages...\n')
    
    # Remove packages first
    installed <- rownames(installed.packages())
    to_remove <- intersect(stress_packages, installed)
    if (length(to_remove) > 0) {
        remove.packages(to_remove)
    }
    
    # Install all at once
    start_time <- Sys.time()
    pak::pkg_install(stress_packages)
    install_time <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
    
    # Verify all installed
    installed_after <- rownames(installed.packages())
    missing <- setdiff(stress_packages, installed_after)
    
    if (length(missing) > 0) {
        cat('✗ Missing packages after stress test:', paste(missing, collapse = ', '), '\n')
        quit(status = 1)
    }
    
    cat('✓ Stress test completed in', sprintf('%.2f', install_time), 'seconds\n')
    cat('Stress installation test: PASSED\n')
    "
}

# Generate comprehensive test report
generate_test_report() {
    log_header "📊 Generating Test Report"
    
    local report_file="${TEST_SESSION_DIR}/reports/test_report.html"
    local summary_file="${TEST_SESSION_DIR}/reports/test_summary.txt"
    
    # Generate text summary
    {
        echo "=== Phase 4 Testing and Validation Report ==="
        echo "Test Session: $TIMESTAMP"
        echo "Generated: $(date)"
        echo ""
        echo "=== Test Summary ==="
        echo "Total Tests: $TESTS_TOTAL"
        echo "Passed: $TESTS_PASSED"
        echo "Failed: $TESTS_FAILED"
        echo "Skipped: $TESTS_SKIPPED"
        echo "Success Rate: $(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc -l)%"
        echo ""
        echo "=== Test Results ==="
        for test_name in "${!TEST_RESULTS[@]}"; do
            printf "%-30s %-8s %8.2fs  %s\n" \
                "$test_name" \
                "${TEST_RESULTS[$test_name]}" \
                "${TEST_TIMES[$test_name]}" \
                "${TEST_DETAILS[$test_name]}"
        done
        echo ""
        echo "=== System Information ==="
        cat "$TEST_SESSION_DIR/system_info.txt"
    } > "$summary_file"
    
    # Generate HTML report
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Phase 4 Testing Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; }
        .metric h3 { margin: 0; color: #2c5aa0; }
        .metric .value { font-size: 24px; font-weight: bold; color: #1a365d; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .passed { color: #28a745; font-weight: bold; }
        .failed { color: #dc3545; font-weight: bold; }
        .skipped { color: #ffc107; font-weight: bold; }
        .details { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
        pre { background: #f1f1f1; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 Phase 4 Testing and Validation Report</h1>
        <p><strong>Test Session:</strong> $TIMESTAMP</p>
        <p><strong>Generated:</strong> $(date)</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Tests</h3>
            <div class="value">$TESTS_TOTAL</div>
        </div>
        <div class="metric">
            <h3>Passed</h3>
            <div class="value" style="color: #28a745;">$TESTS_PASSED</div>
        </div>
        <div class="metric">
            <h3>Failed</h3>
            <div class="value" style="color: #dc3545;">$TESTS_FAILED</div>
        </div>
        <div class="metric">
            <h3>Skipped</h3>
            <div class="value" style="color: #ffc107;">$TESTS_SKIPPED</div>
        </div>
        <div class="metric">
            <h3>Success Rate</h3>
            <div class="value">$(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc -l)%</div>
        </div>
    </div>
    
    <h2>📋 Test Results</h2>
    <table>
        <thead>
            <tr>
                <th>Test Name</th>
                <th>Status</th>
                <th>Duration (s)</th>
                <th>Description</th>
            </tr>
        </thead>
        <tbody>
EOF
    
    # Add test results to HTML
    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local css_class=""
        case "$status" in
            "PASSED") css_class="passed" ;;
            "FAILED") css_class="failed" ;;
            "SKIPPED") css_class="skipped" ;;
        esac
        
        cat >> "$report_file" << EOF
            <tr>
                <td>$test_name</td>
                <td class="$css_class">$status</td>
                <td>${TEST_TIMES[$test_name]}</td>
                <td>${TEST_DETAILS[$test_name]}</td>
            </tr>
EOF
    done
    
    cat >> "$report_file" << EOF
        </tbody>
    </table>
    
    <div class="details">
        <h2>🖥️ System Information</h2>
        <pre>$(cat "$TEST_SESSION_DIR/system_info.txt")</pre>
    </div>
    
    <div class="details">
        <h2>📁 Test Artifacts</h2>
        <p>Detailed logs and artifacts are available in: <code>$TEST_SESSION_DIR</code></p>
        <ul>
            <li><strong>Logs:</strong> Individual test logs in <code>logs/</code></li>
            <li><strong>Benchmarks:</strong> Performance data in <code>benchmarks/</code></li>
            <li><strong>Reports:</strong> Summary reports in <code>reports/</code></li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log_success "Test report generated: $report_file"
    log_success "Test summary generated: $summary_file"
    
    # Display summary
    echo ""
    cat "$summary_file"
}

# Main execution
main() {
    # Initialize
    init_test_environment
    
    # Core functionality tests
    log_header "🔧 Core Functionality Tests"
    run_test "pak_installation" "test_pak_installation" "Test pak package installation and basic functionality"
    run_test "package_installation_basic" "test_package_installation_basic" "Test basic CRAN package installation"
    run_test "special_packages" "test_special_packages" "Test GitHub and archive package installation"
    run_test "package_loading" "test_package_loading" "Test package loading and functionality"
    run_test "dependency_resolution" "test_dependency_resolution" "Test dependency resolution capabilities"
    run_test "cache_functionality" "test_cache_functionality" "Test pak cache management"
    run_test "error_handling" "test_error_handling" "Test error handling and recovery"
    
    # Performance tests
    if [[ "$ENABLE_PERFORMANCE_TESTS" == "true" ]]; then
        log_header "⚡ Performance Tests"
        run_test "performance_benchmark" "test_performance_benchmark" "Benchmark pak vs traditional installation"
    else
        skip_test "performance_benchmark" "Performance tests disabled"
    fi
    
    # Regression tests
    if [[ "$ENABLE_REGRESSION_TESTS" == "true" ]]; then
        log_header "🔄 Regression Tests"
        run_test "regression_compatibility" "test_regression_compatibility" "Test compatibility with existing package list"
    else
        skip_test "regression_compatibility" "Regression tests disabled"
    fi
    
    # Multi-architecture tests
    if [[ "$ENABLE_MULTIARCH_TESTS" == "true" ]]; then
        log_header "🏗️ Multi-Architecture Tests"
        run_test "multiarch_support" "test_multiarch_support" "Test multi-architecture support"
    else
        skip_test "multiarch_support" "Multi-architecture tests disabled"
    fi
    
    # Stress tests
    if [[ "$ENABLE_STRESS_TESTS" == "true" ]]; then
        log_header "💪 Stress Tests"
        run_test "stress_installation" "test_stress_installation" "Test installation under stress conditions"
    else
        skip_test "stress_installation" "Stress tests disabled"
    fi
    
    # Generate report
    generate_test_report
    
    # Final summary
    log_header "🎯 Test Suite Complete"
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed! ($TESTS_PASSED/$TESTS_TOTAL)"
        exit 0
    else
        log_error "Some tests failed ($TESTS_FAILED/$TESTS_TOTAL)"
        log_info "Check detailed logs in: $TEST_SESSION_DIR"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Phase 4 Testing and Validation Framework"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --verbose               Enable verbose output"
        echo "  --no-performance        Disable performance tests"
        echo "  --no-regression         Disable regression tests"
        echo "  --enable-multiarch      Enable multi-architecture tests"
        echo "  --enable-stress         Enable stress tests"
        echo ""
        echo "Environment Variables:"
        echo "  ENABLE_PERFORMANCE_TESTS=true|false"
        echo "  ENABLE_REGRESSION_TESTS=true|false"
        echo "  ENABLE_MULTIARCH_TESTS=true|false"
        echo "  ENABLE_STRESS_TESTS=true|false"
        echo "  VERBOSE=true|false"
        exit 0
        ;;
    --verbose)
        VERBOSE=true
        ;;
    --no-performance)
        ENABLE_PERFORMANCE_TESTS=false
        ;;
    --no-regression)
        ENABLE_REGRESSION_TESTS=false
        ;;
    --enable-multiarch)
        ENABLE_MULTIARCH_TESTS=true
        ;;
    --enable-stress)
        ENABLE_STRESS_TESTS=true
        ;;
esac

# Ensure bc is available for calculations
if ! command -v bc >/dev/null 2>&1; then
    log_error "bc (basic calculator) is required but not installed"
    exit 1
fi

# Run main function
main "$@"