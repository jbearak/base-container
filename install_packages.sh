#!/bin/bash
# install_packages.sh - Sequential R package installer with time tracking
# Note: Removed 'set -e' to handle individual package failures gracefully

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
failed_count=0

for package in "${packages[@]}"; do
    # Skip empty lines or lines with only whitespace
    [[ -z "${package// }" ]] && continue
    
    echo -n "📦 Installing $package... "
    package_start=$(date +%s)
    
    # Prepare R command
    r_command="if (require('$package', character.only=TRUE, quietly=TRUE)) { 
        cat('already installed\\n') 
    } else { 
        install.packages('$package', repos='https://cloud.r-project.org/', dependencies=TRUE, quiet=TRUE)
        if (require('$package', character.only=TRUE, quietly=TRUE)) {
            cat('success\\n')
        } else {
            cat('failed\\n')
        }
    }"
    
    # Run R installation
    if [[ "$DEBUG_MODE" == "true" ]]; then
        # Show full R output in debug mode
        if echo "$r_command" | R --slave --no-restore; then
            status="✅"
            ((installed_count++))
        else
            status="❌"
            ((failed_count++))
        fi
    else
        # Suppress R output in normal mode
        if echo "$r_command" | R --slave --no-restore >/dev/null 2>&1; then
            status="✅"
            ((installed_count++))
        else
            status="❌"
            ((failed_count++))
        fi
    fi
    
    package_end=$(date +%s)
    package_duration=$((package_end - package_start))
    
    echo "$status (${package_duration}s)"
done

# Install colorout from r-multiverse
echo
echo -n "🎨 Installing colorout from r-multiverse... "
colorout_start=$(date +%s)

colorout_command="install.packages('colorout', repos='https://community.r-multiverse.org', dependencies=TRUE, quiet=TRUE)"

if [[ "$DEBUG_MODE" == "true" ]]; then
    if echo "$colorout_command" | R --slave --no-restore; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        ((failed_count++))
    fi
else
    if echo "$colorout_command" | R --slave --no-restore >/dev/null 2>&1; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        ((failed_count++))
    fi
fi

colorout_end=$(date +%s)
colorout_duration=$((colorout_end - colorout_start))
echo "(${colorout_duration}s)"

# Final summary
end_time=$(date +%s)
total_duration=$((end_time - start_time))
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))

echo
echo "📊 Installation Summary:"
echo "   ✅ Successfully installed: $installed_count packages"
echo "   ❌ Failed installations: $failed_count packages"
echo "   🕒 Total time: ${total_minutes}m ${total_seconds}s"
echo "   📅 End time: $(date)"

if [[ $failed_count -gt 0 ]]; then
    echo "⚠️  Some packages failed to install. Check logs above for details."
    exit 1
fi

echo "🎉 All packages installed successfully!"
