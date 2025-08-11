#!/opt/homebrew/bin/bash
# run_phase4_tests.sh - Master Test Runner for Phase 4
# Phase 4 implementation for pak migration (Issue #2)
#
# This script runs all Phase 4 tests in the correct order and generates
# a comprehensive summary report.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_RESULTS_DIR="${SCRIPT_DIR}/phase4_test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SESSION_DIR="${MASTER_RESULTS_DIR}/${TIMESTAMP}"

# Configuration
TEST_LEVEL=${TEST_LEVEL:-standard}  # quick, standard, comprehensive
PARALLEL_EXECUTION=${PARALLEL_EXECUTION:-false}
VERBOSE=${VERBOSE:-false}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "$1" | tee -a "${SESSION_DIR}/master_test.log"
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

# Initialize master test environment
init_master_testing() {
    # Create directories first before any logging
    mkdir -p "$SESSION_DIR"/{logs,reports,summaries}
    
    log_header "🧪 Phase 4: Master Test Runner"
    log_info "Session: $TIMESTAMP"
    log_info "Test level: $TEST_LEVEL"
    log_info "Parallel execution: $PARALLEL_EXECUTION"
    log_info "Results directory: $SESSION_DIR"
    
    # Check prerequisites
    local missing_tools=()
    for tool in bc jq R docker; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
    
    # Check R packages
    if ! R --slave --no-restore -e "library(pak); library(jsonlite)" >/dev/null 2>&1; then
        log_warning "Required R packages (pak, jsonlite) may not be installed"
        log_info "Installing required R packages..."
        R --slave --no-restore -e "
        if (!require('pak', quietly = TRUE)) {
            install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')
        }
        if (!require('jsonlite', quietly = TRUE)) {
            install.packages('jsonlite', repos = 'https://cloud.r-project.org/')
        }
        " || log_warning "Failed to install R packages automatically"
    fi
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR"/{test_suite_phase4.sh,test_build_performance.sh,test_regression_comparison.sh,test_package_validation.R} 2>/dev/null || true
    
    log_success "Master test environment initialized"
}

# Configure test parameters based on test level
#
# TEST LEVEL CONFIGURATION MATRIX:
# ┌─────────────────────────────┬─────────┬──────────┬──────────────┐
# │ Test Component              │ Quick   │ Standard │ Comprehensive│
# ├─────────────────────────────┼─────────┼──────────┼──────────────┤
# │ Core Functionality          │ ✓       │ ✓        │ ✓            │
# │ Package Validation          │ ✓ (20)  │ ✓ (50)   │ ✓ (100)      │
# │ Regression Testing          │ ✓ (10)  │ ✓ (20)   │ ✓ (50)       │
# │ Build Performance Tests     │ ✗       │ ✓        │ ✓            │
# │ Stress Testing              │ ✗       │ ✗        │ ✓            │
# │ Multi-architecture Tests    │ ✗       │ ✗        │ ✓            │
# │ Deep Package Validation     │ ✗       │ ✗        │ ✓            │
# │ Cache Performance Analysis  │ ✗       │ ✓        │ ✓            │
# │ Estimated Runtime           │ ~2 min  │ ~10 min  │ ~30+ min     │
# └─────────────────────────────┴─────────┴──────────┴──────────────┘
#
# Numbers in parentheses indicate sample sizes for testing.
# ✓ = Enabled, ✗ = Disabled
#
configure_test_level() {
    case "$TEST_LEVEL" in
        quick)
            log_info "Configuring for quick testing..."
            export ENABLE_PERFORMANCE_TESTS=false
            export ENABLE_REGRESSION_TESTS=true
            export ENABLE_MULTIARCH_TESTS=false
            export ENABLE_STRESS_TESTS=false
            export SAMPLE_SIZE=10
            export ITERATIONS=1
            PACKAGE_VALIDATION_ARGS="--quick"
            REGRESSION_ARGS="--sample-size 10"
            BUILD_PERF_ARGS="--no-cache"
            ;;
        comprehensive)
            log_info "Configuring for comprehensive testing..."
            export ENABLE_PERFORMANCE_TESTS=true
            export ENABLE_REGRESSION_TESTS=true
            export ENABLE_MULTIARCH_TESTS=true
            export ENABLE_STRESS_TESTS=true
            export SAMPLE_SIZE=50
            export ITERATIONS=5
            PACKAGE_VALIDATION_ARGS="--deep --verbose"
            REGRESSION_ARGS="--full-comparison --verbose"
            BUILD_PERF_ARGS="--enable-multiarch --verbose"
            ;;
        *)  # standard
            log_info "Configuring for standard testing..."
            export ENABLE_PERFORMANCE_TESTS=true
            export ENABLE_REGRESSION_TESTS=true
            export ENABLE_MULTIARCH_TESTS=false
            export ENABLE_STRESS_TESTS=false
            export SAMPLE_SIZE=20
            export ITERATIONS=3
            PACKAGE_VALIDATION_ARGS=""
            REGRESSION_ARGS="--sample-size 20"
            BUILD_PERF_ARGS=""
            ;;
    esac
    
    if [[ "$VERBOSE" == "true" ]]; then
        export VERBOSE=true
        PACKAGE_VALIDATION_ARGS="$PACKAGE_VALIDATION_ARGS --verbose"
        REGRESSION_ARGS="$REGRESSION_ARGS --verbose"
        BUILD_PERF_ARGS="$BUILD_PERF_ARGS --verbose"
    fi
}

