# Multiple Container Builds Implementation Summary

This document summarizes the implementation of issue #29 - Multiple Container Builds.

## Overview

The implementation creates two final container targets:
- **r-container**: Lightweight for CI/CD (GitHub Actions, Bitbucket Pipelines)
- **full-container**: Complete development environment (renamed from 'full')

## Key Changes Made

### 1. Files Added
- `R_packages_essential.txt` - Essential R packages for r-container
- `.dockerignore` - Build optimization
- `IMPLEMENTATION_SUMMARY.md` - This file

### 2. Dockerfile Changes
- Updated header to reflect multiple container builds
- Added jq and yq to base stage for both containers
- Renamed final stage from 'full' to 'full-container'
- Added new 'r-container' stage that branches from base

### 3. Build Script Changes (build-container.sh)
- Updated default target to 'full-container'
- Added --r-container and --full-container flags
- Updated test conditions for new targets
- Updated help text and examples
- Updated final output section

### 4. Container Specifications

#### r-container (Lightweight CI/CD)
- **Base**: Ubuntu 24.04 + basic tools + jq/yq
- **R**: Latest from CRAN (no CmdStan/JAGS)
- **Packages**: Essential R packages only (~80 packages)
- **Working Dir**: `/workspace` (CI standard)
- **Optimizations**: 
  - Aggressive cleanup (removes dev tools, LaTeX, etc.)
  - CI environment variables
  - Smaller package set
- **Estimated Size**: 1-2GB
- **Use Case**: GitHub Actions, Bitbucket Pipelines

#### full-container (Complete Development)
- **Base**: All existing stages (LaTeX, Pandoc, Haskell, Python 3.13, etc.)
- **R**: Latest from CRAN + CmdStan + JAGS
- **Packages**: Complete R package set (~200+ packages)
- **Working Dir**: `/workspaces` (dev container standard)
- **Features**: VS Code server, Neovim, all development tools
- **Estimated Size**: 4-6GB
- **Use Case**: Full development environment

## Build Commands

```bash
# Build lightweight R container for CI/CD
./build-container.sh --r-container

# Build complete development environment
./build-container.sh --full-container

# Legacy support (maps to full-container)
./build-container.sh --full
```

## Container Registry Naming

- `ghcr.io/jbearak/r-container:latest` (lightweight CI/CD)
- `ghcr.io/jbearak/full-container:latest` (complete dev environment)

## Implementation Status

- [x] Created essential R packages list
- [x] Added .dockerignore for build optimization
- [x] Updated Dockerfile header and structure
- [x] Added jq/yq to base stage
- [x] Created r-container stage
- [x] Renamed full to full-container
- [x] Updated build script arguments
- [x] Updated test conditions
- [x] Updated help text and examples
- [ ] Push updated Dockerfile (in progress)
- [ ] Push updated build script (in progress)
- [ ] Test builds
- [ ] Update documentation

## Next Steps

1. Complete file uploads to repository
2. Test both container builds
3. Update README.md with new usage instructions
4. Create pull request for review
5. Update CI/CD workflows if needed

## Benefits

1. **Space Efficiency**: r-container is ~3-4GB smaller than full-container
2. **CI Performance**: Faster pulls and reduced storage costs
3. **Flexibility**: Choose appropriate container for use case
4. **Backward Compatibility**: Legacy --full flag still works
5. **Consistent Tooling**: Both containers include jq/yq for JSON/YAML processing