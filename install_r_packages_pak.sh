#!/bin/bash
# install_r_packages_pak.sh - pak-based R package installer with BuildKit cache optimization
# Phase 2: Core pak implementation with architecture-segregated site libraries

set -euo pipefail

# Configuration
PACKAGES_FILE="/tmp/packages.txt"
DEBUG_MODE=false
R_VERSION=""
TARGETARCH=""

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

# Detect R version and architecture
detect_environment() {
    echo "🔍 Detecting R version and architecture..."
    
    # Get R major.minor version (e.g., "4.5" from "R version 4.5.1")
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9]\+\.[0-9]\+\).*/\1/')
    
    # Get target architecture from dpkg or uname
    if command -v dpkg >/dev/null 2>&1; then
        TARGETARCH=$(dpkg --print-architecture)
    else
        case "$(uname -m)" in
            x86_64) TARGETARCH="amd64" ;;
            aarch64|arm64) TARGETARCH="arm64" ;;
            *) echo "❌ Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
    fi
    
    echo "   R version: $R_VERSION"
    echo "   Architecture: $TARGETARCH"
    echo
}

# Setup site library with architecture segregation
setup_site_library() {
    local site_lib_base="/opt/R/site-library"
    local site_lib_arch="${site_lib_base}/${R_VERSION}-${TARGETARCH}"
    local site_lib_compat="/usr/local/lib/R/site-library"
    
    echo "📁 Setting up architecture-segregated site library..."
    echo "   Base path: $site_lib_base"
    echo "   Arch-specific: $site_lib_arch"
    echo "   Compatibility: $site_lib_compat"
    
    # Create architecture-specific directory
    mkdir -p "$site_lib_arch"
    
    # Create compatibility symlink if it doesn't exist
    if [[ ! -e "$site_lib_compat" ]]; then
        ln -sf "$site_lib_arch" "$site_lib_compat"
        echo "   ✅ Created compatibility symlink: $site_lib_compat -> $site_lib_arch"
    else
        echo "   ℹ️  Compatibility path already exists: $site_lib_compat"
    fi
    
    # Set R_LIBS_SITE environment variable
    export R_LIBS_SITE="$site_lib_arch"
    echo "   ✅ Set R_LIBS_SITE=$R_LIBS_SITE"
    echo
}

# Install and configure pak
install_pak() {
    echo "📦 Installing and configuring pak..."
    
    # Install pak from CRAN
    local pak_install_cmd='install.packages("pak", repos="https://cloud.r-project.org/", dependencies=TRUE, quiet=TRUE)'
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "   Installing pak with debug output..."
        echo "$pak_install_cmd" | R --slave --no-restore
    else
        echo "   Installing pak..."
        if ! echo "$pak_install_cmd" | R --slave --no-restore >/dev/null 2>&1; then
            echo "❌ Failed to install pak"
            exit 1
        fi
    fi
    
    # Configure pak settings
    local pak_config_cmd='
        library(pak)
        # Configure pak for optimal performance and caching
        pak::pak_config_set("dependencies" = TRUE)
        pak::pak_config_set("ask" = FALSE)
        # Enable parallel downloads and builds
        pak::pak_config_set("build_vignettes" = FALSE)
        cat("pak configured successfully\n")
    '
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "   Configuring pak with debug output..."
        echo "$pak_config_cmd" | R --slave --no-restore
    else
        echo "   Configuring pak..."
        if ! echo "$pak_config_cmd" | R --slave --no-restore >/dev/null 2>&1; then
            echo "❌ Failed to configure pak"
            exit 1
        fi
    fi
    
    echo "   ✅ pak installed and configured"
    echo
}

# Install CRAN packages using pak
install_cran_packages() {
    local packages_file="$1"
    
    if [[ ! -f "$packages_file" ]]; then
        echo "❌ Package file not found: $packages_file"
        exit 1
    fi
    
    # Count packages
    local total_packages
    total_packages=$(grep -c -v '^\s*$' "$packages_file" || echo "0")
    
    if [[ $total_packages -eq 0 ]]; then
        echo "ℹ️  No CRAN packages to install"
        return 0
    fi
    
    echo "📦 Installing $total_packages CRAN packages using pak..."
    echo "🕒 Start time: $(date)"
    
    local start_time
    start_time=$(date +%s)
    
    # Create R command to install packages
    local install_cmd='
        library(pak)
        packages <- readLines("'$packages_file'")
        packages <- packages[packages != "" & !grepl("^\\s*$", packages)]
        
        cat("Installing", length(packages), "packages...\n")
        
        tryCatch({
            pak::pkg_install(packages)
            cat("SUCCESS: All CRAN packages installed\n")
        }, error = function(e) {
            cat("ERROR:", conditionMessage(e), "\n")
            quit(status = 1)
        })
    '
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "   Installing with debug output..."
        echo "$install_cmd" | R --slave --no-restore
    else
        echo "   Installing packages..."
        if ! echo "$install_cmd" | R --slave --no-restore; then
            echo "❌ Failed to install CRAN packages"
            exit 1
        fi
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo "   ✅ CRAN packages installed in ${minutes}m ${seconds}s"
    echo
}