# Run individual test suite
run_test_suite() {
    local test_name="$1"
    local test_command="$2"
    local test_description="$3"
    
    log_header "Running $test_name"
    log_info "Description: $test_description"
    log_info "Command: $test_command"
    
    local start_time=$(date +%s.%N)
    local test_log="${SESSION_DIR}/logs/${test_name}.log"
    local test_success=false
    
    if eval "$test_command" > "$test_log" 2>&1; then
        test_success=true
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Create test result summary
    cat > "${SESSION_DIR}/summaries/${test_name}_summary.json" << EOF
{
    "test_name": "$test_name",
    "description": "$test_description",
    "command": "$test_command",
    "success": $test_success,
    "duration_seconds": $duration,
    "timestamp": "$(date -Iseconds)",
    "log_file": "$test_log"
}
EOF
    
    if [[ "$test_success" == "true" ]]; then
        log_success "$test_name completed successfully (${duration}s)"
        return 0
    else
        log_error "$test_name failed (${duration}s)"
        if [[ "$VERBOSE" == "true" ]]; then
            log "Last 10 lines of error log:"
            tail -n 10 "$test_log" | sed 's/^/  /'
        fi
        return 1
    fi
}

# Run all test suites
run_all_tests() {
    log_header "🚀 Running All Phase 4 Test Suites"
    
    local test_results=()
    
    # Test 1: Core functionality tests
    if run_test_suite "core_functionality" \
        "./test_suite_phase4.sh" \
        "Core pak functionality and basic package installation tests"; then
        test_results+=("core_functionality:PASSED")
    else
        test_results+=("core_functionality:FAILED")
    fi
    
    # Test 2: Package validation
    if run_test_suite "package_validation" \
        "Rscript test_package_validation.R $PACKAGE_VALIDATION_ARGS" \
        "Comprehensive package validation and functionality testing"; then
        test_results+=("package_validation:PASSED")
    else
        test_results+=("package_validation:FAILED")
    fi
    
    # Test 3: Regression testing
    if run_test_suite "regression_testing" \
        "./test_regression_comparison.sh $REGRESSION_ARGS" \
        "Regression testing comparing pak vs traditional installation"; then
        test_results+=("regression_testing:PASSED")
    else
        test_results+=("regression_testing:FAILED")
    fi
    
    # Test 4: Build performance (if enabled)
    if [[ "$ENABLE_PERFORMANCE_TESTS" == "true" ]]; then
        if run_test_suite "build_performance" \
            "ITERATIONS=$ITERATIONS ./test_build_performance.sh $BUILD_PERF_ARGS" \
            "Docker build performance testing and cache effectiveness"; then
            test_results+=("build_performance:PASSED")
        else
            test_results+=("build_performance:FAILED")
        fi
    else
        log_info "Skipping build performance tests (disabled)"
        test_results+=("build_performance:SKIPPED")
    fi
    
    # Save overall test results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    for result in "${test_results[@]}"; do
        case "$result" in
            *:PASSED) ((passed_tests++)); ((total_tests++)) ;;
            *:FAILED) ((failed_tests++)); ((total_tests++)) ;;
            *:SKIPPED) ((skipped_tests++)) ;;
        esac
    done
    
    # Create master summary
    cat > "${SESSION_DIR}/summaries/master_summary.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "session_id": "$TIMESTAMP",
    "test_level": "$TEST_LEVEL",
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "failed_tests": $failed_tests,
    "skipped_tests": $skipped_tests,
    "success_rate": $(echo "scale=3; $passed_tests / $total_tests" | bc -l),
    "test_results": [
        $(printf '"%s",' "${test_results[@]}" | sed 's/,$//')
    ]
}
EOF
    
    log_header "📊 Test Execution Summary"
    log_info "Total tests: $total_tests"
    log_info "Passed: $passed_tests"
    log_info "Failed: $failed_tests"
    log_info "Skipped: $skipped_tests"
    log_info "Success rate: $(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l)%"
    
    return $failed_tests
}

