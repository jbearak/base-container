# Cache Optimization Guide

This guide provides advanced strategies for optimizing BuildKit cache performance in the pak-based R package installation system.

## Overview

The pak-based system uses multiple cache layers to achieve 50%+ build time reduction:

1. **BuildKit Registry Cache**: Shared cache across builds and environments
2. **pak Package Cache**: R package download and metadata cache
3. **Compilation Cache**: Compiled package binaries cache
4. **Download Cache**: Raw package download cache

## Cache Architecture

### Cache Mount Structure

```dockerfile
# pak cache - package metadata and downloads
--mount=type=cache,target=/root/.cache/R/pak

# Compilation cache - compiled binaries
--mount=type=cache,target=/tmp/R-compile

# Download cache - raw package files
--mount=type=cache,target=/tmp/R-downloads
```

### Cache Hierarchy

```
BuildKit Registry Cache (ghcr.io/user/repo/cache:*)
├── Base System Cache (Ubuntu, R installation)
├── pak Installation Cache
└── R Package Installation Cache
    ├── pak Package Cache (/root/.cache/R/pak)
    ├── Compilation Cache (/tmp/R-compile)
    └── Download Cache (/tmp/R-downloads)
```

## Optimization Strategies

### 1. Registry Cache Optimization

#### Pre-warming Strategy

```bash
# Pre-warm all caches in CI/CD pipeline
./cache-helper.sh warm-all

# Pre-warm specific target
./cache-helper.sh warm pak-full

# Pre-warm with specific registry
./cache-helper.sh --registry ghcr.io/myorg/myrepo warm-all
```

#### Cache Key Optimization

```bash
# Use consistent cache keys across builds
export CACHE_REGISTRY="ghcr.io/jbearak/base-container"

# Build with registry cache
./build-pak-container.sh --cache-from-to "$CACHE_REGISTRY"

# Verify cache usage
docker buildx build --progress=plain --cache-from "type=registry,ref=$CACHE_REGISTRY/cache:pak-full" .
```

### 2. pak Cache Optimization

#### Cache Configuration

```r
# Optimize pak cache settings
pak::pak_config_set("cache_dir", "/root/.cache/R/pak")
pak::pak_config_set("metadata_cache_dir", "/root/.cache/R/pak/metadata")
pak::pak_config_set("package_cache_dir", "/root/.cache/R/pak/packages")
```

#### Cache Verification

```bash
# Check pak cache status
docker run --rm base-container:pak R -e 'pak::cache_summary()'

# Verify cache directory structure
docker run --rm base-container:pak find /root/.cache/R/pak -type f | head -20

# Check cache size
docker run --rm base-container:pak du -sh /root/.cache/R/pak
```

### 3. Build Layer Optimization

#### Layer Ordering Strategy

Optimize Dockerfile layer ordering for maximum cache reuse:

```dockerfile
# 1. System dependencies (rarely change)
RUN apt-get update && apt-get install -y ...

# 2. R installation (stable)
RUN install R...

# 3. pak installation (stable)
RUN R -e 'install.packages("pak")'

# 4. System R packages (stable)
COPY R_packages.txt /tmp/
RUN --mount=type=cache,target=/root/.cache/R/pak \
    R -e 'pak::pkg_install(readLines("/tmp/R_packages.txt"))'

# 5. Special packages (may change more frequently)
RUN --mount=type=cache,target=/root/.cache/R/pak \
    R -e 'pak::pkg_install("nx10/httpgd")'
```

#### Cache Mount Optimization

```dockerfile
# Combine cache mounts for better efficiency
RUN --mount=type=cache,target=/root/.cache/R/pak \
    --mount=type=cache,target=/tmp/R-compile \
    --mount=type=cache,target=/tmp/R-downloads \
    R -e 'pak::pkg_install(readLines("R_packages.txt"))'
```

### 4. Multi-Architecture Cache Strategy

#### Architecture-Specific Caching

