#!/bin/bash
# install_r_packages.sh - R package installer with failed package reporting

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

echo "📦 Installing $total_packages R packages..."
echo "🕒 Start time: $(date)"
echo

start_time=$(date +%s)
installed_count=0
failed_packages=()

# Function to install a single package
install_package() {
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
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        # Show full R output in debug mode
        if echo "$r_command" | R --slave --no-restore; then
            echo "✅"
            ((installed_count++))
            return 0
        else
            echo "❌"
            failed_packages+=("$package")
            return 1
        fi
    else
        # Suppress R output in normal mode
        if echo "$r_command" | R --slave --no-restore >/dev/null 2>&1; then
            echo "✅"
            ((installed_count++))
            return 0
        else
            echo "❌"
            failed_packages+=("$package")
            return 1
        fi
    fi
}

# Install packages from the main list
for package in "${packages[@]}"; do
    # Skip empty lines or lines with only whitespace
    [[ -z "${package// }" ]] && continue
    install_package "$package"
done

# Install additional packages
echo
echo "📦 Installing additional packages ..."

# Install mcmcplots from CRAN archive
echo -n "📦 Installing mcmcplots from CRAN archive... "
mcmcplots_command="install.packages('https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz', repos=NULL, type='source', dependencies=TRUE, quiet=TRUE)"

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

# Install colorout from GitHub
echo -n "🎨 Installing colorout from GitHub... "

# Get latest release info from GitHub API
RELEASE_INFO=$(curl -s https://api.github.com/repos/jalvesaq/colorout/releases/latest)
COLOROUT_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
COLOROUT_ASSET_NAME=$(echo "$RELEASE_INFO" | grep '"name":.*\.tar\.gz"' | sed -E 's/.*"([^"]+)".*/\1/')
COLOROUT_SHA256=$(echo "$RELEASE_INFO" | grep '"digest":.*sha256:' | sed -E 's/.*sha256:([a-f0-9]+)".*/\1/')

if [[ -z "$COLOROUT_VERSION" || -z "$COLOROUT_ASSET_NAME" || -z "$COLOROUT_SHA256" ]]; then
    echo "❌ Failed to get colorout release information"
    failed_packages+=("colorout")
else
    # Construct download URL
    COLOROUT_URL="https://github.com/jalvesaq/colorout/releases/download/${COLOROUT_VERSION}/${COLOROUT_ASSET_NAME}"
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo
        echo "  Version: $COLOROUT_VERSION"
        echo "  Asset: $COLOROUT_ASSET_NAME"
        echo "  SHA256: $COLOROUT_SHA256"
        echo "  URL: $COLOROUT_URL"
        echo -n "  Downloading and verifying... "
    fi
    
    # Download the package
    if curl -fsSL "$COLOROUT_URL" -o "/tmp/$COLOROUT_ASSET_NAME"; then
        # Verify SHA256 checksum
        DOWNLOADED_SHA256=$(sha256sum "/tmp/$COLOROUT_ASSET_NAME" | cut -d' ' -f1)
        if [[ "$DOWNLOADED_SHA256" == "$COLOROUT_SHA256" ]]; then
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo "✅ SHA256 verified"
                echo -n "  Installing R package... "
            fi
            
            # Install the package from the downloaded tarball
            colorout_command="install.packages('/tmp/$COLOROUT_ASSET_NAME', repos=NULL, type='source', dependencies=TRUE, quiet=TRUE)"
            
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
            
            # Clean up downloaded file
            rm -f "/tmp/$COLOROUT_ASSET_NAME"
        else
            echo "❌ SHA256 verification failed"
            echo "  Expected: $COLOROUT_SHA256"
            echo "  Got:      $DOWNLOADED_SHA256"
            failed_packages+=("colorout")
            rm -f "/tmp/$COLOROUT_ASSET_NAME"
        fi
    else
        echo "❌ Failed to download colorout"
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
echo "📊 R PACKAGE INSTALLATION SUMMARY"
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
fi
