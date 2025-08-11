# Base Container

A comprehensive, reproducible development environment using VS Code dev containers with **pak-based R package management** for optimal performance and caching.

## Features
- **Development Tools**: Git, R, Python, shell utilities
- **R Packages**: 200+ packages with pak-based installation and BuildKit caching
- **Document Preparation**: LaTeX, Pandoc for typesetting
- **Performance Optimized**: 50%+ faster builds with advanced caching
- **Multi-Architecture**: Native support for amd64 and arm64

## pak-based R Package System

This container uses **pak** (modern R package manager) instead of traditional `install.packages()` for:

- **50%+ build time reduction** with BuildKit cache optimization
- **Unified package management** for CRAN, GitHub, and archive packages
- **Enhanced security** through consistent HTTPS handling
- **Better error handling** and automatic retry mechanisms
- **Architecture-segregated libraries** for multi-platform consistency

### Package Categories

- **CRAN Packages**: 200+ packages from `R_packages.txt`
- **GitHub Packages**: httpgd (nx10/httpgd), colorout (jalvesaq/colorout)
- **Archive Packages**: mcmcplots from CRAN archive

### Architecture

```
/opt/R/site-library/
├── 4.5-amd64/          # R 4.5 on amd64 architecture
├── 4.5-arm64/          # R 4.5 on arm64 architecture
└── ...

/usr/local/lib/R/site-library -> /opt/R/site-library/${R_MM}-${TARGETARCH}
```

## Quick Setup

