#!/bin/bash
# test_regression_comparison.sh - Regression Testing Framework
# Phase 4 implementation for pak migration (Issue #2)
#
# This script performs comprehensive regression testing to ensure that the
# pak-based installation produces identical results to the traditional
# install.packages() approach.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/regression_test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SESSION_DIR="${RESULTS_DIR}/${TIMESTAMP}"

# Configuration
SAMPLE_SIZE=${SAMPLE_SIZE:-20}
ENABLE_FULL_COMPARISON=${ENABLE_FULL_COMPARISON:-false}
ENABLE_PERFORMANCE_COMPARISON=${ENABLE_PERFORMANCE_COMPARISON:-true}
VERBOSE=${VERBOSE:-false}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() {
    echo -e "$1" | tee -a "${SESSION_DIR}/regression_test.log"
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

# Initialize regression testing environment
init_regression_testing() {
    log_header "🔄 Phase 4: Regression Testing Framework"
    log_info "Session: $TIMESTAMP"
    log_info "Results directory: $SESSION_DIR"
    log_info "Sample size: $SAMPLE_SIZE"
    log_info "Full comparison: $ENABLE_FULL_COMPARISON"
    
    mkdir -p "$SESSION_DIR"/{logs,metrics,reports,environments}
    
    # Create isolated R environments for testing
    mkdir -p "$SESSION_DIR/environments"/{traditional,pak}
    
    log_success "Regression testing environment initialized"
}

# Create test package list
create_test_package_list() {
    local packages_file="$SCRIPT_DIR/R_packages.txt"
    local test_packages_file="$SESSION_DIR/test_packages.txt"
    
    if [[ ! -f "$packages_file" ]]; then
        log_error "R_packages.txt not found"
        return 1
    fi
    
    # Read and filter packages
    local all_packages=($(grep -v '^#' "$packages_file" | grep -v '^$' | head -n "$SAMPLE_SIZE"))
    
    if [[ "$ENABLE_FULL_COMPARISON" == "true" ]]; then
        all_packages=($(grep -v '^#' "$packages_file" | grep -v '^$'))
        log_info "Full comparison mode: testing all $(echo ${#all_packages[@]}) packages"
    fi
    
    # Write test packages to file
    printf '%s\n' "${all_packages[@]}" > "$test_packages_file"
    
    log_info "Created test package list with ${#all_packages[@]} packages"
    echo "$test_packages_file"
}

# Install packages using traditional method
install_traditional() {
    local packages_file="$1"
    local lib_dir="$SESSION_DIR/environments/traditional"
    local log_file="$SESSION_DIR/logs/traditional_install.log"
    
    log_info "Installing packages using traditional method..."
    
    local start_time=$(date +%s.%N)
    
    # Create R script for traditional installation
    cat > "$SESSION_DIR/traditional_install.R" << EOF
# Traditional installation script
.libPaths(c("$lib_dir", .libPaths()))

packages <- readLines("$packages_file")
packages <- packages[packages != "" & !grepl("^#", packages)]

cat("Installing", length(packages), "packages using traditional method...\n")

install_results <- list()
successful_installs <- 0
failed_installs <- 0

for (pkg in packages) {
    cat("Installing:", pkg, "\n")
    
    result <- tryCatch({
        install.packages(pkg, 
                        lib = "$lib_dir",
                        repos = "https://cloud.r-project.org/",
                        dependencies = TRUE,
                        quiet = FALSE)
        
        # Verify installation
        if (pkg %in% rownames(installed.packages(lib.loc = "$lib_dir"))) {
            successful_installs <<- successful_installs + 1
            list(success = TRUE, error = NULL)
        } else {
            failed_installs <<- failed_installs + 1
            list(success = FALSE, error = "Package not found after installation")
        }
    }, error = function(e) {
        failed_installs <<- failed_installs + 1
        list(success = FALSE, error = conditionMessage(e))
    })
    
    install_results[[pkg]] <- result
}

# Save results
library(jsonlite)
summary_results <- list(
    method = "traditional",
    total_packages = length(packages),
    successful_installs = successful_installs,
    failed_installs = failed_installs,
    success_rate = successful_installs / length(packages),
    install_results = install_results
)

write_json(summary_results, "$SESSION_DIR/metrics/traditional_results.json", pretty = TRUE)

cat("Traditional installation completed:\n")
cat("  Successful:", successful_installs, "/", length(packages), "\n")
cat("  Failed:", failed_installs, "\n")
cat("  Success rate:", sprintf("%.1f%%", successful_installs * 100 / length(packages)), "\n")
EOF
    
    # Run traditional installation
    if R --slave --no-restore < "$SESSION_DIR/traditional_install.R" > "$log_file" 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        
        log_success "Traditional installation completed in ${duration}s"
        echo "$duration" > "$SESSION_DIR/metrics/traditional_time.txt"
        return 0
    else
        log_error "Traditional installation failed"
        return 1
    fi
}

# Install packages using pak method
install_pak() {
    local packages_file="$1"
    local lib_dir="$SESSION_DIR/environments/pak"
    local log_file="$SESSION_DIR/logs/pak_install.log"
    
    log_info "Installing packages using pak method..."
    
    local start_time=$(date +%s.%N)
    
    # Create R script for pak installation
    cat > "$SESSION_DIR/pak_install.R" << EOF
# Pak installation script
.libPaths(c("$lib_dir", .libPaths()))

# Install pak if not available
if (!require("pak", quietly = TRUE)) {
    install.packages("pak", repos = "https://r-lib.github.io/p/pak/stable/")
}

library(pak)

packages <- readLines("$packages_file")
packages <- packages[packages != "" & !grepl("^#", packages)]

cat("Installing", length(packages), "packages using pak...\n")

install_results <- list()
successful_installs <- 0
failed_installs <- 0

# Configure pak to use the specific library
pak::pkg_install_plan(packages, lib = "$lib_dir")

for (pkg in packages) {
    cat("Installing:", pkg, "\n")
    
    result <- tryCatch({
        pak::pkg_install(pkg, lib = "$lib_dir", ask = FALSE)
        
        # Verify installation
        if (pkg %in% rownames(installed.packages(lib.loc = "$lib_dir"))) {
            successful_installs <<- successful_installs + 1
            list(success = TRUE, error = NULL)
        } else {
            failed_installs <<- failed_installs + 1
            list(success = FALSE, error = "Package not found after installation")
        }
    }, error = function(e) {
        failed_installs <<- failed_installs + 1
        list(success = FALSE, error = conditionMessage(e))
    })
    
    install_results[[pkg]] <- result
}

# Save results
library(jsonlite)
summary_results <- list(
    method = "pak",
    total_packages = length(packages),
    successful_installs = successful_installs,
    failed_installs = failed_installs,
    success_rate = successful_installs / length(packages),
    install_results = install_results
)

write_json(summary_results, "$SESSION_DIR/metrics/pak_results.json", pretty = TRUE)

cat("Pak installation completed:\n")
cat("  Successful:", successful_installs, "/", length(packages), "\n")
cat("  Failed:", failed_installs, "\n")
cat("  Success rate:", sprintf("%.1f%%", successful_installs * 100 / length(packages)), "\n")
EOF
    
    # Run pak installation
    if R --slave --no-restore < "$SESSION_DIR/pak_install.R" > "$log_file" 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        
        log_success "Pak installation completed in ${duration}s"
        echo "$duration" > "$SESSION_DIR/metrics/pak_time.txt"
        return 0
    else
        log_error "Pak installation failed"
        return 1
    fi
}

# Compare installation results
compare_installations() {
    log_header "📊 Comparing Installation Results"
    
    local traditional_results="$SESSION_DIR/metrics/traditional_results.json"
    local pak_results="$SESSION_DIR/metrics/pak_results.json"
    
    if [[ ! -f "$traditional_results" ]] || [[ ! -f "$pak_results" ]]; then
        log_error "Missing installation results files"
        return 1
    fi
    
    # Create comparison script
    cat > "$SESSION_DIR/compare_results.R" << EOF
library(jsonlite)

# Load results
traditional <- fromJSON("$traditional_results")
pak <- fromJSON("$pak_results")

# Compare success rates
cat("=== Installation Success Rate Comparison ===\n")
cat("Traditional:", sprintf("%.1f%%", traditional\$success_rate * 100), 
    "(", traditional\$successful_installs, "/", traditional\$total_packages, ")\n")
cat("Pak:", sprintf("%.1f%%", pak\$success_rate * 100), 
    "(", pak\$successful_installs, "/", pak\$total_packages, ")\n")

success_rate_diff <- (pak\$success_rate - traditional\$success_rate) * 100
cat("Difference:", sprintf("%.1f%%", success_rate_diff), "\n")

# Find packages that succeeded in one method but failed in another
traditional_success <- names(traditional\$install_results)[
    sapply(traditional\$install_results, function(x) x\$success)
]
pak_success <- names(pak\$install_results)[
    sapply(pak\$install_results, function(x) x\$success)
]

only_traditional <- setdiff(traditional_success, pak_success)
only_pak <- setdiff(pak_success, traditional_success)

cat("\n=== Package Installation Differences ===\n")
cat("Packages that succeeded only with traditional method:", length(only_traditional), "\n")
if (length(only_traditional) > 0) {
    cat("  ", paste(head(only_traditional, 10), collapse = ", "), "\n")
}

cat("Packages that succeeded only with pak:", length(only_pak), "\n")
if (length(only_pak) > 0) {
    cat("  ", paste(head(only_pak, 10), collapse = ", "), "\n")
}

# Performance comparison
if (file.exists("$SESSION_DIR/metrics/traditional_time.txt") && 
    file.exists("$SESSION_DIR/metrics/pak_time.txt")) {
    
    traditional_time <- as.numeric(readLines("$SESSION_DIR/metrics/traditional_time.txt"))
    pak_time <- as.numeric(readLines("$SESSION_DIR/metrics/pak_time.txt"))
    
    cat("\n=== Performance Comparison ===\n")
    cat("Traditional installation time:", sprintf("%.2f", traditional_time), "seconds\n")
    cat("Pak installation time:", sprintf("%.2f", pak_time), "seconds\n")
    
    if (pak_time < traditional_time) {
        improvement <- ((traditional_time - pak_time) / traditional_time) * 100
        cat("Pak is", sprintf("%.1f%%", improvement), "faster\n")
    } else {
        slowdown <- ((pak_time - traditional_time) / traditional_time) * 100
        cat("Pak is", sprintf("%.1f%%", slowdown), "slower\n")
    }
}

# Create comprehensive comparison report
comparison_report <- list(
    timestamp = "$TIMESTAMP",
    traditional = traditional,
    pak = pak,
    comparison = list(
        success_rate_difference = success_rate_diff,
        only_traditional_success = only_traditional,
        only_pak_success = only_pak,
        performance_improvement = if (exists("improvement")) improvement else if (exists("slowdown")) -slowdown else NA
    )
)

write_json(comparison_report, "$SESSION_DIR/reports/comparison_report.json", pretty = TRUE)

# Determine overall regression test result
regression_passed <- TRUE

# Check if pak success rate is not significantly worse
if (success_rate_diff < -5) {  # Allow 5% tolerance
    cat("\n❌ REGRESSION: Pak success rate is significantly lower\n")
    regression_passed <- FALSE
}

# Check if there are critical packages that only work with traditional method
critical_packages <- c("dplyr", "ggplot2", "readr", "tibble", "stringr")
critical_failures <- intersect(only_traditional, critical_packages)
if (length(critical_failures) > 0) {
    cat("\n❌ REGRESSION: Critical packages failed with pak:", paste(critical_failures, collapse = ", "), "\n")
    regression_passed <- FALSE
}

if (regression_passed) {
    cat("\n✅ REGRESSION TEST PASSED: Pak performs equivalently to traditional method\n")
    quit(status = 0)
} else {
    cat("\n❌ REGRESSION TEST FAILED: Pak shows significant regressions\n")
    quit(status = 1)
}
EOF
    
    # Run comparison
    if R --slave --no-restore < "$SESSION_DIR/compare_results.R" > "$SESSION_DIR/logs/comparison.log" 2>&1; then
        log_success "Regression test passed"
        return 0
    else
        log_error "Regression test failed"
        return 1
    fi
}

# Compare package versions and metadata
compare_package_metadata() {
    log_header "🔍 Comparing Package Metadata"
    
    cat > "$SESSION_DIR/compare_metadata.R" << EOF
# Compare package metadata between traditional and pak installations

traditional_lib <- "$SESSION_DIR/environments/traditional"
pak_lib <- "$SESSION_DIR/environments/pak"

# Get installed packages from both libraries
traditional_pkgs <- as.data.frame(installed.packages(lib.loc = traditional_lib), 
                                 stringsAsFactors = FALSE)
pak_pkgs <- as.data.frame(installed.packages(lib.loc = pak_lib), 
                         stringsAsFactors = FALSE)

cat("=== Package Metadata Comparison ===\n")
cat("Traditional library packages:", nrow(traditional_pkgs), "\n")
cat("Pak library packages:", nrow(pak_pkgs), "\n")

# Compare versions for common packages
common_packages <- intersect(traditional_pkgs\$Package, pak_pkgs\$Package)
cat("Common packages:", length(common_packages), "\n")

version_differences <- 0
metadata_issues <- list()

for (pkg in common_packages) {
    trad_info <- traditional_pkgs[traditional_pkgs\$Package == pkg, ]
    pak_info <- pak_pkgs[pak_pkgs\$Package == pkg, ]
    
    if (trad_info\$Version != pak_info\$Version) {
        version_differences <- version_differences + 1
        metadata_issues[[pkg]] <- list(
            traditional_version = trad_info\$Version,
            pak_version = pak_info\$Version
        )
        
        if (version_differences <= 10) {  # Show first 10 differences
            cat("Version difference for", pkg, ":", 
                trad_info\$Version, "(traditional) vs", 
                pak_info\$Version, "(pak)\n")
        }
    }
}

cat("Total version differences:", version_differences, "\n")

# Save metadata comparison
library(jsonlite)
metadata_report <- list(
    timestamp = "$TIMESTAMP",
    traditional_package_count = nrow(traditional_pkgs),
    pak_package_count = nrow(pak_pkgs),
    common_packages = length(common_packages),
    version_differences = version_differences,
    metadata_issues = metadata_issues
)

write_json(metadata_report, "$SESSION_DIR/reports/metadata_comparison.json", pretty = TRUE)

if (version_differences == 0) {
    cat("✅ All package versions match between methods\n")
} else if (version_differences < length(common_packages) * 0.1) {
    cat("⚠️  Minor version differences detected (", version_differences, "/", length(common_packages), ")\n")
} else {
    cat("❌ Significant version differences detected\n")
}
EOF
    
    R --slave --no-restore < "$SESSION_DIR/compare_metadata.R" > "$SESSION_DIR/logs/metadata_comparison.log" 2>&1
    log_success "Package metadata comparison completed"
}

# Generate regression test report
generate_regression_report() {
    log_header "📊 Generating Regression Test Report"
    
    local report_file="$SESSION_DIR/reports/regression_report.html"
    local summary_file="$SESSION_DIR/reports/regression_summary.txt"
    
    # Generate text summary
    {
        echo "=== Regression Testing Report ==="
        echo "Session: $TIMESTAMP"
        echo "Generated: $(date)"
        echo "Sample size: $SAMPLE_SIZE"
        echo "Full comparison: $ENABLE_FULL_COMPARISON"
        echo ""
        
        if [[ -f "$SESSION_DIR/reports/comparison_report.json" ]]; then
            echo "=== Installation Comparison ==="
            jq -r '
                "Traditional success rate: " + (.traditional.success_rate * 100 | tostring) + "%",
                "Pak success rate: " + (.pak.success_rate * 100 | tostring) + "%",
                "Success rate difference: " + (.comparison.success_rate_difference | tostring) + "%",
                "",
                "Packages only successful with traditional: " + (.comparison.only_traditional_success | length | tostring),
                "Packages only successful with pak: " + (.comparison.only_pak_success | length | tostring)
            ' "$SESSION_DIR/reports/comparison_report.json"
            echo ""
        fi
        
        if [[ -f "$SESSION_DIR/reports/metadata_comparison.json" ]]; then
            echo "=== Metadata Comparison ==="
            jq -r '
                "Traditional packages: " + (.traditional_package_count | tostring),
                "Pak packages: " + (.pak_package_count | tostring),
                "Common packages: " + (.common_packages | tostring),
                "Version differences: " + (.version_differences | tostring)
            ' "$SESSION_DIR/reports/metadata_comparison.json"
            echo ""
        fi
        
        echo "=== Test Artifacts ==="
        echo "Detailed results available in: $SESSION_DIR"
        echo "- Installation logs: logs/"
        echo "- Metrics: metrics/"
        echo "- Reports: reports/"
        echo "- Test environments: environments/"
    } > "$summary_file"
    
    # Generate HTML report (simplified version)
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Regression Test Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 15px; border-radius: 5px; text-align: center; }
        .metric h3 { margin: 0; color: #2c5aa0; }
        .metric .value { font-size: 24px; font-weight: bold; color: #1a365d; }
        .passed { background: #d4edda; color: #155724; }
        .failed { background: #f8d7da; color: #721c24; }
        pre { background: #f1f1f1; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔄 Regression Testing Report</h1>
        <p><strong>Session:</strong> $TIMESTAMP</p>
        <p><strong>Generated:</strong> $(date)</p>
    </div>
    
    <div class="summary">
        <pre>$(cat "$summary_file")</pre>
    </div>
</body>
</html>
EOF
    
    log_success "Regression test report generated: $report_file"
    log_success "Regression test summary generated: $summary_file"
    
    # Display summary
    echo ""
    cat "$summary_file"
}

# Main execution
main() {
    init_regression_testing
    
    # Create test package list
    local test_packages_file
    test_packages_file=$(create_test_package_list)
    
    # Install packages using both methods
    install_traditional "$test_packages_file"
    install_pak "$test_packages_file"
    
    # Compare results
    compare_installations
    compare_package_metadata
    
    # Generate report
    generate_regression_report
    
    log_header "🎯 Regression Testing Complete"
    log_success "Results available in: $SESSION_DIR"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Regression Testing Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --sample-size N         Number of packages to test (default: 20)"
        echo "  --full-comparison       Test all packages (overrides sample-size)"
        echo "  --no-performance        Disable performance comparison"
        echo "  --verbose               Enable verbose output"
        echo ""
        echo "Environment Variables:"
        echo "  SAMPLE_SIZE=N"
        echo "  ENABLE_FULL_COMPARISON=true|false"
        echo "  ENABLE_PERFORMANCE_COMPARISON=true|false"
        echo "  VERBOSE=true|false"
        exit 0
        ;;
    --sample-size)
        SAMPLE_SIZE="$2"
        shift 2
        ;;
    --full-comparison)
        ENABLE_FULL_COMPARISON=true
        ;;
    --no-performance)
        ENABLE_PERFORMANCE_COMPARISON=false
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