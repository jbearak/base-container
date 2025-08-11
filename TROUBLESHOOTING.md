# Troubleshooting Guide

This guide provides solutions for common issues encountered with the pak-based R package installation system.

## Quick Diagnostics

### System Health Check

```bash
# Check Docker and BuildKit
docker --version
docker buildx version

# Check available disk space
df -h

# Check Docker system usage
docker system df

# Check running containers
docker ps -a
```

### pak System Check

```bash
# Test pak installation
docker run --rm ghcr.io/jbearak/base-container:latest R -e 'library(pak); pak::pak_config()'

# Check site library paths
docker run --rm ghcr.io/jbearak/base-container:latest R -e '.libPaths()'

# Verify cache status
docker run --rm ghcr.io/jbearak/base-container:latest R -e 'pak::cache_summary()'
```

## Build Issues

### BuildKit Not Available

**Symptoms:**
- Error: "buildx is not supported"
- Build fails with cache mount errors

**Solutions:**
```bash
# Enable BuildKit (Docker 20.10+)
export DOCKER_BUILDKIT=1

# Install buildx plugin if missing
docker buildx install

# Verify buildx is available
docker buildx version
```

### Cache Mount Failures

**Symptoms:**
- "mount type cache not supported"
- Cache mounts ignored during build

**Solutions:**
```bash
# Ensure BuildKit is enabled
export DOCKER_BUILDKIT=1

# Use buildx explicitly
docker buildx build --file Dockerfile.pak --target pak-full .

# Check buildx builder
docker buildx ls
docker buildx use default
```

### Out of Disk Space

**Symptoms:**
- "no space left on device"
- Build fails during package installation

**Solutions:**
```bash
# Clean Docker system
docker system prune -f

# Remove unused images
docker image prune -f

# Clean build cache
docker builder prune -f

# Check and clean pak cache
./cache-helper.sh clean
```

### Build Timeout

**Symptoms:**
- Build hangs during R package installation
- No progress for extended periods

**Solutions:**
```bash
# Increase Docker memory allocation (Docker Desktop)
# Settings > Resources > Memory > 8GB+

# Build with progress output
docker buildx build --progress=plain --file Dockerfile.pak .

# Build without cache to isolate issues
./build-pak-container.sh --no-cache
```

## Package Installation Issues

### pak Installation Failures

**Symptoms:**
- "pak package not found"
- pak functions not available

**Solutions:**
```bash
# Verify pak is installed
docker run --rm base-container:pak R -e 'installed.packages()["pak",]'

# Reinstall pak if missing
docker run --rm base-container:pak R -e 'install.packages("pak")'

# Check pak configuration
docker run --rm base-container:pak R -e 'pak::pak_config()'
```

### CRAN Package Installation Failures

**Symptoms:**
- Specific packages fail to install
- Dependency resolution errors

**Solutions:**
```bash
# Check package availability
docker run --rm base-container:pak R -e 'pak::pkg_status("package_name")'

# Install with verbose output
docker run --rm base-container:pak R -e 'pak::pkg_install("package_name", ask=FALSE)'

# Check for system dependencies
docker run --rm base-container:pak apt list --installed | grep -i package_name
```

### GitHub Package Installation Failures

**Symptoms:**
- GitHub packages fail to install
- Authentication errors

**Solutions:**
```bash
# Test GitHub connectivity
docker run --rm base-container:pak curl -I https://github.com

# Install with explicit GitHub reference
docker run --rm base-container:pak R -e 'pak::pkg_install("user/repo@main")'

# Check GitHub rate limits
docker run --rm base-container:pak R -e 'pak::github_rate_limit()'
```

### Archive Package Installation Failures

**Symptoms:**
- Archive packages fail to download
- URL not accessible errors

**Solutions:**
```bash
# Test URL accessibility
docker run --rm base-container:pak curl -I "https://cran.r-project.org/src/contrib/Archive/package/package_version.tar.gz"

# Use alternative CRAN mirror
docker run --rm base-container:pak R -e 'options(repos = c(CRAN = "https://cloud.r-project.org"))'

# Install from local file if available
# Copy file to container and install
```

## Runtime Issues

### Package Loading Failures

**Symptoms:**
- `library(package)` fails
- "package not found" errors

**Solutions:**
```bash
# Check if package is installed
docker run --rm base-container:pak R -e 'installed.packages()["package_name",]'

# Check library paths
docker run --rm base-container:pak R -e '.libPaths()'

# Verify site library structure
docker run --rm base-container:pak ls -la /opt/R/site-library/

# Check symlink integrity
docker run --rm base-container:pak ls -la /usr/local/lib/R/site-library
```

### Architecture Mismatch

**Symptoms:**
- Packages installed for wrong architecture
- Binary compatibility errors

**Solutions:**
```bash
# Check current architecture
docker run --rm base-container:pak uname -m

# Verify architecture-specific library
docker run --rm base-container:pak R -e 'R.version$arch'

# List architecture-specific directories
docker run --rm base-container:pak ls -la /opt/R/site-library/
```

### Memory Issues

**Symptoms:**
- R crashes during package loading
- Out of memory errors

**Solutions:**
```bash
# Increase Docker memory limit
# Docker Desktop: Settings > Resources > Memory

# Check memory usage
docker run --rm base-container:pak free -h

# Run with memory monitoring
docker run --rm -m 8g base-container:pak R -e 'memory.limit()'
```

## Cache Issues

### Cache Not Working

