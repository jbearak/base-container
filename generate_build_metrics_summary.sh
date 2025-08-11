#!/bin/bash

# ===========================================================================
# BUILD METRICS SUMMARY GENERATOR
# ===========================================================================
# This script parses build metrics CSV files generated during Docker build
# and produces a comprehensive timing and size summary table.
#
# Usage:
#   ./generate_build_metrics_summary.sh [--metadata build/build_metadata.json] [image_or_container]
#
# If no argument is provided, it will attempt to use the most recent
# base-container image.
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

# Bytes to human readable
format_size() {
    local bytes="$1"
    awk -v b="$bytes" '
      function human(x){
        split("B K M G T P", u, " ")
        i=1
        while (x>=1024 && i<6){ x/=1024; i++ }
        if (x>=100) printf("%.0f%s\n", x, u[i]);
        else if (x>=10) printf("%.1f%s\n", x, u[i]);
        else printf("%.2f%s\n", x, u[i]);
      } BEGIN { human(b) }'
}

# Function to format duration in human-readable format
format_duration() {
    local seconds="$1"
    if [ -z "$seconds" ] || ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
        echo "-"
        return
    fi
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

# Extract metrics from a container ID; caller ensures a container exists
extract_metrics_from_container() {
    local container_id="$1"
    local temp_dir
    temp_dir=$(mktemp -d)

    print_color "$BLUE" "Extracting build metrics from container: $container_id"

    if ! docker cp "$container_id:/tmp/build-metrics" "$temp_dir/" >/dev/null 2>&1; then
        print_color "$YELLOW" "No /tmp/build-metrics found in container."
        rm -rf "$temp_dir"
        return 1
    fi

    local metrics_dir="$temp_dir/build-metrics"
    if [ ! -d "$metrics_dir" ]; then
        print_color "$YELLOW" "No metrics directory extracted."
        rm -rf "$temp_dir"
        return 1
    fi

    print_header "BUILD METRICS SUMMARY"

    # Initialize totals
    local total_build_time=0
    
    # Stage information arrays
    declare -a stage_names=()
    declare -a stage_durations=()
    declare -a stage_sizes_start=()
    declare -a stage_sizes_end=()
    declare -a stage_size_changes=()

    # Discover stages by CSV files and sort numerically by stage number
    IFS=$'\n'
    for csv_path in $(find "$metrics_dir" -maxdepth 1 -type f -name 'stage-*-*.csv' \
                      | sed -E 's#.*/stage-([0-9]+)-.*#\1 & #' \
                      | sort -n \
                      | awk '{print $2}'); do
        local base
        base="$(basename "$csv_path")" # stage-N-name.csv
        local stage_num
        stage_num="$(echo "$base" | sed -E 's/^stage-([0-9]+)-.*/\1/')"
        local stage_name
        stage_name="$(echo "$base" | sed -E 's/^stage-[0-9]+-(.*)\.csv/\1/')"

        local start_time end_time
        start_time=$(grep ',start,' "$csv_path" | awk -F',' 'END{print $NF}')
        end_time=$(grep ',end,' "$csv_path" | awk -F',' 'END{print $NF}')
        if [ -z "$start_time" ] || [ -z "$end_time" ]; then
            continue
        fi
        local duration=$(( end_time - start_time ))
        total_build_time=$(( total_build_time + duration ))

        local start_file end_file start_bytes end_bytes change_bytes
        start_file="$metrics_dir/stage-${stage_num}-size-start.txt"
        end_file="$metrics_dir/stage-${stage_num}-size-end.txt"
        if [ -s "$start_file" ]; then start_bytes="$(tr -dc '0-9' < "$start_file")"; else start_bytes=""; fi
        if [ -s "$end_file" ]; then end_bytes="$(tr -dc '0-9' < "$end_file")"; else end_bytes=""; fi
        if [ -n "$start_bytes" ] && [ -n "$end_bytes" ]; then
            change_bytes=$(( end_bytes - start_bytes ))
        else
            change_bytes=""
        fi

        stage_names+=("$stage_name")
        stage_durations+=("$duration")
        stage_sizes_start+=("${start_bytes:-}")
        stage_sizes_end+=("${end_bytes:-}")
        stage_size_changes+=("${change_bytes:-}")
    done
    unset IFS

    echo
    print_color "$BOLD" "Per-Stage Build Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-6s %-35s %-12s %-12s %-12s %-12s %-15s\n" \
           "Stage" "Name" "Duration" "Cumulative" "Start Size" "End Size" "Size Change"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local cumulative_duration=0
    local slowest_stage=""
    local slowest_seconds=0

    for i in "${!stage_names[@]}"; do
        local stage_num=$((i + 1))
        local sname="${stage_names[$i]}"
        local dur="${stage_durations[$i]}"
        local sb="${stage_sizes_start[$i]}"
        local eb="${stage_sizes_end[$i]}"
        local cb="${stage_size_changes[$i]}"

        cumulative_duration=$((cumulative_duration + dur))
        [ "$dur" -gt "$slowest_seconds" ] && slowest_seconds="$dur" && slowest_stage="$sname"

        local color
        if [ "$dur" -gt 1800 ]; then color="$RED"; elif [ "$dur" -gt 600 ]; then color="$YELLOW"; else color="$GREEN"; fi

        local display_name="$sname"
        if [ ${#display_name} -gt 32 ]; then display_name="...${display_name: -29}"; fi

        printf "${color}%-6s${NC} %-35s ${color}%-12s${NC} %-12s %-12s %-12s %-15s\n" \
               "$stage_num" "$display_name" "$(format_duration "$dur")" "$(format_duration "$cumulative_duration")" \
               "$( [ -n "$sb" ] && format_size "$sb" || echo - )" \
               "$( [ -n "$eb" ] && format_size "$eb" || echo - )" \
               "$( [ -n "$cb" ] && printf "+%s" "$(format_size "$cb")" || echo - )"
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo
    print_color "$BOLD$GREEN" "Overall Build Statistics"
    print_color "$GREEN" "• Total Build Time: $(format_duration "$total_build_time")"
    print_color "$GREEN" "• Number of Stages: ${#stage_names[@]}"
    if [ ${#stage_names[@]} -gt 0 ]; then
      print_color "$GREEN" "• Average Stage Time: $(format_duration $(( total_build_time / ${#stage_names[@]} )))"
    fi
    if [ "$slowest_seconds" -gt 0 ]; then
      print_color "$YELLOW" "• Slowest Stage: $slowest_stage ($(format_duration "$slowest_seconds"))"
    fi

    echo
    print_color "$BOLD$CYAN" "Build Optimization Recommendations"
    if [ "$slowest_seconds" -gt 3600 ]; then
      print_color "$RED" "⚠️  Very long build detected (>1 hour stage)"
    elif [ "$slowest_seconds" -gt 1800 ]; then
      print_color "$YELLOW" "⚠️  Long build detected (>30 minutes for slowest stage)"
      print_color "$YELLOW" "   Consider optimizing the '$slowest_stage' stage"
    else
      print_color "$GREEN" "✅ Build time looks reasonable"
    fi

    rm -rf "$temp_dir"

    echo
    print_color "$BOLD$BLUE" "Build metrics analysis complete!"
}

print_image_sizes_and_history() {
    local image_ref="$1"
    local metadata_file="${2:-}"

    print_header "IMAGE SIZE SUMMARY"

    if [ -n "$metadata_file" ] && command -v jq >/dev/null 2>&1 && [ -s "$metadata_file" ]; then
        local compressed_bytes
        compressed_bytes=$(jq -r '."containerimage.descriptor".size // empty' "$metadata_file" || true)
        if [ -n "$compressed_bytes" ] && [ "$compressed_bytes" != "null" ]; then
            echo "Compressed (push) size: $(format_size "$compressed_bytes")"
        else
            echo "Compressed (push) size: unavailable (no descriptor in metadata)"
        fi
    else
        echo "Compressed (push) size: (provide --metadata path to BuildKit metadata to show)"
    fi

    local uncompressed_bytes
    uncompressed_bytes=$(docker image inspect "$image_ref" --format '{{.Size}}' 2>/dev/null || true)
    if [ -n "$uncompressed_bytes" ]; then
        echo "Uncompressed (local) size: $(format_size "$uncompressed_bytes")"
    else
        echo "Uncompressed (local) size: unavailable"
    fi

    if docker history --no-trunc "$image_ref" >/dev/null 2>&1; then
        echo
        print_color "$BOLD" "Layer history (most recent first)"
        docker history --no-trunc "$image_ref" | sed -n '1,15p'
    fi
}

# Main execution
main() {
    local metadata_file=""
    local arg=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata)
          metadata_file="$2"; shift 2 ;;
        *)
          arg="$1"; shift ;;
      esac
    done

    local image_or_container="$arg"

    if [ -z "$image_or_container" ]; then
        print_color "$BLUE" "No image/container specified, selecting a 'base-container' image..."
        # Collect candidate tags, excluding <none>
        local candidates
        candidates=($(docker images --format '{{.Repository}}:{{.Tag}}' \
            | grep '^base-container:' \
            | grep -v ':<none>$' || true))
        if [ ${#candidates[@]} -eq 0 ]; then
            print_color "$RED" "❌ No base-container images found"
            print_color "$YELLOW" "Usage: $0 [--metadata file.json] [image_or_container]"
            exit 1
        fi
        # Prefer explicit tags when available
        for preferred in "base-container:full" "base-container:latest"; do
            for c in "${candidates[@]}"; do
                if [ "$c" = "$preferred" ]; then
                    image_or_container="$c"
                    break 2
                fi
            done
        done
        # Fallback to the first candidate
        if [ -z "$image_or_container" ]; then
            image_or_container="${candidates[0]}"
        fi
        print_color "$GREEN" "Using image: $image_or_container"
    fi

    # Determine if the argument is a container or an image
    local container_id=""
    if docker container inspect "$image_or_container" >/dev/null 2>&1; then
        container_id="$image_or_container"
    else
        # Treat as image, create a temporary container
        if ! docker image inspect "$image_or_container" >/dev/null 2>&1; then
            print_color "$RED" "❌ Not a valid container or image: $image_or_container"
            exit 1
        fi
        container_id=$(docker create "$image_or_container")
    fi

    # Ensure container gets removed after use if we created it
    local created_temp=false
    if ! docker ps -a --format '{{.ID}}' | grep -q "^${container_id}$"; then
        # Unexpected, but continue without cleanup flag
        created_temp=false
    else
        # We don't know if it pre-existed; best effort: mark as created if the name isn't in 'docker ps -a --format {{.Names}}'
        created_temp=true
    fi

    # Print sizes/history based on the image reference (resolve from container if needed)
    local image_ref
    image_ref=$(docker inspect --format='{{.Image}}' "$container_id" 2>/dev/null || echo "")
    # If that failed (rare), fall back to arg
    [ -z "$image_ref" ] && image_ref="$image_or_container"

    print_image_sizes_and_history "$image_ref" "$metadata_file"

    # Extract and display metrics
    extract_metrics_from_container "$container_id" || true

    # Cleanup temporary container if we created one (best effort)
    # We can't perfectly detect pre-existence without more bookkeeping; remove safely if it's not running
    docker rm -v "$container_id" >/dev/null 2>&1 || true
}

# Run main function with all arguments
main "$@"