# Generate comprehensive master report
generate_master_report() {
    log_header "📊 Generating Master Report"
    
    local report_file="${SESSION_DIR}/reports/phase4_master_report.html"
    local summary_file="${SESSION_DIR}/reports/phase4_master_summary.txt"
    
    # Collect all test results
    local all_results_dirs=()
    for results_dir in test_results package_validation_results regression_test_results build_performance_results; do
        if [[ -d "$results_dir" ]]; then
            local latest_subdir=$(ls -1t "$results_dir" 2>/dev/null | head -1)
            if [[ -n "$latest_subdir" ]] && [[ -d "$results_dir/$latest_subdir" ]]; then
                all_results_dirs+=("$results_dir/$latest_subdir")
            fi
        fi
    done
    
    # Generate text summary
    {
        echo "=== Phase 4 Testing and Validation - Master Report ==="
        echo "Session: $TIMESTAMP"
        echo "Generated: $(date)"
        echo "Test Level: $TEST_LEVEL"
        echo ""
        
        if [[ -f "${SESSION_DIR}/summaries/master_summary.json" ]]; then
            echo "=== Overall Results ==="
            jq -r '
                "Total Tests: " + (.total_tests | tostring),
                "Passed: " + (.passed_tests | tostring),
                "Failed: " + (.failed_tests | tostring),
                "Skipped: " + (.skipped_tests | tostring),
                "Success Rate: " + ((.success_rate * 100) | tostring) + "%"
            ' "${SESSION_DIR}/summaries/master_summary.json"
            echo ""
        fi
        
        echo "=== Individual Test Results ==="
        for summary_file in "${SESSION_DIR}/summaries"/*_summary.json; do
            if [[ -f "$summary_file" ]] && [[ "$(basename "$summary_file")" != "master_summary.json" ]]; then
                local test_name=$(jq -r '.test_name' "$summary_file")
                local success=$(jq -r '.success' "$summary_file")
                local duration=$(jq -r '.duration_seconds' "$summary_file")
                
                if [[ "$success" == "true" ]]; then
                    echo "✅ $test_name: PASSED (${duration}s)"
                else
                    echo "❌ $test_name: FAILED (${duration}s)"
                fi
            fi
        done
        echo ""
        
        echo "=== Detailed Results ==="
        for results_dir in "${all_results_dirs[@]}"; do
            if [[ -d "$results_dir/reports" ]]; then
                echo "Results from: $results_dir"
                for report in "$results_dir/reports"/*summary*.txt; do
                    if [[ -f "$report" ]]; then
                        echo "--- $(basename "$report") ---"
                        head -15 "$report"
                        echo ""
                    fi
                done
            fi
        done
        
        echo "=== Recommendations ==="
        local master_summary="${SESSION_DIR}/summaries/master_summary.json"
        if [[ -f "$master_summary" ]]; then
            local success_rate=$(jq -r '.success_rate' "$master_summary")
            local failed_tests=$(jq -r '.failed_tests' "$master_summary")
            
            if (( $(echo "$success_rate >= 0.9" | bc -l) )); then
                echo "✅ Phase 4 testing completed successfully"
                echo "   - All critical tests passed"
                echo "   - pak migration is ready for production use"
            elif (( $(echo "$success_rate >= 0.7" | bc -l) )); then
                echo "⚠️  Phase 4 testing completed with minor issues"
                echo "   - Review failed tests and address issues"
                echo "   - Consider additional testing before production deployment"
            else
                echo "❌ Phase 4 testing revealed significant issues"
                echo "   - Address all failed tests before proceeding"
                echo "   - Consider reverting to traditional installation method"
            fi
        fi
        
        echo ""
        echo "=== Next Steps ==="
        echo "1. Review detailed test results in: $SESSION_DIR"
        echo "2. Check individual test logs for failure details"
        echo "3. Refer to PHASE4_TESTING_README.md for interpretation guidelines"
        echo "4. Address any identified issues before proceeding to Phase 5"
    } > "$summary_file"
    
    # Generate HTML report
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Phase 4 Master Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; }
        .metric h3 { margin: 0; color: #2c5aa0; }
        .metric .value { font-size: 24px; font-weight: bold; color: #1a365d; }
        .passed { background: #d4edda; color: #155724; }
        .failed { background: #f8d7da; color: #721c24; }
        .details { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
        pre { background: #f1f1f1; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 Phase 4 Testing and Validation - Master Report</h1>
        <p><strong>Session:</strong> $TIMESTAMP</p>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Test Level:</strong> $TEST_LEVEL</p>
    </div>
    
    <div class="details">
        <h2>📊 Complete Test Results</h2>
        <pre>$(cat "$summary_file")</pre>
    </div>
    
    <div class="details">
        <h2>📁 Test Artifacts</h2>
        <p>All test results and artifacts are available in: <code>$SESSION_DIR</code></p>
        <ul>
            <li><strong>Individual Test Logs:</strong> <code>logs/</code></li>
            <li><strong>Test Summaries:</strong> <code>summaries/</code></li>
            <li><strong>Master Reports:</strong> <code>reports/</code></li>
            <li><strong>Detailed Results:</strong> Individual test result directories</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log_success "Master report generated: $report_file"
    log_success "Master summary generated: $summary_file"
    
    # Display summary
    echo ""
    cat "$summary_file"
}

# Main execution
main() {
    init_master_testing
    configure_test_level
    
    local start_time=$(date +%s.%N)
    
    # Run all tests
    local test_exit_code=0
    if ! run_all_tests; then
        test_exit_code=1
    fi
    
    local end_time=$(date +%s.%N)
    local total_duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Generate master report
    generate_master_report
    
    log_header "🎯 Phase 4 Testing Complete"
    log_info "Total execution time: ${total_duration}s"
    log_success "Master results available in: $SESSION_DIR"
    
    if [[ $test_exit_code -eq 0 ]]; then
        log_success "All Phase 4 tests completed successfully!"
        echo ""
        echo "🎉 Phase 4 testing passed! The pak migration is ready for the next phase."
    else
        log_warning "Some Phase 4 tests failed"
        echo ""
        echo "⚠️  Please review the test results and address any issues before proceeding."
    fi
    
    exit $test_exit_code
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Phase 4 Master Test Runner"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --level LEVEL           Test level: quick, standard, comprehensive (default: standard)"
        echo "  --parallel              Enable parallel test execution (experimental)"
        echo "  --verbose               Enable verbose output"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_LEVEL=quick|standard|comprehensive"
        echo "  PARALLEL_EXECUTION=true|false"
        echo "  VERBOSE=true|false"
        echo ""
        echo "Test Levels:"
        echo "  quick        - Fast validation with minimal tests"
        echo "  standard     - Comprehensive testing with reasonable runtime"
        echo "  comprehensive - Full testing including stress and multi-arch tests"
        exit 0
        ;;
    --level)
        TEST_LEVEL="$2"
        shift 2
        ;;
    --parallel)
        PARALLEL_EXECUTION=true
        ;;
    --verbose)
        VERBOSE=true
        ;;
esac

# Validate test level
case "$TEST_LEVEL" in
    quick|standard|comprehensive) ;;
    *)
        log_error "Invalid test level: $TEST_LEVEL"
        log_info "Valid levels: quick, standard, comprehensive"
        exit 1
        ;;
esac

# Run main function
main "$@"