# Base Container

A comprehensive, reproducible development environment using VS Code dev containers. Includes essential tools for data science, development, and document preparation.

## Features
- **Development Tools**: Git, R, Python, shell utilities
- **R Packages**: Comprehensive set of packages for data analysis, modeling, and visualization
- **Document Preparation**: LaTeX, Pandoc for typesetting
- **Performance**: Fast rebuilds with BuildKit caching
- **Multi-Architecture**: Supports both AMD64 and ARM64


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


## Technical Implementation Details

### Architecture

The container uses a multi-stage build process optimized for Docker layer caching and supports both AMD64 and ARM64 architectures:

- **Base Stage**: Ubuntu 24.04 with essential system packages
- **Development Tools**: Neovim with plugins, Git, shell utilities  
- **Document Preparation**: LaTeX, Pandoc, Haskell (for pandoc-crossref)
- **Programming Languages**: Python 3.13, R 4.5+ with comprehensive packages
- **VS Code Integration**: VS Code Server with extensions (positioned last for optimal caching)

**Platform Detection**: The Dockerfile automatically detects the target architecture using `dpkg --print-architecture` and installs architecture-specific binaries for tools like Go, Neovim, Hadolint, and others.

**Optimization Strategy**: Expensive, stable components (LaTeX, Haskell) are built early, while frequently updated components (VS Code extensions) are positioned late to minimize rebuild times when making changes.

### R Package Management