**Prerequisites**: [VS Code](https://code.visualstudio.com/) with [Remote Development](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack) extension

### macOS: Install and Configure Colima

If you're on macOS, you'll need to install and properly configure Colima for correct file permissions:

1. **Install Colima with Homebrew:**
   ```bash
   brew install colima
   ```

2. **Start Colima as a service (persists across reboots):**
   ```bash
   brew services start colima
   ```

3. **Reconfigure for proper UID/GID mapping**
   
   The initial installation uses SSHFS, which causes permission errors when accessing project files from within the container. You need to reconfigure Colima to use the `vz` virtualization framework:
   
   ```bash
   colima stop
   colima delete
   colima start --vm-type vz --mount-type virtiofs
   ```
   
   By default, Colima allocates only 2 CPU cores and 2 GB RAM. For better performance, you can specify more resources, for example:
   ```
   colima stop
   colima delete
   colima start --vm-type vz --mount-type virtiofs --cpu 16 --memory 128
   ```
   Adjust the values to match your system's capabilities.

   Once configured this way, Colima will remember these settings and use `vz` for future starts.

4. **Set Colima as the default Docker context:**
   
   This makes Colima the default for all Docker commands and ensures VS Code's Dev Containers extension works properly:
   
   ```bash
   docker context use colima
   ```
   
   You can verify the active context with:
   ```bash
   docker context ls
   ```

   You can also append to your ~/.zshrc:

   ```zsh
   export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
   ```

### Container Setup

1. **Create `.devcontainer/devcontainer.json` in your project:**

```jsonc
{
  "name": "Base Container Development Environment",
  "image": "ghcr.io/jbearak/base-container:latest",

  // For Colima on macOS, use vz for correct UID/GID mapping:
  // colima stop; colima delete; colima start --vm-type vz --mount-type virtiofs

  // Use non-root user "me" (alias of 'vscode' with same UID/GID). Set to "root" if needed.
  "remoteUser": "me",
  "updateRemoteUserUID": true,

  // Mount local Git config for container Git usage
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,consistency=cached,readonly"
  ],

  // Set container timezone from host
  "containerEnv": {
    "TZ": "${localEnv:TZ}"
  }
}
```

2. **Open in VS Code:**
   - Open your project folder in VS Code
   - When prompted, click "Reopen in Container"

The container will automatically download and start your development environment.

## Building and Performance

### Building the Container

```bash
# Build with pak-based system (recommended)
./build-pak-container.sh

# Build with cache optimization
./build-pak-container.sh --cache-from-to ghcr.io/jbearak/base-container

# Build without cache (for testing)
./build-pak-container.sh --no-cache
```

### Performance Monitoring

```bash
# Run performance benchmarks
./test_build_performance.sh

# Generate build metrics
./generate_build_metrics_summary.sh

# Check cache usage
docker system df
```

### Cache Management

```bash
# Check cache effectiveness
./cache-helper.sh inspect pak

# Clean local cache
./cache-helper.sh clean

# Warm cache for faster builds
./cache-helper.sh warm-all
```

## Documentation

### Core Documentation

- **[README-pak.md](README-pak.md)**: Detailed pak implementation guide
- **[CACHING.md](CACHING.md)**: Cache management and optimization
- **[BUILD_METRICS_README.md](BUILD_METRICS_README.md)**: Build performance tracking
- **[PHASE4_TESTING_README.md](PHASE4_TESTING_README.md)**: Testing framework
- **[PHASE5_INTEGRATION_README.md](PHASE5_INTEGRATION_README.md)**: Integration guide

### Troubleshooting and Optimization

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions
- **[CACHE_OPTIMIZATION.md](CACHE_OPTIMIZATION.md)**: Advanced cache strategies
- **[PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md)**: Performance tuning guide

## Using the Container with an Agentic Coding Tool

To use an agentic coding tool, modify devcontainer.json to include the necessary mounts and post-create commands to install the tool.

### Amazon Q CLI Integration

As an example, here is how to integrate the Amazon Q CLI into your dev container. There are two approaches:

#### Option 1: Custom Docker Image (Recommended)

Build a custom image that extends the base container with Q CLI pre-installed:

1. **Create a Dockerfile** named `Dockerfile.amazonq` in your project root:
   ```dockerfile
   # Dockerfile for Base Container with Amazon Q CLI pre-installed
   FROM ghcr.io/jbearak/base-container:latest

   # Switch to the me user for installation
   USER me
   WORKDIR /home/me

   # Install Amazon Q CLI during image build
   RUN set -e; \
      ARCH="$(uname -m)"; \
      case "$ARCH" in \
        x86_64) Q_ARCH="x86_64" ;; \
        aarch64|arm64) Q_ARCH="aarch64" ;; \
        *) echo "Unsupported arch: $ARCH"; exit 1 ;; \
      esac; \
      URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/q-${Q_ARCH}-linux.zip"; \
      echo "Downloading Amazon Q CLI from $URL"; \
      curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o q.zip; \
      unzip q.zip; \
      chmod +x ./q/install.sh; \
      ./q/install.sh --no-confirm; \
      rm -rf q.zip q

   # Ensure Q CLI is in PATH for all users
   ENV PATH="/home/me/.local/bin:$PATH"
   ```

2. **Build your custom image:**
   ```bash
   docker build -f Dockerfile.amazonq -t my-base-container-amazonq .
   ```

3. **Create folders for persistent configuration:**
   ```bash
   mkdir -p ~/.container-aws ~/.container-amazon-q
   ```

4. **Update your `.devcontainer/devcontainer.json`:**
   ```jsonc
   {
     "name": "Base Container with Amazon Q CLI",
     "image": "my-base-container-amazonq:latest",
     "remoteUser": "me",
     "updateRemoteUserUID": true,
     "mounts": [
       "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,readonly",
       "source=${localEnv:HOME}/.container-aws,target=/home/me/.aws,type=bind",
       "source=${localEnv:HOME}/.container-amazon-q,target=/home/me/.local/share/amazon-q,type=bind"
     ],
     "containerEnv": { "TZ": "${localEnv:TZ}" }
   }
   ```

#### Option 2: PostCreateCommand (Simple but slower)

If you prefer not to build a custom image, you can install Q CLI on container startup:

1. **Create folders for persistent configuration:**
   ```bash
   mkdir -p ~/.container-aws ~/.container-amazon-q
   ```

2. **Update your `.devcontainer/devcontainer.json`:**
   ```jsonc
   {
     "name": "Base Container with Amazon Q CLI",
     "image": "ghcr.io/jbearak/base-container:latest",
     "remoteUser": "me",
     "updateRemoteUserUID": true,
     "mounts": [
       "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,readonly",
       "source=${localEnv:HOME}/.container-aws,target=/home/me/.aws,type=bind",
       "source=${localEnv:HOME}/.container-amazon-q,target=/home/me/.local/share/amazon-q,type=bind"
     ],
     "containerEnv": { "TZ": "${localEnv:TZ}" },
     "postCreateCommand": "ARCH=$(uname -m); case \"$ARCH\" in x86_64) QARCH=x86_64 ;; aarch64|arm64) QARCH=aarch64 ;; *) echo 'Unsupported arch'; exit 1 ;; esac; URL=\"https://desktop-release.q.us-east-1.amazonaws.com/latest/q-${QARCH}-linux.zip\"; curl --proto '=https' --tlsv1.2 -fsSL \"$URL\" -o 'q.zip' && unzip q.zip && ./q/install.sh --no-confirm && rm -rf q.zip q"
   }
   ```

**Note:** Option 1 is recommended as it pre-installs Q CLI during image build, making container startup much faster. Option 2 reinstalls Q CLI every time the container starts.

### User model

As an aesthetic preference, the container contains a non-root user named "me". To retain this design choice while ensuring compatibility with VS Code, the following adjustments are made:

- The image retains the default 'vscode' user required by Dev Containers/VS Code but also creates a 'me' user and 'me' group that share the same UID/GID as 'vscode'.
- Both users have the same home directory: /home/me (the previous /home/vscode is renamed).
- This design ensures compatibility with VS Code while making file listings show owner and group as 'me'.

## Research containers with tmux

For multi-day analyses, keep containers running with tmux sessions to survive disconnections (but not reboots).

**Key practices:**
- Use `--init` for proper signal handling during long runs
- Mount your project directory for data persistence  
- Center workflow around tmux for resilient sessions
- Implement checkpointing for analyses longer than uptime between reboots

### Terminal workflow
```bash
# Set project name from current directory
PROJECT_NAME=$(basename "$(pwd)")

# Start persistent container
docker run -d --name "$PROJECT_NAME" --hostname "$PROJECT_NAME" --restart unless-stopped --init \
  -v "$(pwd)":"/workspaces/$PROJECT_NAME" -w "/workspaces/$PROJECT_NAME" \
  ghcr.io/jbearak/base-container:latest sleep infinity

# Work in tmux
docker exec -it "$PROJECT_NAME" bash -lc "tmux new -A -s '$PROJECT_NAME'"
# Inside tmux: Rscript long_analysis.R 2>&1 | tee -a logs/run.log
# Detach: Ctrl-b then d

# When finished, stop the container
docker stop "$PROJECT_NAME" && docker rm "$PROJECT_NAME"
```

If you start the container using the terminal workflow and then open it from VS Code (the "Reopen in Container" action), Code will treat this like connecting to a host without having specified a workspace. Press "Open..." and enter your project directory (`/workspaces/$PROJECT_NAME`).

Configure Git to avoid permission issues:

```bash
git config --global --add safe.directory "/workspaces/$PROJECT_NAME"
```

This allows Git to operate in /workspaces/ when ownership or permissions differ, as is common in containers.

### VS Code workflow
If you began with the terminal workflow, you can attach to the running container from VS Code. Choose "Remote-Containers: Attach to Running Container..." from the Command Palette.

If you use VS Code to create the container, add the following to your `.devcontainer/devcontainer.json` file:

```jsonc
{
  "shutdownAction": "none",
  "init": true,
  "postAttachCommand": "tmux new -A -s analysis"
}
```

**Limitations:** Reboots terminate all processes. Container auto-restarts but jobs must be resumed manually. Use checkpointing for critical work.

## Migration from Traditional System

### Key Improvements

| Aspect | Traditional | pak-based |
|--------|-------------|-----------||
| **Build Time** | 35-45 min | 15-25 min (with cache) |
| **Package Management** | Multiple systems | Unified pak interface |
| **Error Handling** | Manual intervention | Automatic retry |
| **GitHub Packages** | Manual API calls | Native integration |
| **Caching** | Limited | Comprehensive BuildKit + pak |
| **Multi-arch** | Complex setup | Native support |

### Compatibility

- **Library Paths**: Maintained compatibility with existing R code
- **Package Versions**: Consistent with CRAN latest versions  
- **Container Interface**: Identical user experience
- **Development Workflow**: No changes required

## Troubleshooting

### Quick Diagnostics

```bash
# System health check
docker --version && docker buildx version

# pak system check
docker run --rm ghcr.io/jbearak/base-container:latest R -e 'library(pak); pak::pak_config()'

# Check cache usage
docker system df

# Check pak cache (if container exists)
docker run --rm base-container:pak R -e 'pak::cache_summary()' 2>/dev/null || echo "Container not built yet"
```

### Common Issues

- **Build failures**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Performance issues**: See [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md)
- **Cache problems**: Review [CACHE_OPTIMIZATION.md](CACHE_OPTIMIZATION.md)

## License

Licensed under the [MIT License](LICENSE.txt).