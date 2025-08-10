# Docker Build Metrics

This document explains how to use the comprehensive build metrics tracking system that has been integrated into the multi-stage Dockerfile.

## Overview

The Dockerfile now includes comprehensive build metrics tracking for all 11 stages:

1. **Stage 1 (base)**: Ubuntu system with R
2. **Stage 2 (base-nvim)**: Neovim plugin initialization
3. **Stage 3 (base-nvim-vscode)**: VS Code server and extensions
4. **Stage 4 (base-nvim-vscode-tex)**: LaTeX typesetting support
5. **Stage 5 (base-nvim-vscode-tex-pandoc)**: Pandoc installation
6. **Stage 6 (base-nvim-vscode-tex-pandoc-haskell)**: Haskell Stack installation
7. **Stage 7 (base-nvim-vscode-tex-pandoc-haskell-crossref)**: pandoc-crossref installation
8. **Stage 8 (base-nvim-vscode-tex-pandoc-haskell-crossref-plus)**: Additional LaTeX packages
9. **Stage 9 (base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r)**: R package installation
10. **Stage 10 (base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py)**: Python 3.13 installation
11. **Stage 11 (full)**: Final environment setup

## Metrics Collected

For each stage, the following metrics are automatically collected:

- **Start/End Timestamps**: Precise timing of when each stage begins and completes
- **Build Duration**: Time taken for each individual stage
- **Filesystem Size**: Disk usage before and after each stage
- **Size Changes**: How much each stage adds to the image size

## How It Works

### During Build

Each stage includes metrics collection commands that:

1. **At Stage Start**: Record timestamp and initial filesystem size
2. **At Stage End**: Record completion timestamp and final filesystem size
3. **Store Data**: Save timing data to CSV files and size data to text files in `/tmp/build-metrics/`

### Metrics Files Generated

The build process creates the following files inside the container:

```
/tmp/build-metrics/
├── stage-1-base.csv                    # Stage 1 timing data
├── stage-1-size-start.txt              # Stage 1 initial size
├── stage-1-size-end.txt                # Stage 1 final size
├── stage-2-base-nvim.csv               # Stage 2 timing data
├── stage-2-size-start.txt              # Stage 2 initial size
├── stage-2-size-end.txt                # Stage 2 final size
├── ... (and so on for all 11 stages)
└── stage-11-full.csv                   # Final stage timing data
```

## Viewing Build Metrics

### Automatic Summary Generation

Use the provided script to generate a comprehensive build metrics report:

```bash
# Generate report for most recent base-container image
./generate_build_metrics_summary.sh

# Generate report for specific container
./generate_build_metrics_summary.sh base-container:latest

# Generate report for container ID
./generate_build_metrics_summary.sh abc123def456
```

### Sample Output

The script produces a detailed table showing:

```
==========================================
BUILD METRICS SUMMARY
==========================================

Per-Stage Build Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Stage  Name                             Duration     Cumulative   Start Size   End Size     Size Change    
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1      base                             8m 23s       8m 23s       1.2G         2.8G         +1.6G         
2      base-nvim                        2m 15s       10m 38s      2.8G         2.9G         +0.1G         
3      base-nvim-vscode                 5m 42s       16m 20s      2.9G         3.2G         +0.3G         
4      base-nvim-vscode-tex             12m 8s       28m 28s      3.2G         5.1G         +1.9G         
5      base-nvim-vscode-tex-pandoc      1m 33s       30m 1s       5.1G         5.2G         +0.1G         
6      ...tex-pandoc-haskell             3m 45s       33m 46s      5.2G         5.4G         +0.2G         
7      ...doc-haskell-crossref          7m 12s       40m 58s      5.4G         5.4G         +0.0G         
8      ...askell-crossref-plus          2m 5s        43m 3s       5.4G         5.5G         +0.1G         
9      ...ell-crossref-plus-r           45m 12s      1h 28m 15s   5.5G         6.8G         +1.3G         
10     ...crossref-plus-r-py            2m 18s       1h 30m 33s   6.8G         6.9G         +0.1G         
11     full                            0m 45s       1h 31m 18s   6.9G         6.9G         +0.0G         
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall Build Statistics
• Total Build Time: 1h 31m 18s
• Number of Stages: 11
• Average Stage Time: 8m 18s
• Slowest Stage: base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r (45m 12s)

Build Optimization Recommendations
⚠️  Long build detected (>30 minutes for slowest stage)
   Consider optimizing the '...ell-crossref-plus-r' stage

Build metrics analysis complete!
```

