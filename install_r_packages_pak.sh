#!/bin/bash
# install_r_packages_pak.sh - pak-based R package installer with failed package reporting
# Phase 3 implementation of pak migration plan

# Configuration
PACKAGES_FILE="/tmp/packages.txt"
DEBUG_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --packages-file)
            PACKAGES_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug] [--packages-file FILE]"
            exit 1
            ;;
    esac
done

# Check if packages file exists
if [[ ! -f "$PACKAGES_FILE" ]]; then
    echo "❌ Package file not found: $PACKAGES_FILE"
    exit 1
fi

# Read packages from file, removing empty lines
mapfile -t packages < <(grep -v '^\s*$' "$PACKAGES_FILE")
total_cran_packages=${#packages[@]}

# Define special packages
declare -A special_packages=(
    ["mcmcplots"]="https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz"
    ["httpgd"]="nx10/httpgd"
    ["colorout"]="jalvesaq/colorout"
)

total_special_packages=${#special_packages[@]}
total_packages=$((total_cran_packages + total_special_packages))

if [[ $total_packages -eq 0 ]]; then
    echo "ℹ️  No packages to install"
    exit 0
fi

echo "📦 Installing $total_packages R packages using pak..."
echo "   📋 CRAN packages: $total_cran_packages"
echo "   🔧 Special packages: $total_special_packages"
echo "🕒 Start time: $(date)"
echo

start_time=$(date +%s)
installed_count=0
failed_packages=()

# Function to run R command with proper error handling
run_r_command() {
    local r_command="$1"
    local package_name="$2"
    local debug_output="$3"
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "R command: $r_command"
    fi
    
    # Capture R output and exit code
    local r_output
    local exit_code
    r_output=$(echo "$r_command" | R --slave --no-restore 2>&1)
    exit_code=$?
    
    # Show output in debug mode
    if [[ "$DEBUG_MODE" == "true" || "$debug_output" == "true" ]]; then
        echo "$r_output"
    fi
    
    # Check for success indicators in output
    if [[ $exit_code -eq 0 ]] && ! echo "$r_output" | grep -q -i "error\|failed\|cannot"; then
        echo "✅"
        ((installed_count++))
        return 0
    else
        echo "❌"
        failed_packages+=("$package_name")
        if [[ "$DEBUG_MODE" == "true" ]]; then
            echo "Error output: $r_output"
        fi
        return 1
    fi
}

# Install pak if not already available
echo "🔧 Ensuring pak is available..."
pak_check_command='
if (!requireNamespace("pak", quietly = TRUE)) {
    install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))
}
cat("pak ready\n")
'

echo -n "📦 Installing/checking pak... "
if run_r_command "$pak_check_command" "pak" "false"; then
    : # Success message already printed
else
    echo "❌ Failed to install pak - cannot continue"
    exit 1
fi

