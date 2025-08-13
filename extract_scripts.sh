#!/bin/bash
# This script extracts shell code from RUN blocks in a Dockerfile that are
# preceded by the comment "# shellcheck-check"

set -e

if [ ! -f "$1" ]; then
    echo "Usage: $0 <Dockerfile>" >&2
    exit 1
fi

# Use awk to find the marker, then print all lines of the next RUN command.
awk \
    'BEGIN { found=0; } 
    /^# shellcheck-check/ { found=1; next; } 
    found && /^RUN/ { 
        # Start of a marked RUN block
        sub(/^RUN[[:space:]]*/, ""); # Remove the RUN instruction itself
        # Handle multi-line and single-line RUN commands
        if (/\\$/) { 
            sub(/\\$/, ""); # Remove trailing backslash for the current line
            print; 
            while (getline > 0) { 
                if (/\\$/) { 
                    sub(/\\$/, ""); # Remove trailing backslash
                    print; 
                } else { 
                    print; 
                    break; 
                } 
            } 
        } else { 
            print; 
        } 
        found=0; # Reset the flag
    }' "$1"