# Install special packages (GitHub, archive, etc.)
install_special_packages() {
    echo "📦 Installing special packages..."
    
    # Install mcmcplots from CRAN archive
    echo "   📦 Installing mcmcplots from CRAN archive..."
    local mcmcplots_cmd='
        library(pak)
        tryCatch({
            pak::pkg_install("https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz")
            cat("SUCCESS: mcmcplots installed\n")
        }, error = function(e) {
            cat("ERROR installing mcmcplots:", conditionMessage(e), "\n")
            quit(status = 1)
        })
    '
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$mcmcplots_cmd" | R --slave --no-restore
    else
        if ! echo "$mcmcplots_cmd" | R --slave --no-restore >/dev/null 2>&1; then
            echo "❌ Failed to install mcmcplots"
            exit 1
        fi
    fi
    echo "      ✅ mcmcplots installed"
    
    # Install httpgd from GitHub
    echo "   🌐 Installing httpgd from GitHub..."
    local httpgd_cmd='
        library(pak)
        tryCatch({
            pak::pkg_install("nx10/httpgd")
            cat("SUCCESS: httpgd installed\n")
        }, error = function(e) {
            cat("ERROR installing httpgd:", conditionMessage(e), "\n")
            quit(status = 1)
        })
    '
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$httpgd_cmd" | R --slave --no-restore
    else
        if ! echo "$httpgd_cmd" | R --slave --no-restore >/dev/null 2>&1; then
            echo "❌ Failed to install httpgd"
            exit 1
        fi
    fi
    echo "      ✅ httpgd installed"
    
    # Install colorout from GitHub
    echo "   🎨 Installing colorout from GitHub..."
    local colorout_cmd='
        library(pak)
        tryCatch({
            pak::pkg_install("jalvesaq/colorout")
            cat("SUCCESS: colorout installed\n")
        }, error = function(e) {
            cat("ERROR installing colorout:", conditionMessage(e), "\n")
            quit(status = 1)
        })
    '
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$colorout_cmd" | R --slave --no-restore
    else
        if ! echo "$colorout_cmd" | R --slave --no-restore >/dev/null 2>&1; then
            echo "❌ Failed to install colorout"
            exit 1
        fi
    fi
    echo "      ✅ colorout installed"
    
    echo "   ✅ All special packages installed"
    echo
}

# Verify installation
verify_installation() {
    echo "🔍 Verifying package installation..."
    
    local verify_cmd='
        # Get list of installed packages
        installed <- installed.packages()[,"Package"]
        cat("Total packages installed:", length(installed), "\n")
        
        # Check specific packages
        test_packages <- c("pak", "dplyr", "ggplot2", "httpgd", "colorout", "mcmcplots")
        
        for (pkg in test_packages) {
            if (pkg %in% installed) {
                cat("✅", pkg, "\n")
            } else {
                cat("❌", pkg, "(not found)\n")
            }
        }
        
        # Show library paths
        cat("\nLibrary paths:\n")
        for (path in .libPaths()) {
            cat("  ", path, "\n")
        }
    '
    
    echo "$verify_cmd" | R --slave --no-restore
    echo
}

# Main execution
main() {
    echo "==========================================="
    echo "🚀 PAK-BASED R PACKAGE INSTALLER (Phase 2)"
    echo "==========================================="
    echo "🕒 Start time: $(date)"
    echo
    
    local overall_start
    overall_start=$(date +%s)
    
    # Setup environment
    detect_environment
    setup_site_library
    
    # Install pak
    install_pak
    
    # Install packages
    install_cran_packages "$PACKAGES_FILE"
    install_special_packages
    
    # Verify installation
    verify_installation
    
    # Final summary
    local overall_end
    overall_end=$(date +%s)
    local total_duration=$((overall_end - overall_start))
    local total_minutes=$((total_duration / 60))
    local total_seconds=$((total_duration % 60))
    
    echo "==========================================="
    echo "🎉 PAK INSTALLATION COMPLETED SUCCESSFULLY"
    echo "==========================================="
    echo "   🕒 Total time: ${total_minutes}m ${total_seconds}s"
    echo "   📅 End time: $(date)"
    echo "   📁 Site library: $R_LIBS_SITE"
    echo "   🏗️  Architecture: ${R_VERSION}-${TARGETARCH}"
    echo
}

# Run main function
main "$@"