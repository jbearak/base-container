#!/bin/bash
# test_pak_installation.sh - Test script for pak-based R package installation
# Phase 3 implementation testing

set -e

echo "🧪 Testing pak-based R package installation"
echo "==========================================="
echo "Test start time: $(date)"
echo

# Create a test packages file with a small subset
TEST_PACKAGES_FILE="/tmp/test_packages.txt"
cat > "$TEST_PACKAGES_FILE" << 'EOF'
dplyr
ggplot2
readr
tibble
stringr
EOF

echo "📋 Created test packages file with 5 CRAN packages:"
cat "$TEST_PACKAGES_FILE"
echo

# Test 1: Bash script with debug mode
echo "🧪 Test 1: Bash script (install_r_packages_pak.sh) with debug mode"
echo "=================================================================="
if [[ -f "./install_r_packages_pak.sh" ]]; then
    echo "Running: ./install_r_packages_pak.sh --debug --packages-file $TEST_PACKAGES_FILE"
    ./install_r_packages_pak.sh --debug --packages-file "$TEST_PACKAGES_FILE"
    echo "✅ Test 1 completed successfully"
else
    echo "❌ install_r_packages_pak.sh not found"
    exit 1
fi

echo
echo "🧪 Test 2: Direct R script (install_packages.R) with debug mode"
echo "==============================================================="
if [[ -f "./install_packages.R" ]]; then
    echo "Running: ./install_packages.R $TEST_PACKAGES_FILE --debug"
    ./install_packages.R "$TEST_PACKAGES_FILE" --debug
    echo "✅ Test 2 completed successfully"
else
    echo "❌ install_packages.R not found"
    exit 1
fi

echo
echo "🧪 Test 3: Package verification"
echo "==============================="

# Verify that test packages are installed
VERIFY_SCRIPT="/tmp/verify_packages.R"
cat > "$VERIFY_SCRIPT" << 'EOF'
# Verify test packages are installed
test_packages <- c("dplyr", "ggplot2", "readr", "tibble", "stringr")
special_packages <- c("mcmcplots", "httpgd", "colorout")

installed_pkgs <- rownames(installed.packages())

cat("📋 Checking test packages...\n")
missing_test <- setdiff(test_packages, installed_pkgs)
if (length(missing_test) > 0) {
    cat("❌ Missing test packages:", paste(missing_test, collapse = ", "), "\n")
} else {
    cat("✅ All test packages found\n")
}

cat("📋 Checking special packages...\n")
missing_special <- setdiff(special_packages, installed_pkgs)
if (length(missing_special) > 0) {
    cat("❌ Missing special packages:", paste(missing_special, collapse = ", "), "\n")
} else {
    cat("✅ All special packages found\n")
}

# Test loading key packages
cat("📋 Testing package loading...\n")
test_load <- function(pkg) {
    tryCatch({
        library(pkg, character.only = TRUE, quietly = TRUE)
        cat("✅", pkg, "loads successfully\n")
        return(TRUE)
    }, error = function(e) {
        cat("❌", pkg, "failed to load:", conditionMessage(e), "\n")
        return(FALSE)
    })
}

success_count <- 0
for (pkg in c(test_packages, special_packages)) {
    if (test_load(pkg)) {
        success_count <- success_count + 1
    }
}

total_packages <- length(test_packages) + length(special_packages)
cat("\n📊 Package loading summary:\n")
cat("   ✅ Successfully loaded:", success_count, "/", total_packages, "packages\n")

if (success_count == total_packages) {
    cat("🎉 All packages loaded successfully!\n")
} else {
    cat("⚠️  Some packages failed to load\n")
    quit(status = 1)
}
EOF

echo "Running package verification..."
Rscript "$VERIFY_SCRIPT"
echo "✅ Test 3 completed successfully"

echo
echo "🧪 Test 4: Performance comparison setup"
echo "======================================="

# Create timing comparison script
TIMING_SCRIPT="/tmp/timing_comparison.R"
cat > "$TIMING_SCRIPT" << 'EOF'
# Compare pak vs traditional installation timing for a small package
library(pak)

test_pkg <- "praise"  # Small package for quick testing

# Remove package if installed
if ("praise" %in% rownames(installed.packages())) {
    remove.packages("praise")
}

cat("⏱️  Testing pak installation speed...\n")
start_time <- Sys.time()
pak::pkg_install("praise")
pak_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

# Remove again for fair comparison
remove.packages("praise")

cat("⏱️  Testing traditional installation speed...\n")
start_time <- Sys.time()
install.packages("praise", repos = "https://cloud.r-project.org/", quiet = TRUE)
traditional_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n📊 Installation speed comparison:\n")
cat("   pak:", sprintf("%.2f", pak_time), "seconds\n")
cat("   traditional:", sprintf("%.2f", traditional_time), "seconds\n")

if (pak_time < traditional_time) {
    improvement <- ((traditional_time - pak_time) / traditional_time) * 100
    cat("   🚀 pak is", sprintf("%.1f%%", improvement), "faster\n")
} else {
    slowdown <- ((pak_time - traditional_time) / traditional_time) * 100
    cat("   🐌 pak is", sprintf("%.1f%%", slowdown), "slower\n")
}
EOF

echo "Running performance comparison..."
Rscript "$TIMING_SCRIPT"
echo "✅ Test 4 completed successfully"

# Cleanup
rm -f "$TEST_PACKAGES_FILE" "$VERIFY_SCRIPT" "$TIMING_SCRIPT"

echo
echo "🎉 ALL TESTS COMPLETED SUCCESSFULLY!"
echo "===================================="
echo "✅ Bash script installation works"
echo "✅ R script installation works"  
echo "✅ Package verification works"
echo "✅ Performance comparison completed"
echo "Test end time: $(date)"
echo
echo "📋 Next steps for Phase 3:"
echo "  1. Review test results above"
echo "  2. Compare with original install_r_packages.sh behavior"
echo "  3. Proceed to Phase 4 (Testing & Validation) when ready"