The container uses [pak](https://pak.r-lib.org/) for R package management, providing:

- **Better Dependency Resolution**: Handles complex dependency graphs more reliably
- **Faster Installation**: Parallel downloads and compilation
- **Caching**: BuildKit cache mounts for faster rebuilds

#### Cache Usage Examples
```bash
# Build with local cache only (default) - host platform
./build-container.sh --full

# Build for AMD64 platform (cross-platform on Apple Silicon)
./build-amd64.sh full-container

# Build using registry cache
./build-container.sh --full --cache-from ghcr.io/jbearak/base-container

# Build and update registry cache
./build-container.sh --full --cache-from-to ghcr.io/jbearak/base-container

# Build without cache (clean build)
./build-container.sh --full --no-cache

# Clean local cache
./cache-helper.sh clean
```

#### Available Build Targets
- `base` - Ubuntu base with system packages
- `base-nvim` - Base + Neovim
- `base-nvim-vscode` - Base + Neovim + VS Code Server
- `base-nvim-vscode-tex` - Base + Neovim + VS Code + LaTeX
- `base-nvim-vscode-tex-pandoc` - Base + Neovim + VS Code + LaTeX + Pandoc
- `base-nvim-vscode-tex-pandoc-haskell` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell
- `base-nvim-vscode-tex-pandoc-haskell-crossref` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus` - Base + additional tools
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r` - Base + R with comprehensive packages via pak
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py` - Base + R + Python
- `full` - Complete development environment (default)

### User Model

The container uses a non-root user named "me" for security and compatibility:

- Compatible with VS Code Dev Containers (shares UID/GID with 'vscode' user)
- Home directory: `/home/me`
- Proper file permissions for mounted volumes


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
docker run --rm full-container-arm64 R -e 'pak::cache_summary()' 2>/dev/null || echo "Container not built yet"
```

## License

Licensed under the [MIT License](LICENSE.txt).


## Building the Container

### Platform Support

The container supports both AMD64 and ARM64 architectures with automatic platform detection:

- **`./build-container.sh`** - Builds for the **host platform** (ARM64 on Apple Silicon, AMD64 on Intel/AMD systems)
  - Default: Builds both `full-container` and `r-container` for host architecture
  - Examples:
    ```bash
    ./build-container.sh                    # Build both containers for host platform
    ./build-container.sh --full-container   # Build full container for host platform
    ./build-container.sh --r-container      # Build R container for host platform
    ```

- **`./build-amd64.sh`** - Explicitly builds for **AMD64 platform** (useful on Apple Silicon for cross-platform builds)
  - Examples:
    ```bash
    ./build-amd64.sh base                   # Build base stage for AMD64
    ./build-amd64.sh full-container         # Build full container for AMD64
    ./build-amd64.sh r-container           # Build R container for AMD64
    ```

### Image Naming Convention

The build scripts use different naming conventions for local vs. registry images:

- **Local Images**: Include architecture suffix for clarity
  - Examples: `full-container-arm64`, `r-container-amd64`, `base-amd64`
  - Built by: `./build-container.sh`, `./build-amd64.sh`, `./build-all.sh`

- **Registry Images**: Use multi-architecture manifests (no arch suffix)
  - Examples: `ghcr.io/user/repo:latest` (contains both amd64 and arm64)
  - Created by: `./push-to-ghcr.sh -a` or `docker buildx build --push`

This approach provides clarity during development while following Docker best practices for distribution.

### Build Options

All build scripts support additional options:

```bash
# Build with testing
./build-container.sh --full-container --test

# Build without cache
./build-container.sh --full-container --no-cache

# Build with registry cache
./build-container.sh --full-container --cache-from-to ghcr.io/user/repo
```

### Publishing Images

- **`./push-to-ghcr.sh`** - Pushes images to GitHub Container Registry (GHCR)
  - **Platform**: Only pushes images built for the **host platform** (default)
  - **Multi-platform**: Use `-a` flag to build and push both AMD64 and ARM64
  - **Default**: Pushes both `full-container` and `r-container` if available locally
  - **Examples**:
    ```bash
    ./push-to-ghcr.sh                       # Push both containers (host platform)
    ./push-to-ghcr.sh -a                    # Build and push both containers (both platforms)
    ./push-to-ghcr.sh -t full-container     # Push specific container (host platform)
    ./push-to-ghcr.sh -a -t r-container     # Build and push R container (both platforms)
    ./push-to-ghcr.sh -b -t r-container     # Build and push R container (host platform)
    ```

- **Multi-architecture publishing**:
  ```bash
  # Option 1: Use the -a flag (recommended)
  ./push-to-ghcr.sh -a                     # Build and push both platforms
  ./push-to-ghcr.sh -a -t full-container   # Build and push specific target, both platforms
  
  # Option 2: Use docker buildx directly
  docker buildx build --platform linux/amd64,linux/arm64 \
    --target full-container --push -t ghcr.io/user/repo:latest .
  ```

## Multiple container targets

This repository now supports two top-level container targets optimized for different use cases.

- r-container: a lightweight R-focused image for CI/CD
  - Base: Ubuntu + essential build tools only
  - Includes: R 4.x, pak, JAGS, and packages from R_packages.txt (Stan packages excluded)
  - Skips: Neovim, LaTeX toolchain, Pandoc, Haskell, Python, VS Code server, CmdStan
  - Working directory: /workspaces, ENV CI=true
  - Best for: GitHub Actions / Bitbucket Pipelines / other CI runners

- full-container: the complete local development environment
  - Includes: Neovim (+plugins), LaTeX, Pandoc (+crossref), Haskell/Stack,
    Python 3.13, R (+pak + packages), VS Code server, dotfiles
  - Working directory: /workspaces
  - Best for: local development, VS Code Dev Containers

### Build commands

- **Build both containers for host platform (default):**
  ```bash
  ./build-container.sh
  ```

- **Build specific container for host platform:**
  ```bash
  ./build-container.sh --r-container      # Lightweight R image (CI optimized)
  ./build-container.sh --full-container   # Complete dev environment
  ```

- **Build for AMD64 platform (cross-platform):**
  ```bash
  ./build-amd64.sh r-container            # R container for AMD64
  ./build-amd64.sh full-container         # Full container for AMD64
  ```

- **Build all combinations (2 architectures × 2 targets = 4 images):**
  ```bash
  ./build-all.sh                          # Build all 4 images sequentially
  ./build-all.sh --parallel               # Build all 4 images in parallel
  ```

- **Push to GitHub Container Registry:**
  ```bash
  ./push-to-ghcr.sh                       # Push both containers (host platform only)
  ./push-to-ghcr.sh -t full-container     # Push specific container (host platform only)
  ```
  
  **Note**: `push-to-ghcr.sh` only pushes images built for the **host platform**. To push multi-architecture images, use `docker buildx build --push` with `--platform linux/amd64,linux/arm64`.

Add `--test` to run non-interactive verification inside the built image.

### Using in VS Code Dev Containers (full-container)

Reference the published image in your project's .devcontainer/devcontainer.json:

{
  "name": "base-container (full)",
  "image": "ghcr.io/jbearak/full-container:full-container",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/project,type=bind",
  "workspaceFolder": "/workspaces/project"
}

### Notes

- Both targets install R packages using pak based on R_packages.txt; the set is shared so R behavior is consistent.
- The r-container target may install additional apt packages (e.g., pandoc) via pak when needed by R packages.
- The legacy stage name full remains available for backward compatibility and aliases to full-container.



### r-container (slim CI image)

This stage is designed for CI/CD. It intentionally excludes heavy toolchains and developer tools to keep the image small and fast:
- No CmdStan; Stan model compilation is not supported in this image
- Stan-related R packages are excluded by default during installation
- Compilers (g++, gcc, gfortran, make) are installed only temporarily for building R packages, then purged
- Not included: LaTeX, Neovim, pandoc-crossref, Go toolchain, Python user tools, and various CLI utilities present in full-container
- Aggressive cleanup of caches, man pages, docs, and R help files

If you need to compile Stan models, use the full-container image or a custom derivative.
