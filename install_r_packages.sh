#!/bin/bash
# install_r_packages.sh - R package installer with pak support (Phase 1)
# 
# Phase 1 Implementation: Foundation setup with pak integration
# - Installs CRAN packages using pak for better dependency resolution
# - Maintains compatibility with existing special package handling
# - Adds pak-based installation for GitHub packages
# - Preserves current error reporting and debugging features

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
total_packages=${#packages[@]}

if [[ $total_packages -eq 0 ]]; then
    echo "ℹ️  No packages to install"
    exit 0
fi

echo "📦 Installing $total_packages R packages using pak..."
echo "🕒 Start time: $(date)"
echo

start_time=$(date +%s)
installed_count=0
failed_packages=()

# Function to install packages using pak
install_packages_with_pak() {
    local packages_list="$1"
    echo "📦 Installing CRAN packages with pak..."
    
    # Create R script for pak installation
    local r_script="
    library(pak)
    
    # Read packages from file
    packages <- readLines('$PACKAGES_FILE')
    packages <- packages[packages != '']  # Remove empty lines
    
    cat('Installing', length(packages), 'packages with pak...\\n')
    
    # Install packages with pak
    tryCatch({
        pak::pkg_install(packages)
        cat('SUCCESS: All CRAN packages installed\\n')
    }, error = function(e) {
        cat('ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
    })
    "
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "R script for pak installation:"
        echo "$r_script"
        echo "Executing pak installation..."
    fi
    
    # Execute pak installation
    if echo "$r_script" | R --slave --no-restore; then
        echo "✅ CRAN packages installed successfully with pak"
        installed_count=$((installed_count + total_packages))
        return 0
    else
        echo "❌ pak installation failed, falling back to individual package installation"
        return 1
    fi
}

# Function to install a single package (fallback method)
install_package_individual() {
    local package="$1"
    local r_command="if (require('$package', character.only=TRUE, quietly=TRUE)) { 
        cat('already installed\\n') 
    } else { 
        install.packages('$package', repos='https://cloud.r-project.org/', dependencies=TRUE, quiet=TRUE)
        if (require('$package', character.only=TRUE, quietly=TRUE)) {
            cat('success\\n')
        } else {
            cat('failed\\n')
        }
    }"
    
    echo -n "📦 Installing $package... "
    package_start=$(date +%s)
    
    # Capture R output
    local r_output
    r_output=$(echo "$r_command" | R --slave --no-restore 2>&1)
    
    # Show output in debug mode
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$r_output"
    fi
    
    # Check if the output contains "success" or "already installed"
    if echo "$r_output" | grep -q -E "(success|already installed)"; then
        echo "✅"
        ((installed_count++))
        return 0
    else
        echo "❌"
        failed_packages+=("$package")
        return 1
    fi
}

# Try pak installation first, fall back to individual installation if needed
if ! install_packages_with_pak; then
    echo "Falling back to individual package installation..."
    installed_count=0  # Reset counter for individual installation
    
    # Install packages individually
    for package in "${packages[@]}"; do
        # Skip empty lines or lines with only whitespace
        [[ -z "${package// }" ]] && continue
        install_package_individual "$package"
    done
fi

# Install additional packages using pak where possible
echo
echo "📦 Installing additional packages ..."

# Install mcmcplots from CRAN archive using install.packages() (pak fails with this package)
echo -n "📦 Installing mcmcplots from CRAN archive with install.packages()... "
mcmcplots_command="
tryCatch({
    install.packages('https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz', 
                     repos = NULL, type = 'source', dependencies = TRUE, quiet = TRUE)
    if (require('mcmcplots', character.only = TRUE, quietly = TRUE)) {
        cat('SUCCESS\\n')
    } else {
        cat('FAILED TO LOAD\\n')
        quit(status = 1)
    }
}, error = function(e) {
    cat('ERROR:', conditionMessage(e), '\\n')
    quit(status = 1)
})
"

if [[ "$DEBUG_MODE" == "true" ]]; then
    if echo "$mcmcplots_command" | R --slave --no-restore; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("mcmcplots")
    fi
else
    if echo "$mcmcplots_command" | R --slave --no-restore >/dev/null 2>&1; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("mcmcplots")
    fi
fi

# Install httpgd from GitHub using pak
echo -n "🌐 Installing httpgd from GitHub with pak... "
httpgd_command="
library(pak)
tryCatch({
    pak::pkg_install('nx10/httpgd')
    cat('SUCCESS\\n')
}, error = function(e) {
    cat('ERROR:', conditionMessage(e), '\\n')
    quit(status = 1)
})
"

if [[ "$DEBUG_MODE" == "true" ]]; then
    if echo "$httpgd_command" | R --slave --no-restore; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("httpgd")
    fi
else
    if echo "$httpgd_command" | R --slave --no-restore >/dev/null 2>&1; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("httpgd")
    fi
fi

# Install colorout from GitHub using pak
echo -n "🎨 Installing colorout from GitHub with pak... "
colorout_command="
library(pak)
tryCatch({
    pak::pkg_install('jalvesaq/colorout')
    cat('SUCCESS\\n')
}, error = function(e) {
    cat('ERROR:', conditionMessage(e), '\\n')
    quit(status = 1)
})
"

if [[ "$DEBUG_MODE" == "true" ]]; then
    if echo "$colorout_command" | R --slave --no-restore; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("colorout")
    fi
else
    if echo "$colorout_command" | R --slave --no-restore >/dev/null 2>&1; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("colorout")
    fi
fi

# Final summary
end_time=$(date +%s)
total_duration=$((end_time - start_time))
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))
failed_count=${#failed_packages[@]}

echo
echo "=========================================="
echo "📊 R PACKAGE INSTALLATION SUMMARY (Phase 1)"
echo "=========================================="
echo "   ✅ Successfully installed: $installed_count packages"
echo "   ❌ Failed installations: $failed_count packages"
echo "   🕒 Total time: ${total_minutes}m ${total_seconds}s"
echo "   📅 End time: $(date)"
echo "   🔧 Method: pak with fallback to install.packages()"
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
fi