# Build Caching

This project implements target-specific build caching to speed up Docker builds and reduce bandwidth usage, especially for the pak-based R package system which benefits significantly from caching.

## Overview

The caching system uses Docker BuildKit's registry cache feature with target-specific cache keys. Each build target maintains its own cache, preventing cache pollution between different stages. This is particularly important for the R package installation stage which can take significant time without caching.

## Local Development

### Basic Usage

```bash
# Build with local cache only (default)
./build-container.sh --full

# Build using registry cache
./build-container.sh --full --cache-from ghcr.io/jbearak/base-container

# Build and update registry cache
./build-container.sh --full --cache-from-to ghcr.io/jbearak/base-container

# Build without any cache (clean build)
./build-container.sh --full --no-cache
```

### Available Build Targets

The pak-based system supports these build targets:

- `base` - Ubuntu base with system packages
- `base-nvim` - Base + Neovim
- `base-nvim-vscode` - Base + Neovim + VS Code Server
- `base-nvim-vscode-tex` - Base + Neovim + VS Code + LaTeX
- `base-nvim-vscode-tex-pandoc` - Base + Neovim + VS Code + LaTeX + Pandoc
- `base-nvim-vscode-tex-pandoc-haskell` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell
- `base-nvim-vscode-tex-pandoc-haskell-crossref` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref + additional tools
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref + additional tools + R with 600+ packages via pak
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref + additional tools + R + Python
- `full` - Complete development environment (default)

### Cache Helper Script

Use `cache-helper.sh` for cache management:

```bash
# Clean local Docker build cache
./cache-helper.sh clean

# List available cache images
./cache-helper.sh list

# Pre-warm cache for specific target
./cache-helper.sh warm base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r

# Pre-warm cache for all targets
./cache-helper.sh warm-all
```

## pak-Specific Caching Benefits

The pak-based R package system particularly benefits from caching:

### Cache Mount Points
The Dockerfile uses BuildKit cache mounts for:
- `/root/.cache/R/pak` - pak metadata and dependency cache
- `/tmp/R-pkg-cache` - compiled package cache  
- `/tmp/downloaded_packages` - source package downloads

### Performance Impact
- **First build**: ~30-45 minutes for 600+ R packages
- **Cached build**: ~5-10 minutes (80%+ time savings)
- **Incremental changes**: Only affected packages rebuild

## Registry Caching

### Cache Keys

Cache images are stored with target-specific tags:

- `ghcr.io/jbearak/base-container/cache:base`
- `ghcr.io/jbearak/base-container/cache:base-nvim`
- `ghcr.io/jbearak/base-container/cache:base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r`
- etc.

### Registry Requirements

For registry caching, you need:

- Push access to the container registry
- Docker BuildKit enabled (default in modern Docker)
- Sufficient registry storage quota (R packages can be large)

## Example Workflows

### Development Iteration

```bash
# First build (slow, populates cache)
./build-container.sh --full --cache-from-to ghcr.io/jbearak/base-container

# Subsequent builds (fast, uses cache)
./build-container.sh --full --cache-from ghcr.io/jbearak/base-container

# Test specific R stage only
./build-container.sh --base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r --cache-from ghcr.io/jbearak/base-container
```

### Multi-Architecture Builds

```bash
# Build for multiple architectures with caching
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target full \
  --cache-from type=registry,ref=ghcr.io/jbearak/base-container/cache:full \
  --cache-to type=registry,ref=ghcr.io/jbearak/base-container/cache:full,mode=max \
  -t base-container:multiarch .
```

### Emergency Cache Reset

```bash
# Clean local cache
./cache-helper.sh clean

# Build without cache to reset
./build-container.sh --full --no-cache --cache-to ghcr.io/jbearak/base-container
```

## Benefits

1. **Faster R Package Builds**: pak cache mounts provide 80%+ time savings
2. **Reduced Bandwidth**: Only download changed packages
3. **Target Isolation**: Changes to one target don't invalidate others
4. **Multi-Architecture Support**: Cache works across AMD64 and ARM64

## Troubleshooting

**Cache misses**: Ensure cache registry URL is correct and accessible.

**Permission errors**: Verify push access to the registry.

**Storage issues**: R package caches can be large; monitor quota usage.

**Stale cache**: Use `--no-cache` occasionally to ensure clean builds.

**pak cache issues**: If pak cache becomes corrupted, clean local cache and rebuild.

## Cache Management Best Practices

1. **Regular cleanup**: Run `./cache-helper.sh clean` periodically
2. **Target-specific builds**: Use specific targets during development to avoid rebuilding everything
3. **Registry cache**: Use `--cache-from-to` for shared development environments
4. **Monitor storage**: Registry caches for R packages can consume significant space