# Install CRAN packages in batch using pak
if [[ $total_cran_packages -gt 0 ]]; then
    echo
    echo "📦 Installing $total_cran_packages CRAN packages in batch..."
    
    # Create R vector of package names
    package_vector=$(printf '"%s"' "${packages[0]}")
    for ((i=1; i<${#packages[@]}; i++)); do
        package_vector+=", \"${packages[i]}\""
    done
    
    cran_install_command="
    library(pak)
    packages <- c($package_vector)
    cat('Installing packages:', paste(packages, collapse=', '), '\n')
    
    # Install packages with error handling
    tryCatch({
        pak::pkg_install(packages, dependencies = TRUE)
        cat('CRAN batch installation completed\n')
    }, error = function(e) {
        cat('CRAN batch installation error:', conditionMessage(e), '\n')
        quit(status = 1)
    })
    "
    
    echo -n "📦 Installing CRAN packages batch... "
    if run_r_command "$cran_install_command" "CRAN_batch" "true"; then
        # Count successful installations (approximate - pak handles individual failures internally)
        installed_count=$((installed_count + total_cran_packages - 1)) # -1 because run_r_command already incremented
    else
        # If batch fails, we'll need individual installation fallback
        echo "⚠️  Batch installation failed, falling back to individual package installation..."
        
        # Reset counter and try individual installations
        installed_count=$((installed_count - 1))
        
        for package in "${packages[@]}"; do
            [[ -z "${package// }" ]] && continue
            
            individual_install_command="
            library(pak)
            tryCatch({
                pak::pkg_install('$package', dependencies = TRUE)
                cat('success\n')
            }, error = function(e) {
                cat('failed:', conditionMessage(e), '\n')
                quit(status = 1)
            })
            "
            
            echo -n "📦 Installing $package... "
            run_r_command "$individual_install_command" "$package" "false"
        done
    fi
fi

# Install special packages
echo
echo "📦 Installing special packages..."

for package_name in "${!special_packages[@]}"; do
    package_spec="${special_packages[$package_name]}"
    
    case "$package_name" in
        "mcmcplots")
            echo -n "📦 Installing mcmcplots from CRAN archive... "
            special_install_command="
            library(pak)
            tryCatch({
                pak::pkg_install('$package_spec', dependencies = TRUE)
                cat('success\n')
            }, error = function(e) {
                cat('failed:', conditionMessage(e), '\n')
                quit(status = 1)
            })
            "
            ;;
        "httpgd")
            echo -n "🌐 Installing httpgd from GitHub... "
            special_install_command="
            library(pak)
            tryCatch({
                pak::pkg_install('$package_spec', dependencies = TRUE)
                cat('success\n')
            }, error = function(e) {
                cat('failed:', conditionMessage(e), '\n')
                quit(status = 1)
            })
            "
            ;;
        "colorout")
            echo -n "🎨 Installing colorout from GitHub... "
            special_install_command="
            library(pak)
            tryCatch({
                pak::pkg_install('$package_spec', dependencies = TRUE)
                cat('success\n')
            }, error = function(e) {
                cat('failed:', conditionMessage(e), '\n')
                quit(status = 1)
            })
            "
            ;;
    esac
    
    run_r_command "$special_install_command" "$package_name" "false"
done

# Verify installations
echo
echo "🔍 Verifying package installations..."

verify_command='
library(pak)

# Get list of installed packages
installed_pkgs <- rownames(installed.packages())

# Define expected packages
cran_packages <- readLines("'$PACKAGES_FILE'")
cran_packages <- cran_packages[cran_packages != ""]

special_packages <- c("mcmcplots", "httpgd", "colorout")
all_expected <- c(cran_packages, special_packages)

# Check which packages are missing
missing_packages <- setdiff(all_expected, installed_pkgs)

if (length(missing_packages) > 0) {
    cat("Missing packages:", paste(missing_packages, collapse = ", "), "\n")
    quit(status = 1)
} else {
    cat("All packages verified successfully\n")
}
'

echo -n "🔍 Verifying all packages... "
if run_r_command "$verify_command" "verification" "false"; then
    : # Success message already printed
else
    echo "⚠️  Some packages may not have installed correctly"
fi

# Final summary
end_time=$(date +%s)
total_duration=$((end_time - start_time))
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))
failed_count=${#failed_packages[@]}

echo
echo "=========================================="
echo "📊 R PACKAGE INSTALLATION SUMMARY (pak)"
echo "=========================================="
echo "   ✅ Successfully installed: $installed_count packages"
echo "   ❌ Failed installations: $failed_count packages"
echo "   🕒 Total time: ${total_minutes}m ${total_seconds}s"
echo "   📅 End time: $(date)"
echo

if [[ $failed_count -gt 0 ]]; then
    echo "❌ FAILED PACKAGES:"
    echo "==================="
    for pkg in "${failed_packages[@]}"; do
        echo "   • $pkg"
    done
    echo
    echo "⚠️  Build completed with $failed_count failed package installations."
    echo "    Consider investigating these packages and their system dependencies."
    exit 1
else
    echo "🎉 ALL PACKAGES INSTALLED SUCCESSFULLY!"
    echo "   No failed packages to report."
    echo "   pak-based installation completed successfully."
fi