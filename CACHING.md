# Build Caching

This project implements target-specific build caching to speed up Docker builds and reduce bandwidth usage, especially in CI/CD environments.

## Overview

The caching system uses Docker BuildKit's registry cache feature with target-specific cache keys. Each build target (base, base-nvim, etc.) maintains its own cache, preventing cache pollution between different stages.

## Local Development

### Basic Usage

```bash
# Build with local cache only (default)
./build-container.sh --base

# Build using registry cache
./build-container.sh --base --cache-from ghcr.io/user/repo

# Build and update registry cache
./build-container.sh --base --cache-from-to ghcr.io/user/repo

# Build without any cache
./build-container.sh --base --no-cache
```

### Cache Helper Script

Use `cache-helper.sh` for cache management:

```bash
# Pre-warm cache for a specific target
./cache-helper.sh warm base

# Pre-warm cache for all targets
./cache-helper.sh warm-all

# List available cache images
./cache-helper.sh list

# Clean local cache
./cache-helper.sh clean

# Inspect cache details
./cache-helper.sh inspect base
```

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/build.yml`) demonstrates:

- **Multi-platform builds**: amd64 and arm64
- **Target-specific caching**: Each target uses its own cache key
- **Matrix builds**: All targets built in parallel
- **Cache reuse**: Subsequent builds leverage existing cache layers

### Cache Keys

Cache images are stored with target-specific tags:

- `ghcr.io/user/repo/cache:base`
- `ghcr.io/user/repo/cache:base-nvim`
- `ghcr.io/user/repo/cache:base-nvim-vscode`
- etc.

## Benefits

1. **Faster builds**: Reuse layers from previous builds
2. **Reduced bandwidth**: Only download changed layers
3. **Target isolation**: Changes to one target don't invalidate others
4. **CI efficiency**: Parallel builds with shared cache layers

## Registry Requirements

For registry caching, you need:

- Push access to the container registry
- Docker BuildKit enabled (default in modern Docker)
- Sufficient registry storage quota

## Example Workflows

### Development Iteration

```bash
# First build (slow, populates cache)
./build-container.sh --base --cache-from-to ghcr.io/user/repo

# Subsequent builds (fast, uses cache)
./build-container.sh --base --cache-from ghcr.io/user/repo
```

### CI/CD Pipeline

The GitHub Actions workflow automatically:

1. Sets up Docker BuildX
2. Logs into the container registry
3. Builds all targets with registry caching
4. Runs target-specific tests
5. Creates multi-arch manifests

### Emergency Cache Reset

```bash
# Clean local cache
./cache-helper.sh clean

# Build without cache to reset
./build-container.sh --full --no-cache --cache-to ghcr.io/user/repo
```

## Troubleshooting

**Cache misses**: Ensure cache registry URL is correct and accessible.

**Permission errors**: Verify push access to the registry.

**Storage issues**: Registry caches can be large; monitor quota usage.

**Stale cache**: Use `--no-cache` occasionally to ensure clean builds.