**Symptoms:**
- Builds always take full time
- No cache hit messages

**Solutions:**
```bash
# Verify BuildKit cache support
docker buildx build --help | grep cache

# Check cache mount syntax
grep -n "mount=type=cache" Dockerfile.pak

# Build with cache debugging
docker buildx build --progress=plain --file Dockerfile.pak .
```

### Cache Corruption

**Symptoms:**
- Inconsistent build results
- Unexpected package versions

**Solutions:**
```bash
# Clean all caches
docker builder prune -f
./cache-helper.sh clean

# Rebuild without cache
./build-pak-container.sh --no-cache

# Verify cache integrity
docker run --rm base-container:pak R -e 'pak::cache_summary()'
```

### Registry Cache Issues

**Symptoms:**
- Registry cache not accessible
- Authentication failures

**Solutions:**
```bash
# Check registry authentication
docker login ghcr.io

# Test registry access
docker pull ghcr.io/jbearak/base-container/cache:base

# Use local cache only
./build-pak-container.sh --no-registry-cache
```

## Performance Issues

### Slow Builds

**Symptoms:**
- Builds take longer than expected
- Poor cache hit rates

**Solutions:**
```bash
# Check cache effectiveness
docker system df

# Monitor build progress
docker buildx build --progress=plain --file Dockerfile.pak .

# Use performance testing script
./test_build_performance.sh

# Check network connectivity
docker run --rm base-container:pak ping -c 3 cran.r-project.org
```

### High Memory Usage

**Symptoms:**
- System becomes unresponsive during builds
- Docker memory warnings

**Solutions:**
```bash
# Monitor resource usage
docker stats

# Reduce parallel compilation
export MAKEFLAGS="-j2"

# Increase swap space
sudo swapon --show
```

### Network Issues

**Symptoms:**
- Package downloads fail intermittently
- Timeout errors

**Solutions:**
```bash
# Test network connectivity
docker run --rm base-container:pak curl -I https://cran.r-project.org

# Use alternative mirrors
docker run --rm base-container:pak R -e 'chooseCRANmirror(ind=1)'

# Configure proxy if needed
export HTTP_PROXY=http://proxy:port
export HTTPS_PROXY=http://proxy:port
```

## Development Container Issues

### VS Code Integration Problems

**Symptoms:**
- Container fails to start in VS Code
- Extensions not working

**Solutions:**
```bash
# Check devcontainer.json syntax
cat .devcontainer/devcontainer.json | jq .

# Test container manually
docker run -it --rm ghcr.io/jbearak/base-container:latest

# Check VS Code Remote Development extension
code --list-extensions | grep ms-vscode-remote
```

### User Permission Issues

**Symptoms:**
- File permission errors
- Cannot write to mounted directories

**Solutions:**
```bash
# Check user mapping
docker run --rm ghcr.io/jbearak/base-container:latest id

# Verify mount permissions
docker run --rm -v $(pwd):/workspace ghcr.io/jbearak/base-container:latest ls -la /workspace

# Use updateRemoteUserUID in devcontainer.json
"updateRemoteUserUID": true
```

### Git Configuration Issues

**Symptoms:**
- Git commands fail in container
- Authentication issues

**Solutions:**
```bash
# Check git configuration
docker run --rm ghcr.io/jbearak/base-container:latest git config --list

# Mount git config
"mounts": [
  "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,readonly"
]

# Configure safe directory
git config --global --add safe.directory /workspaces/project
```

## Advanced Troubleshooting

### Debug Mode

Enable verbose logging for detailed troubleshooting:

```bash
# Build with debug output
./build-pak-container.sh --debug

# Run tests with verbose output
VERBOSE=true ./test_suite_phase4.sh

# Enable R debugging
docker run --rm base-container:pak R -e 'options(error=traceback)'
```

### Log Analysis

```bash
# Extract build logs
docker buildx build --progress=plain --file Dockerfile.pak . 2>&1 | tee build.log

# Analyze pak logs
docker run --rm base-container:pak R -e 'pak::pak_config_get("log_level")'

# Check system logs
docker run --rm base-container:pak journalctl --no-pager
```

### Container Inspection

```bash
# Inspect running container
docker exec -it container_name bash

# Check environment variables
docker exec container_name env

# Examine file system
docker exec container_name find /opt/R -name "*.so" | head -10
```

## Getting Help

### Information to Provide

When reporting issues, include:

1. **System Information:**
   ```bash
   docker --version
   docker buildx version
   uname -a
   ```

2. **Build Command Used:**
   ```bash
   # Exact command that failed
   ./build-pak-container.sh --debug
   ```

3. **Error Messages:**
   - Complete error output
   - Build logs
   - Container logs

4. **Environment:**
   - Operating system
   - Docker configuration
   - Available resources

### Support Channels

- **GitHub Issues**: Create issue with `troubleshooting` label
- **Documentation**: Check existing documentation files
- **Testing**: Run diagnostic scripts to gather information

### Diagnostic Script

Create a diagnostic script to gather system information:

```bash
#!/bin/bash
echo "=== System Diagnostics ==="
echo "Docker version: $(docker --version)"
echo "BuildKit version: $(docker buildx version)"
echo "Available disk space:"
df -h
echo "Docker system usage:"
docker system df
echo "Available memory:"
free -h
echo "=== End Diagnostics ==="
```

This troubleshooting guide covers the most common issues encountered with the pak-based R package installation system. For issues not covered here, please create a GitHub issue with detailed information about your problem.