### Performance Analysis

The script analyzes stage performance and provides recommendations:

- Stages under 10 minutes are considered optimal
- Stages taking 10-30 minutes may benefit from optimization
- Stages over 30 minutes should be prioritized for improvement

## Manual Metrics Extraction

If you prefer to manually examine the metrics data:

```bash
# Start a container from your built image
docker run -it --rm base-container:latest bash

# View timing data for a specific stage
cat /tmp/build-metrics/stage-1-base.csv

# View size data
cat /tmp/build-metrics/stage-1-size-start.txt
cat /tmp/build-metrics/stage-1-size-end.txt

# Copy metrics out of container
docker cp container_id:/tmp/build-metrics ./metrics/
```

## CSV Format

The timing CSV files use this format:
```
timestamp,stage_name,event_type,unix_epoch
2024-01-15 10:30:45 UTC,base,start,1705314645
2024-01-15 10:39:08 UTC,base,end,1705315148
```

## Use Cases

### Build Optimization

- Identify which stages take the longest to build
- Track the impact of optimizations over time
- Compare build times across different architectures

### Infrastructure Planning

- Estimate CI/CD pipeline duration
- Plan resource allocation for build environments
- Set appropriate timeout values

### Documentation and Reporting

- Include build metrics in release notes
- Track technical debt related to build complexity
- Provide visibility into infrastructure costs

## Troubleshooting

### Missing Metrics

If metrics are not generated, ensure:

1. The build completed successfully through your target stage
2. The container has the `/tmp/build-metrics/` directory
3. You're using the updated Dockerfile with metrics tracking

### Script Permissions

Make the summary script executable:
```bash
chmod +x generate_build_metrics_summary.sh
```

### Container Not Found

The script may not find your container if:
- No images with "base-container" in the name exist
- The image was built with a different tag
- The container was removed

Specify the exact container name/ID:
```bash
./generate_build_metrics_summary.sh your-image:your-tag
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Build with Metrics
  run: docker build -t base-container:${{ github.sha }} .

- name: Generate Build Metrics
  run: |
    ./generate_build_metrics_summary.sh base-container:${{ github.sha }} > build-metrics.txt
    cat build-metrics.txt

- name: Upload Metrics as Artifact
  uses: actions/upload-artifact@v3
  with:
    name: build-metrics
    path: build-metrics.txt
```

### Monitoring Integration

The CSV format makes it easy to integrate with monitoring systems:

```bash
# Parse timing data for monitoring
docker cp container:/tmp/build-metrics/stage-9-*.csv metrics.csv
# Send to monitoring system (Prometheus, DataDog, etc.)
```

## Advanced Usage

### Custom Metrics Collection

Add your own metrics collection in the Dockerfile:

```dockerfile
RUN echo "custom-metric,$(date +%s),$(custom-command)" >> /tmp/build-metrics/custom.csv
```

### Historical Tracking

Compare metrics across builds:

```bash
# Save metrics with timestamp
./generate_build_metrics_summary.sh > "metrics-$(date +%Y%m%d-%H%M%S).txt"

# Compare with previous build
diff metrics-20240115-103000.txt metrics-20240115-140000.txt
```

This comprehensive metrics system provides complete visibility into your Docker build performance, helping you optimize build times and track changes over time.