```bash
# Build for specific architecture with cache
docker buildx build \
  --platform linux/amd64 \
  --cache-from "type=registry,ref=ghcr.io/user/repo/cache:pak-amd64" \
  --cache-to "type=registry,ref=ghcr.io/user/repo/cache:pak-amd64" \
  --file Dockerfile.pak .

# Build for ARM64 with separate cache
docker buildx build \
  --platform linux/arm64 \
  --cache-from "type=registry,ref=ghcr.io/user/repo/cache:pak-arm64" \
  --cache-to "type=registry,ref=ghcr.io/user/repo/cache:pak-arm64" \
  --file Dockerfile.pak .
```

#### Cross-Platform Cache Sharing

```bash
# Build multi-arch with shared cache
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --cache-from "type=registry,ref=ghcr.io/user/repo/cache:pak-multi" \
  --cache-to "type=registry,ref=ghcr.io/user/repo/cache:pak-multi" \
  --file Dockerfile.pak .
```

## Performance Monitoring

### Cache Hit Rate Analysis

```bash
# Build with detailed progress
docker buildx build --progress=plain --file Dockerfile.pak . 2>&1 | tee build.log

# Analyze cache hits
grep -i "cache" build.log | grep -E "(HIT|MISS)"

# Count cache hits vs misses
echo "Cache Hits: $(grep -c "CACHED" build.log)"
echo "Cache Misses: $(grep -c "RUN" build.log | grep -v "CACHED")"
```

### Build Time Measurement

```bash
# Measure build time with cache
time docker buildx build --file Dockerfile.pak --target pak-full .

# Measure build time without cache
time docker buildx build --no-cache --file Dockerfile.pak --target pak-full .

# Calculate cache effectiveness
# Cache Effectiveness = (Cold Build Time - Warm Build Time) / Cold Build Time * 100
```

### Cache Size Monitoring

```bash
# Check Docker system cache usage
docker system df

# Check specific cache sizes
docker buildx du

# Monitor pak cache growth
docker run --rm base-container:pak du -sh /root/.cache/R/pak
```

## Advanced Optimization Techniques

### 1. Selective Package Caching

#### Package Grouping Strategy

```dockerfile
# Group stable packages together
COPY R_packages_stable.txt /tmp/
RUN --mount=type=cache,target=/root/.cache/R/pak \
    R -e 'pak::pkg_install(readLines("/tmp/R_packages_stable.txt"))'

# Group frequently updated packages separately
COPY R_packages_dev.txt /tmp/
RUN --mount=type=cache,target=/root/.cache/R/pak \
    R -e 'pak::pkg_install(readLines("/tmp/R_packages_dev.txt"))'
```

#### Conditional Package Installation

```dockerfile
# Install packages only if not cached
RUN --mount=type=cache,target=/root/.cache/R/pak \
    R -e 'if(!require("dplyr", quietly=TRUE)) pak::pkg_install("dplyr")'
```

### 2. Cache Warming Automation

#### CI/CD Cache Warming

```yaml
# GitHub Actions example
name: Warm Cache
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  warm-cache:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      - name: Login to Registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Warm Cache
        run: ./cache-helper.sh warm-all
```

#### Automated Cache Validation

```bash
#!/bin/bash
# validate-cache.sh - Verify cache integrity

echo "Validating cache integrity..."

# Check registry cache availability
for target in base pak-full; do
    if docker buildx imagetools inspect "ghcr.io/user/repo/cache:$target" >/dev/null 2>&1; then
        echo "✅ Cache available for $target"
    else
        echo "❌ Cache missing for $target"
    fi
done

# Check local cache effectiveness
echo "Testing cache effectiveness..."
start_time=$(date +%s)
docker buildx build --file Dockerfile.pak --target pak-full . >/dev/null 2>&1
end_time=$(date +%s)
build_time=$((end_time - start_time))

if [ $build_time -lt 1800 ]; then  # Less than 30 minutes
    echo "✅ Cache is effective (build time: ${build_time}s)"
else
    echo "⚠️  Cache may need optimization (build time: ${build_time}s)"
fi
```

### 3. Cache Maintenance

#### Regular Cache Cleanup

