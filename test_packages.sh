#!/bin/bash
# Test script to install first few packages individually
set -e

packages=("abind" "AsioHeaders" "askpass" "backports" "base64enc")

for package in "${packages[@]}"; do
    echo "Testing installation of $package..."
    
    r_command="
    cat('Installing $package...\\n')
    install.packages('$package', repos='https://cloud.r-project.org/', dependencies=TRUE, quiet=FALSE)
    if (require('$package', character.only=TRUE, quietly=TRUE)) {
        cat('SUCCESS: $package installed\\n')
    } else {
        cat('FAILED: $package not available\\n')
        quit(status=1)
    }
    "
    
    if echo "$r_command" | R --slave --no-restore; then
        echo "✅ $package installed successfully"
    else
        echo "❌ $package failed to install"
        exit 1
    fi
done

echo "All test packages installed successfully!"
