#!/bin/bash

# ===========================================================================
# BUILD METRICS SUMMARY GENERATOR
# ===========================================================================
# This script parses build metrics CSV files generated during Docker build
# and produces a comprehensive timing and size summary table.
#
# Usage: ./generate_build_metrics_summary.sh [container_id_or_name]
#
# If no container ID/name is provided, it will attempt to extract metrics
# from the most recently built base-container image.
# ===========================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Function to print section headers
print_header() {
    echo
    print_color "$BOLD$CYAN" "=========================================="
    print_color "$BOLD$CYAN" "$1"
    print_color "$BOLD$CYAN" "=========================================="
}

# Function to format duration in human-readable format
format_duration() {
    local seconds="$1"
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        local minutes=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${minutes}m ${secs}s"
    else
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        local secs=$((seconds % 60))
        echo "${hours}h ${minutes}m ${secs}s"
    fi
}

# Function to extract metrics from a container
extract_metrics() {
    local container="$1"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_color "$BLUE" "Extracting build metrics from container: $container"
    
    # Copy all metrics files from the container
    docker cp "$container:/tmp/build-metrics" "$temp_dir/" 2>/dev/null || {
        print_color "$RED" "❌ Failed to extract build metrics from container '$container'"
        print_color "$YELLOW" "   Make sure the container was built with the metrics-enabled Dockerfile"
        rm -rf "$temp_dir"
        return 1
    }
    
    local metrics_dir="$temp_dir/build-metrics"
    
    if [ ! -d "$metrics_dir" ]; then
        print_color "$RED" "❌ No build metrics found in container '$container'"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_header "BUILD METRICS SUMMARY"
    
    # Initialize totals
    local total_build_time=0
    local cumulative_time=0
    
    # Stage information arrays
    declare -a stage_names=()
    declare -a stage_durations=()
    declare -a stage_sizes_start=()
    declare -a stage_sizes_end=()
    declare -a stage_size_changes=()
    
    # Process each stage in order
    for stage_num in {1..11}; do
        local csv_file
        case $stage_num in
            1) csv_file="stage-1-base.csv" ;;
            2) csv_file="stage-2-base-nvim.csv" ;;
            3) csv_file="stage-3-base-nvim-vscode.csv" ;;
            4) csv_file="stage-4-base-nvim-vscode-tex.csv" ;;
            5) csv_file="stage-5-base-nvim-vscode-tex-pandoc.csv" ;;
            6) csv_file="stage-6-base-nvim-vscode-tex-pandoc-haskell.csv" ;;
            7) csv_file="stage-7-base-nvim-vscode-tex-pandoc-haskell-crossref.csv" ;;
            8) csv_file="stage-8-base-nvim-vscode-tex-pandoc-haskell-crossref-plus.csv" ;;
            9) csv_file="stage-9-base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r.csv" ;;
            10) csv_file="stage-10-base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py.csv" ;;
            11) csv_file="stage-11-full.csv" ;;
        esac
        
        local csv_path="$metrics_dir/$csv_file"
        if [ ! -f "$csv_path" ]; then
            continue
        fi
        
        # Parse CSV file
        local start_time end_time stage_name
        local start_line end_line
        
        start_line=$(grep ",start," "$csv_path" 2>/dev/null || echo "")
        end_line=$(grep ",end," "$csv_path" 2>/dev/null || echo "")
        
        if [ -z "$start_line" ] || [ -z "$end_line" ]; then
            continue
        fi
        
        start_time=$(echo "$start_line" | cut -d',' -f4)
        end_time=$(echo "$end_line" | cut -d',' -f4)
        stage_name=$(echo "$start_line" | cut -d',' -f2)
        
        if [ -n "$start_time" ] && [ -n "$end_time" ]; then
            local duration=$((end_time - start_time))
            total_build_time=$((total_build_time + duration))
            cumulative_time=$((cumulative_time + duration))
            
            # Get size information
            local size_start_file="stage-${stage_num}-size-start.txt"
            local size_end_file="stage-${stage_num}-size-end.txt"
            local size_start="N/A"
            local size_end="N/A"
            local size_change="N/A"
            
            if [ -f "$metrics_dir/$size_start_file" ] && [ -f "$metrics_dir/$size_end_file" ]; then
                size_start=$(cat "$metrics_dir/$size_start_file" 2>/dev/null || echo "N/A")
                size_end=$(cat "$metrics_dir/$size_end_file" 2>/dev/null || echo "N/A")
                
                if [ "$size_start" != "N/A" ] && [ "$size_end" != "N/A" ]; then
                    # Calculate size change (rough approximation)
                    size_change="+$(echo "$size_end" | sed 's/[^0-9.]//g')-$(echo "$size_start" | sed 's/[^0-9.]//g')" 2>/dev/null || size_change="N/A"
                fi
            fi
            
            # Store stage information
            stage_names+=("$stage_name")
            stage_durations+=("$duration")
            stage_sizes_start+=("$size_start")
            stage_sizes_end+=("$size_end")
            stage_size_changes+=("$size_change")
        fi
    done
    
    # Print summary table
    echo
    print_color "$BOLD" "Per-Stage Build Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-6s %-35s %-12s %-12s %-12s %-12s %-15s\\n" \
           "Stage" "Name" "Duration" "Cumulative" "Start Size" "End Size" "Size Change"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local cumulative_duration=0
    for i in "${!stage_names[@]}"; do
        local stage_num=$((i + 1))
        local stage_name="${stage_names[$i]}"
        local duration="${stage_durations[$i]}"
        local size_start="${stage_sizes_start[$i]}"
        local size_end="${stage_sizes_end[$i]}"
        local size_change="${stage_size_changes[$i]}"
        
        cumulative_duration=$((cumulative_duration + duration))
        
        local duration_formatted
        local cumulative_formatted
        duration_formatted=$(format_duration "$duration")
        cumulative_formatted=$(format_duration "$cumulative_duration")
        
        # Color code slow stages
        local color=""
        if [ "$duration" -gt 1800 ]; then  # > 30 minutes
            color="$RED"
        elif [ "$duration" -gt 600 ]; then  # > 10 minutes
            color="$YELLOW"
        else
            color="$GREEN"
        fi
        
        # Left-truncate stage name if longer than 32 characters
        local display_name="$stage_name"
        if [ ${#stage_name} -gt 32 ]; then
            display_name="...${stage_name: -29}"
        fi
        
        printf "${color}%-6s${NC} %-35s ${color}%-12s${NC} %-12s %-12s %-12s %-15s\\n" \
               "$stage_num" "$display_name" "$duration_formatted" "$cumulative_formatted" \
               "$size_start" "$size_end" "$size_change"
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Print totals
    echo
    print_color "$BOLD$GREEN" "Overall Build Statistics"
    print_color "$GREEN" "• Total Build Time: $(format_duration "$total_build_time")"
    print_color "$GREEN" "• Number of Stages: ${#stage_names[@]}"
    print_color "$GREEN" "• Average Stage Time: $(format_duration $((total_build_time / ${#stage_names[@]})))"
    
    # Find slowest stage
    local max_duration=0
    local slowest_stage=""
    for i in "${!stage_names[@]}"; do
        local duration="${stage_durations[$i]}"
        if [ "$duration" -gt "$max_duration" ]; then
            max_duration="$duration"
            slowest_stage="${stage_names[$i]}"
        fi
    done
    
    if [ "$max_duration" -gt 0 ]; then
        print_color "$YELLOW" "• Slowest Stage: $slowest_stage ($(format_duration "$max_duration"))"
    fi
    
    # Recommendations
    echo
    print_color "$BOLD$CYAN" "Build Optimization Recommendations"
    if [ "$max_duration" -gt 3600 ]; then
        print_color "$RED" "⚠️  Very long build detected (>1 hour total)"
        print_color "$YELLOW" "   Consider using Docker layer caching or multi-stage build optimizations"
    elif [ "$max_duration" -gt 1800 ]; then
        print_color "$YELLOW" "⚠️  Long build detected (>30 minutes for slowest stage)"
        print_color "$YELLOW" "   Consider optimizing the '$slowest_stage' stage"
    else
        print_color "$GREEN" "✅ Build time looks reasonable"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo
    print_color "$BOLD$BLUE" "Build metrics analysis complete!"
}

# Main execution
main() {
    local container="${1:-}"
    
    # If no container specified, try to find the most recent base-container
    if [ -z "$container" ]; then
        print_color "$BLUE" "No container specified, looking for most recent base-container image..."
        
        # Try to get the most recent base-container image
        container=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.CreatedAt}}" | \
                   grep "base-container" | \
                   head -1 | \
                   awk '{print $1}') || true
        
        if [ -z "$container" ]; then
            print_color "$RED" "❌ No base-container images found"
            print_color "$YELLOW" "Usage: $0 [container_id_or_name]"
            print_color "$YELLOW" "   or build a base-container image first"
            exit 1
        fi
        
        print_color "$GREEN" "Found container: $container"
    fi
    
    # Extract and display metrics
    extract_metrics "$container"
}

# Run main function with all arguments
main "$@"