```bash
#!/bin/bash
# cache-maintenance.sh - Regular cache maintenance

# Clean old cache entries (older than 7 days)
docker builder prune --filter until=168h

# Clean unused pak cache
docker run --rm -v pak_cache:/cache alpine find /cache -atime +7 -delete

# Verify cache health
./validate-cache.sh
```

#### Cache Size Management

```bash
# Monitor cache size growth
docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}"

# Set cache size limits
export DOCKER_BUILDKIT_CACHE_MAX_SIZE=10GB

# Implement cache rotation
docker builder prune --filter until=72h --keep-storage 5GB
```

## Troubleshooting Cache Issues

### Cache Miss Diagnosis

```bash
# Enable cache debugging
export BUILDKIT_PROGRESS=plain

# Build with detailed cache information
docker buildx build --progress=plain --file Dockerfile.pak . 2>&1 | grep -E "(cache|CACHE)"

# Check for cache invalidation causes
grep -E "(COPY|ADD|RUN)" Dockerfile.pak
```

### Cache Corruption Recovery

```bash
# Reset all caches
docker builder prune -f
docker system prune -f

# Rebuild cache from scratch
./build-pak-container.sh --no-cache --cache-to "type=registry,ref=ghcr.io/user/repo/cache:pak-full"

# Verify cache integrity
./validate-cache.sh
```

### Performance Regression Analysis

```bash
# Compare build times over time
echo "$(date): $(time docker buildx build --file Dockerfile.pak .)" >> build-times.log

# Analyze trends
tail -20 build-times.log | awk '{print $4}' | sort -n
```

## Best Practices

### 1. Cache Strategy Guidelines

- **Layer Stability**: Place stable layers first, volatile layers last
- **Cache Granularity**: Use appropriate cache mount granularity
- **Registry Management**: Regularly clean registry cache
- **Monitoring**: Continuously monitor cache effectiveness

### 2. Development Workflow

```bash
# Development cycle with cache optimization
./build-pak-container.sh --cache-from ghcr.io/user/repo  # Use existing cache
# Make changes to R_packages.txt
./build-pak-container.sh --cache-from-to ghcr.io/user/repo  # Update cache
```

### 3. Production Deployment

```bash
# Production build with optimized cache
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --cache-from "type=registry,ref=ghcr.io/user/repo/cache:production" \
  --cache-to "type=registry,ref=ghcr.io/user/repo/cache:production" \
  --tag ghcr.io/user/repo:latest \
  --push \
  --file Dockerfile.pak .
```

## Measuring Success

### Key Performance Indicators

- **Cache Hit Rate**: >80% for stable builds
- **Build Time Reduction**: >50% with warm cache
- **Cache Size Efficiency**: <2GB per architecture
- **Registry Cache Availability**: >99% uptime

### Benchmarking Script

```bash
#!/bin/bash
# benchmark-cache.sh - Comprehensive cache benchmarking

echo "=== Cache Performance Benchmark ==="

# Cold build
echo "Running cold build..."
docker builder prune -f >/dev/null 2>&1
cold_start=$(date +%s)
docker buildx build --no-cache --file Dockerfile.pak --target pak-full . >/dev/null 2>&1
cold_end=$(date +%s)
cold_time=$((cold_end - cold_start))

# Warm build
echo "Running warm build..."
warm_start=$(date +%s)
docker buildx build --file Dockerfile.pak --target pak-full . >/dev/null 2>&1
warm_end=$(date +%s)
warm_time=$((warm_end - warm_start))

# Calculate improvement
improvement=$(echo "scale=2; ($cold_time - $warm_time) / $cold_time * 100" | bc)

echo "Cold build time: ${cold_time}s"
echo "Warm build time: ${warm_time}s"
echo "Cache effectiveness: ${improvement}%"

if (( $(echo "$improvement > 50" | bc -l) )); then
    echo "✅ Cache performance meets target (>50% improvement)"
else
    echo "⚠️  Cache performance below target (<50% improvement)"
fi
```

This cache optimization guide provides comprehensive strategies for maximizing the performance benefits of the pak-based R package installation system through effective cache management.