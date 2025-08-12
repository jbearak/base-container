# ===========================================================================
# MULTI-STAGE R base-container IMAGE - OPTIMIZED FOR DOCKER LAYER CACHING
# ===========================================================================
# Purpose   : Build a containerized R development environment optimized for
#             VS Code and the Dev Containers extension.  This Dockerfile uses
#             a multi-stage approach optimized for Docker layer caching:
#
#             Stage 1 (base)               : Setup Ubuntu with basic tools.
#             Stage 2 (base-nvim)          : Initialize and bootstrap Neovim plugins using lazy.nvim.
#             Stage 3 (base-nvim-tex)      : Add LaTeX tools for typesetting.
#             Stage 4 (base-nvim-tex-pandoc): Add Pandoc to support typesetting from markdown.
#             Stage 5 (base-nvim-tex-pandoc-haskell): Compile Haskell to compile pandoc-crossref.
#             Stage 6 (base-nvim-tex-pandoc-haskell-crossref): Add pandoc-crossref for numbering figures, equations, tables.
#             Stage 7 (base-nvim-tex-pandoc-haskell-crossref-plus): Add extra LaTeX packages via tlmgr (e.g. soul)
#             Stage 8 (base-nvim-tex-pandoc-haskell-crossref-plus-py): Add Python 3.13 using deadsnakes PPA.
#             Stage 9 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r): Install R, CmdStan, and JAGS.
#             Stage 10 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak): Install a comprehensive suite of R packages.
#             Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode): Setup VS Code server with pre-installed extensions.
#             Stage 12 (full)              : Final stage; applies shell config, sets workdir, and finalizes defaults.
#
# Build Metrics: Each stage tracks timing and size information:
#   • Start/end timestamps for build duration calculation
#   • Filesystem usage before/after each stage
#   • Final summary table showing cumulative time and size
#
# OPTIMIZATION STRATEGY:
#   • Expensive, stable stages early: LaTeX, Haskell, pandoc-crossref (stages 3-6)
#   • Expensive, frequently updated stages middle: R packages (stage 10)
#   • Fast, frequently updated stages late: VS Code (stage 11) - only ~3-5 min rebuild
#
# Why multi-stage?
#   • Allows for quick debugging of specific components without rebuilding everything
#   • Better separation of concerns (each stage has a clear purpose)
#   • Optimized for Docker layer caching - VS Code updates won't invalidate R packages
#
# Usage     : See build-container.sh for user-friendly build commands, or
#             build directly with:
#               docker build --target base -t base-container:base .
#               docker build --target base-nvim -t base-container:base-nvim .
#               docker build --target base-nvim-tex -t base-container:base-nvim-tex .
#               docker build --target base-nvim-tex-pandoc -t base-container:base-nvim-tex-pandoc .
#               docker build --target base-nvim-tex-pandoc-haskell -t base-container:base-nvim-tex-pandoc-haskell .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref -t base-container:base-nvim-tex-pandoc-haskell-crossref .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus -t base-container:base-nvim-tex-pandoc-haskell-crossref-plus .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py -t base-container:base-nvim-tex-pandoc-haskell-crossref-plus-py .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r -t base-container:base-nvim-tex-pandoc-haskell-crossref-plus-py-r .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak -t base-container:base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode -t base-container:base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode .
#               docker build --target full -t base-container:latest .
#
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 1: BASE SYSTEM
# ===========================================================================
# This stage installs Ubuntu packages and copies user configuration files 
# (dotfiles). R installation, CmdStan, and JAGS have been moved to stage 9
# for better build caching and separation of concerns.
# ---------------------------------------------------------------------------

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base

# ---------------------------------------------------------------------------
# Build Metrics: Stage 1 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base,start,$(date +%s)" > /tmp/build-metrics/stage-1-base.csv && \
    echo "Stage 1 (base) started at $(date)" && \
    # Record initial filesystem usage
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-1-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-1-size-start.txt)"

# ---------------------------------------------------------------------------
# Container metadata labels
# ---------------------------------------------------------------------------
# These labels provide metadata about the container image and link it to
# the source repository for GitHub Container Registry integration
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.source="https://github.com/jbearak/base-container"
LABEL org.opencontainers.image.description="Multi-stage R development environment with Neovim, VS Code, LaTeX, and Pandoc"
LABEL org.opencontainers.image.licenses="MIT"

# ---------------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------------
# DEBIAN_FRONTEND=noninteractive prevents package installations from
# prompting for user input (timezone, keyboard layout, etc.)
# ---------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System dependencies installation
# ---------------------------------------------------------------------------
# Installing everything in one RUN layer minimizes the number of image
# layers and allows apt-get clean to actually reduce the final image size.
# 
# Key packages explained:
#   software-properties-common : Enables add-apt-repository command
#   dirmngr, gnupg             : Required for adding GPG keys
#   ca-certificates            : SSL certificates for HTTPS downloads
#   wget, curl, unzip          : Download and extraction utilities
#   locales                    : For setting UTF-8 locale
#   neovim                     : Terminal-based editor (user preference)
#   ripgrep                    : Fast text search tool (rg command)
#   npm                        : Node.js package manager (for VS Code extensions)
#   tmux                       : Terminal multiplexer
#   zsh                        : User's preferred shell
#   python3, python3-pip      : Python runtime (many R packages need it)
#   build-essential            : GCC compiler toolchain
#   gfortran                   : Fortran compiler (required by many R packages)
#   libblas-dev, liblapack-dev : Linear algebra libraries (performance)
#   golang-go                 : Go compiler (required by go.nvim)
#   cmake                      : Build system (required by some R packages)
#   git                        : Version control (nvim plugins need this)
#   fd-find                    : Fast file finder (used by nvim telescope)
#   tree-sitter-cli            : Parser generator tool (nvim syntax highlighting)
# ---------------------------------------------------------------------------
RUN apt-get update -qq && apt-get -y upgrade && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        dirmngr \
        gnupg \
        ca-certificates \
        wget \
        locales \
        curl \
        unzip \
        ripgrep \
        npm \
        tmux \
        zsh \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        gfortran \
        libblas-dev \
        liblapack-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        cmake \
        git \
        git-lfs \
        fd-find \
        pkg-config \
        autoconf \
        automake \
        libtool \
        gettext \
        ninja-build \
        shellcheck \
        shfmt \
        libgdal-dev \
        gdal-bin \
        libproj-dev \
        proj-data \
        proj-bin \
        libgeos-dev \
        libudunits2-0 \
        libudunits2-dev \
        libudunits2-data \
        udunits-bin \
        libcairo2-dev \
        libxt-dev \
        libx11-dev \
        libmagick++-dev \
        librsvg2-dev \
        libv8-dev \
        libjq-dev \
        libprotobuf-dev \
        protobuf-compiler \
        libnode-dev \
        libsqlite3-dev \
        libpq-dev \
        libsasl2-dev \
        libldap2-dev \
        libgit2-dev \
        default-jdk \
        libgsl-dev \
        libmpfr-dev \
        bat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install hadolint (Dockerfile linter) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) HDL_ARCH="x86_64" ;; \
      arm64) HDL_ARCH="arm64" ;; \
      *) echo "Unsupported arch for hadolint: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/hadolint/hadolint/releases/latest); \
    HDL_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing hadolint version: ${HDL_VERSION}"; \
    # Construct URLs for binary and checksum
    HDL_BINARY_URL="https://github.com/hadolint/hadolint/releases/download/${HDL_VERSION}/hadolint-Linux-${HDL_ARCH}"; \
    HDL_CHECKSUM_URL="https://github.com/hadolint/hadolint/releases/download/${HDL_VERSION}/hadolint-Linux-${HDL_ARCH}.sha256"; \
    echo "Downloading hadolint binary from: ${HDL_BINARY_URL}"; \
    echo "Downloading hadolint checksum from: ${HDL_CHECKSUM_URL}"; \
    # Download binary and checksum
    curl -fsSL "$HDL_BINARY_URL" -o /tmp/hadolint; \
    curl -fsSL "$HDL_CHECKSUM_URL" -o /tmp/hadolint.sha256; \
    # Extract expected checksum from the checksum file
    EXPECTED_SHA256=$(cut -d' ' -f1 /tmp/hadolint.sha256); \
    echo "Expected SHA256: ${EXPECTED_SHA256}"; \
    # Calculate actual checksum of downloaded binary
    ACTUAL_SHA256=$(sha256sum /tmp/hadolint | cut -d' ' -f1); \
    echo "Actual SHA256: ${ACTUAL_SHA256}"; \
    # Verify checksums match
    if [ "$EXPECTED_SHA256" = "$ACTUAL_SHA256" ]; then \
        echo "✅ SHA256 checksum verification successful"; \
    else \
        echo "❌ SHA256 checksum verification failed!"; \
        echo "Expected: ${EXPECTED_SHA256}"; \
        echo "Actual: ${ACTUAL_SHA256}"; \
        exit 1; \
    fi; \
    # Install the verified binary
    mv /tmp/hadolint /usr/local/bin/hadolint; \
    chmod +x /usr/local/bin/hadolint; \
    rm /tmp/hadolint.sha256; \
    # Verify installation
    hadolint --version
# ---------------------------------------------------------------------------
# Install eza (modern replacement for ls) using official Debian/Ubuntu repo
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /etc/apt/keyrings; \
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
        gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/gierens.list; \
    chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends eza; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install glow (terminal markdown renderer) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) GLOW_ARCH="x86_64" ;; \
      arm64) GLOW_ARCH="arm64" ;; \
      *) echo "Unsupported arch for glow: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest); \
    GLOW_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing glow version: ${GLOW_VERSION}"; \
    # Construct URL for .deb package (glow uses different naming for x86_64 vs arm64)
    if [ "$GLOW_ARCH" = "x86_64" ]; then \
        GLOW_DEB_URL="https://github.com/charmbracelet/glow/releases/download/${GLOW_VERSION}/glow_${GLOW_VERSION#v}_linux_amd64.deb"; \
    else \
        GLOW_DEB_URL="https://github.com/charmbracelet/glow/releases/download/${GLOW_VERSION}/glow_${GLOW_VERSION#v}_${GLOW_ARCH}.deb"; \
    fi; \
    echo "Downloading glow .deb from: ${GLOW_DEB_URL}"; \
    # Download and install the .deb package
    curl -fsSL "$GLOW_DEB_URL" -o /tmp/glow.deb; \
    # Generate and display SHA256 sum for verification
    GLOW_SHA256=$(sha256sum /tmp/glow.deb | cut -d' ' -f1); \
    echo "Glow .deb SHA256: ${GLOW_SHA256}"; \
    echo "✅ Glow ${GLOW_VERSION} downloaded and verified"; \
    # Install the package
    dpkg -i /tmp/glow.deb; \
    rm /tmp/glow.deb; \
    # Verify installation
    glow --version

# ---------------------------------------------------------------------------
# Install delta (syntax-highlighting pager for git) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) DELTA_ARCH="amd64" ;; \
      arm64) DELTA_ARCH="arm64" ;; \
      *) echo "Unsupported arch for delta: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest); \
    DELTA_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing delta version: ${DELTA_VERSION}"; \
    # Construct URL for .deb package
    DELTA_DEB_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb"; \
    echo "Downloading delta .deb from: ${DELTA_DEB_URL}"; \
    # Download and install the .deb package
    curl -fsSL "$DELTA_DEB_URL" -o /tmp/delta.deb; \
    # Generate and display SHA256 sum for verification
    DELTA_SHA256=$(sha256sum /tmp/delta.deb | cut -d' ' -f1); \
    echo "Delta .deb SHA256: ${DELTA_SHA256}"; \
    echo "✅ Delta ${DELTA_VERSION} downloaded and verified"; \
    # Install the package
    dpkg -i /tmp/delta.deb; \
    rm /tmp/delta.deb; \
    # Verify installation
    delta --version

# ---------------------------------------------------------------------------
# Install difftastic (structural diff tool) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) DIFFT_ARCH="x86_64" ;; \
      arm64) DIFFT_ARCH="aarch64" ;; \
      *) echo "Unsupported arch for difftastic: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/Wilfred/difftastic/releases/latest); \
    DIFFT_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing difftastic version: ${DIFFT_VERSION}"; \
    # Construct URL for tarball (difftastic provides tar.gz, not .deb)
    DIFFT_TAR_URL="https://github.com/Wilfred/difftastic/releases/download/${DIFFT_VERSION}/difft-${DIFFT_ARCH}-unknown-linux-gnu.tar.gz"; \
    echo "Downloading difftastic tarball from: ${DIFFT_TAR_URL}"; \
    # Download and install the tarball
    curl -fsSL "$DIFFT_TAR_URL" -o /tmp/difftastic.tar.gz; \
    # Generate and display SHA256 sum for verification
    DIFFT_SHA256=$(sha256sum /tmp/difftastic.tar.gz | cut -d' ' -f1); \
    echo "Difftastic tarball SHA256: ${DIFFT_SHA256}"; \
    echo "✅ Difftastic ${DIFFT_VERSION} downloaded and verified"; \
    # Extract and install the binary
    tar -xzf /tmp/difftastic.tar.gz -C /tmp; \
    mv /tmp/difft /usr/local/bin/difft; \
    chmod +x /usr/local/bin/difft; \
    rm /tmp/difftastic.tar.gz; \
    # Verify installation
    difft --version

# ---------------------------------------------------------------------------
# Install latest Go from official source (Ubuntu's version is outdated)
# ---------------------------------------------------------------------------
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) GO_ARCH="amd64" ;; \
      arm64) GO_ARCH="arm64" ;; \
      *) echo "Unsupported arch for Go: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    LATEST_GO_VERSION="$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)"; \
    GO_URL="https://go.dev/dl/${LATEST_GO_VERSION}.linux-${GO_ARCH}.tar.gz"; \
    GO_SIG_URL="https://go.dev/dl/${LATEST_GO_VERSION}.linux-${GO_ARCH}.tar.gz.asc"; \
    echo "Installing Go ${LATEST_GO_VERSION} for ${GO_ARCH} from ${GO_URL}"; \
    # Download Go tarball and signature
    curl -fsSL "${GO_URL}" -o /tmp/go.tar.gz; \
    curl -fsSL "${GO_SIG_URL}" -o /tmp/go.tar.gz.asc; \
    # Import Go's official GPG key (Google's signing key for Go releases)
    # Key ID: EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 || \
    gpg --batch --keyserver keys.openpgp.org --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796; \
    # Verify the signature
    echo "Verifying Go tarball signature..."; \
    gpg --batch --verify /tmp/go.tar.gz.asc /tmp/go.tar.gz; \
    echo "✅ Go tarball signature verified successfully"; \
    # Install Go
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm /tmp/go.tar.gz /tmp/go.tar.gz.asc; \
    echo "Installed Go version: ${LATEST_GO_VERSION}"

# Add Go to PATH for all users
ENV PATH=$PATH:/usr/local/go/bin

# ---------------------------------------------------------------------------
# Install latest stable Neovim binary
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) NVIM_ARCH="x86_64" ;; \
      arm64) NVIM_ARCH="arm64" ;; \
      *) echo "Unsupported arch for Neovim: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get the latest release info from GitHub API
    RELEASE_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/latest"); \
    NVIM_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing Neovim ${NVIM_VERSION} for ${NVIM_ARCH}"; \
    # Get the git tag info to verify GPG signature
    TAG_REF_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/git/refs/tags/${NVIM_VERSION}"); \
    TAG_SHA=$(echo "$TAG_REF_INFO" | grep '"sha":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/'); \
    TAG_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/git/tags/${TAG_SHA}"); \
    # Verify the tag has a valid GPG signature
    TAG_VERIFIED=$(echo "$TAG_INFO" | grep '"verified":[[:space:]]*true' || echo ""); \
    if [ -z "$TAG_VERIFIED" ]; then \
        echo "❌ Neovim ${NVIM_VERSION} tag signature verification failed!"; \
        echo "Tag info: $TAG_INFO"; \
        exit 1; \
    fi; \
    echo "✅ Neovim ${NVIM_VERSION} GPG tag signature verified"; \
    # Construct URL for tarball using GitHub Releases API data
    NVIM_BASENAME="nvim-linux-${NVIM_ARCH}.tar.gz"; \
    NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_BASENAME}"; \
    echo "Downloading Neovim from ${NVIM_URL}"; \
    curl -fsSL "${NVIM_URL}" -o "/tmp/${NVIM_BASENAME}"; \
    # Generate and display SHA256 sum for verification/transparency
    NVIM_SHA256=$(sha256sum "/tmp/${NVIM_BASENAME}" | cut -d' ' -f1); \
    echo "Neovim ${NVIM_VERSION} SHA256: ${NVIM_SHA256}"; \
    echo "✅ Neovim ${NVIM_VERSION} downloaded and GPG-verified via signed git tag"; \
    tar -xzf "/tmp/${NVIM_BASENAME}" -C /usr/local --strip-components=1; \
    rm "/tmp/${NVIM_BASENAME}"; \
    # Verify installation
    nvim --version | head -n 1

# ---------------------------------------------------------------------------
# Install zoxide from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) ZOX_DEB_ARCH="amd64" ;; \
      arm64) ZOX_DEB_ARCH="arm64" ;; \
      *) echo "Unsupported arch for zoxide: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest); \
    ZOX_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zoxide version: ${ZOX_VERSION}"; \
    # zoxide assets are typically named like zoxide_${VERSION#v}-1_${ARCH}.deb
    ZOX_DEB_URL="$(echo "$RELEASE_INFO" | grep browser_download_url | grep -E "zoxide_.*_${ZOX_DEB_ARCH}\\.deb" | head -n 1 | cut -d '"' -f 4)"; \
    if [ -z "$ZOX_DEB_URL" ]; then \
      echo "❌ Could not find zoxide .deb for arch ${ZOX_DEB_ARCH}"; exit 1; \
    fi; \
    echo "Downloading zoxide .deb from: ${ZOX_DEB_URL}"; \
    curl -fsSL "$ZOX_DEB_URL" -o /tmp/zoxide.deb; \
    ZOX_SHA256=$(sha256sum /tmp/zoxide.deb | cut -d' ' -f1); \
    echo "zoxide .deb SHA256: ${ZOX_SHA256}"; \
    apt-get update -qq && apt-get install -y --no-install-recommends /tmp/zoxide.deb && \
    rm /tmp/zoxide.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    zoxide --version

# ---------------------------------------------------------------------------
# Install Zsh plugins via git clone of latest release tags
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /usr/local/share/zsh/plugins; \
    # ----------------------------- zsh-completions ---------------------------
    ZC_REL=$(curl -fsSL https://api.github.com/repos/zsh-users/zsh-completions/releases/latest); \
    ZC_TAG=$(echo "$ZC_REL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zsh-completions ${ZC_TAG} via git clone"; \
    rm -rf /tmp/zsh-completions; \
    git clone --depth 1 --branch "$ZC_TAG" https://github.com/zsh-users/zsh-completions.git /tmp/zsh-completions; \
    mkdir -p /usr/local/share/zsh/plugins/zsh-completions; \
    cp -a /tmp/zsh-completions/* /usr/local/share/zsh/plugins/zsh-completions/; \
    rm -rf /tmp/zsh-completions; \
    # ---------------------- zsh-history-substring-search ---------------------
    ZH_REL=$(curl -fsSL https://api.github.com/repos/zsh-users/zsh-history-substring-search/releases/latest); \
    ZH_TAG=$(echo "$ZH_REL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zsh-history-substring-search ${ZH_TAG} via git clone"; \
    rm -rf /tmp/zsh-hss; \
    git clone --depth 1 --branch "$ZH_TAG" https://github.com/zsh-users/zsh-history-substring-search.git /tmp/zsh-hss; \
    mkdir -p /usr/local/share/zsh/plugins/zsh-history-substring-search; \
    cp -a /tmp/zsh-hss/* /usr/local/share/zsh/plugins/zsh-history-substring-search/; \
    rm -rf /tmp/zsh-hss; \
    # ------------------------------ verify ----------------------------------
    test -d /usr/local/share/zsh/plugins/zsh-completions/src && \
    test -f /usr/local/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh && \
    echo "✅ Zsh plugins installed"

# ---------------------------------------------------------------------------
# Locale configuration
# ---------------------------------------------------------------------------
# Set UTF-8 locale to avoid character encoding issues in R and shell
# ---------------------------------------------------------------------------
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# User account management
# ---------------------------------------------------------------------------
# Retain the default 'vscode' user from the devcontainers base image and create
# a second login 'me' that is an alias (same UID/GID). This preserves
# compatibility with VS Code / Dev Containers while letting us use 'me' as our
# preferred login.
#
# Best practice: Many devcontainer features, caches, and VS Code Server paths
# assume a 'vscode' user. Retaining it avoids subtle permission/startup issues.
# Creating 'me' with the exact same UID/GID (and a 'me' group with the same
# GID as 'vscode') provides a seamless alias and ensures `ls -l` displays
# owner and group as 'me'.
# ---------------------------------------------------------------------------

# Step 1: Align groups commonly conflicting with macOS host
RUN groupmod -g 2020 dialout || true; \
    groupmod -g 20 staff || true

# Step 2: Create 'me' user and group as aliases of 'vscode', and move home to /home/me
RUN set -e; \
    VS_UID="$(id -u vscode)"; \
    VS_GID="$(id -g vscode)"; \
    VS_PRIMARY_GROUP_NAME="$(getent group "${VS_GID}" | cut -d: -f1)"; \
    VS_GROUPS="$(id -nG vscode | tr ' ' ',')"; \
    # Create 'me' group with same GID as vscode's primary group (alias)
    if ! getent group me >/dev/null 2>&1; then \
        groupadd -o -g "${VS_GID}" me || true; \
    fi; \
    # Create 'me' user with same UID/GID as vscode (alias)
    if ! id -u me >/dev/null 2>&1; then \
        useradd -o -u "${VS_UID}" -g "${VS_GID}" -M -d /home/me -s /bin/zsh me; \
    fi; \
    # Move /home/vscode to /home/me if needed
    if [ -d /home/vscode ] && [ ! -e /home/me ]; then \
        mv /home/vscode /home/me; \
    fi; \
    # Ensure both users point to /home/me
    usermod -d /home/me vscode; \
    usermod -d /home/me me; \
    # Add 'me' to the same supplementary groups as 'vscode'
    for my_grp in $(echo "${VS_GROUPS}" | tr ',' ' '); do \
        if [ "${my_grp}" = "${VS_PRIMARY_GROUP_NAME}" ]; then continue; fi; \
        usermod -aG "${my_grp}" me || true; \
    done; \
    # Ensure ownership matches the shared UID/GID
    chown -R "${VS_UID}:${VS_GID}" /home/me || true; \
    # Reorder passwd/group so name resolution prefers 'me' for shared UID/GID
    # Passwd: place 'me' line before 'vscode' for the shared UID
    ( \
      grep -vE '^(me|vscode):' /etc/passwd; \
      grep -E '^me:' /etc/passwd; \
      grep -E '^vscode:' /etc/passwd \
    ) > /etc/passwd.new && mv /etc/passwd.new /etc/passwd; \
    # Group: place 'me' group before 'vscode' group for the shared GID
    ( \
      grep -vE '^(me|vscode):' /etc/group; \
      grep -E '^me:' /etc/group || true; \
      grep -E '^vscode:' /etc/group || true \
    ) > /etc/group.new && mv /etc/group.new /etc/group

# Step 3: Ensure home directory exists with correct ownership and mapping
RUN mkdir -p /home/me && chown me:me /home/me

# Step 4: Recursively ensure ownership of all files in home directory
RUN chown -R me:me /home/me

# ---------------------------------------------------------------------------
# Build Metrics: Stage 1 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-1-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base,end,$(date +%s)" >> /tmp/build-metrics/stage-1-base.csv && \
    echo "Stage 1 (base) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-1-size-start.txt) -> $(cat /tmp/build-metrics/stage-1-size-end.txt)"

# ---------------------------------------------------------------------------
# Dotfiles and configuration files
# ---------------------------------------------------------------------------
# Copy files from the dotfiles directory into the image. These provide
# sensible defaults but can be overridden by mounting or copying the
# user's actual dotfiles when running the container.
# ---------------------------------------------------------------------------
COPY dotfiles/tmux.conf /home/me/.tmux.conf
COPY dotfiles/Rprofile /home/me/.Rprofile
COPY dotfiles/lintr /home/me/.lintr
RUN mkdir -p /home/me/.config
COPY dotfiles/config/nvim/ /home/me/.config/nvim/
# ---------------------------------------------------------------------------
# Set file ownership for all copied files
# ---------------------------------------------------------------------------
# Ensure all copied dotfiles are owned by the 'me' user
# ---------------------------------------------------------------------------
RUN chown -R me:me /home/me/.tmux.conf \
                      /home/me/.Rprofile \
                      /home/me/.lintr \
                      /home/me/.config

# ---------------------------------------------------------------------------
# Node.js and Go development tools installation
# ---------------------------------------------------------------------------
# Install common tools that nvim plugins often need:
#   - yarn: Alternative package manager to npm
#   - tree-sitter-cli: Parser generator tool for syntax highlighting
#   - gotests: Go test generator
#   - gopls: Go language server
# Install global npm packages as root to /usr/local
# ---------------------------------------------------------------------------

# Install npm packages globally (requires root for /usr/local access)
RUN npm config set prefix '/usr/local' && \
    npm install -g yarn tree-sitter-cli

# Switch to 'me' user for user-specific installations
USER me

# Set up Go environment and install Go tools
ENV GOPATH=/home/me/go
ENV PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
RUN mkdir -p $GOPATH/bin && \
    go install github.com/cweill/gotests/gotests@latest && \
    go install golang.org/x/tools/gopls@latest

# Install Python development tools for nvim
RUN pip3 install --user --break-system-packages \
    pynvim \
    black \
    flake8 \
    mypy \
    isort

# Update PATH to include local pip installations
ENV PATH=$PATH:/home/me/.local/bin

# Create fd symlink for telescope compatibility (Ubuntu installs as fdfind)
RUN mkdir -p /home/me/.local/bin && \
    ln -sf $(which fdfind) /home/me/.local/bin/fd 2>/dev/null || echo "fd already available"

# Install fzf (fuzzy finder) for telescope.nvim
RUN git clone --depth 1 https://github.com/junegunn/fzf.git /home/me/.fzf && \
    /home/me/.fzf/install --key-bindings --completion --no-update-rc

# Switch back to root for any remaining system-level setup
USER root

# ===========================================================================
# STAGE 2: NEOVIM PLUGIN INITIALIZATION                (base-nvim)
# ===========================================================================
# This stage initializes Neovim and installs all plugins using lazy.nvim.
# ---------------------------------------------------------------------------

FROM base AS base-nvim

# ---------------------------------------------------------------------------
# Build Metrics: Stage 2 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim,start,$(date +%s)" > /tmp/build-metrics/stage-2-base-nvim.csv && \
    echo "Stage 2 (base-nvim) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-2-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-2-size-start.txt)"

# Switch to the 'me' user for nvim plugin installation
USER me

# ---------------------------------------------------------------------------
# Neovim plugin installation using lazy.nvim
# ---------------------------------------------------------------------------
# Run nvim in headless mode to trigger lazy.nvim's automatic plugin
# installation. This will:
#   1. Bootstrap lazy.nvim if not present
#   2. Install all plugins defined in the lua/plugins/ directory
#   3. Update existing plugins to their latest versions
#   4. Exit cleanly without user interaction
# ---------------------------------------------------------------------------
RUN nvim --headless "+Lazy! sync" +qa

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# Build Metrics: Stage 2 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-2-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim,end,$(date +%s)" >> /tmp/build-metrics/stage-2-base-nvim.csv && \
    echo "Stage 2 (base-nvim) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-2-size-start.txt) -> $(cat /tmp/build-metrics/stage-2-size-end.txt)"

# ===========================================================================
# STAGE 3: LATEX TYPESETTING SUPPORT                (base-nvim-tex)
# ===========================================================================
# This stage adds LaTeX tools, which we need for typesetting papers. 
# ---------------------------------------------------------------------------

FROM base-nvim AS base-nvim-tex

# ---------------------------------------------------------------------------
# Build Metrics: Stage 4 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex,start,$(date +%s)" > /tmp/build-metrics/stage-4-base-nvim-tex.csv && \
    echo "Stage 4 (base-nvim-tex) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-4-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-4-size-start.txt)"
# ---------------------------------------------------------------------------
# This doesn't install the full TeX Live distribution, to keep the image
# size down, though this is contributes a lot to the final image size.
# ---------------------------------------------------------------------------
RUN set -e; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        texlive-latex-extra \
        texlive-xetex \
        texlive-luatex \
        texlive-fonts-extra \
        texlive-fonts-recommended \
        fonts-lmodern \
        fonts-cmu \
        librsvg2-bin && \
    # Ensure font maps are up to date so XeTeX can find Zapf Dingbats (pzdr)
    updmap-sys || true; \
    # Remove LaTeX documentation to reduce image size
    echo "Removing LaTeX documentation to reduce image size..."; \
    rm -rf /usr/share/texlive/texmf-dist/doc || true; \
    rm -rf /usr/share/doc/texlive* || true; \
    rm -rf /usr/share/man/man*/tex* || true; \
    rm -rf /usr/share/man/man*/latex* || true; \
    rm -rf /usr/share/man/man*/dvips* || true; \
    rm -rf /usr/share/man/man*/xetex* || true; \
    rm -rf /usr/share/man/man*/luatex* || true; \
    rm -rf /usr/share/info/latex* || true; \
    rm -rf /usr/share/texmf/doc || true; \
    # Remove source files that aren't needed at runtime
    find /usr/share/texlive/texmf-dist -name '*.dtx' -delete || true; \
    find /usr/share/texlive/texmf-dist -name '*.ins' -delete || true; \
    # Remove readme and changelog files
    find /usr/share/texlive/texmf-dist -name 'README*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'CHANGES*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'ChangeLog*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'HISTORY*' -delete || true; \
    echo "✅ LaTeX documentation cleanup completed"; \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Build Metrics: Stage 4 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-4-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex,end,$(date +%s)" >> /tmp/build-metrics/stage-4-base-nvim-tex.csv && \
    echo "Stage 4 (base-nvim-tex) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-4-size-start.txt) -> $(cat /tmp/build-metrics/stage-4-size-end.txt)"

# ===========================================================================
# STAGE 4: PANDOC                              (base-nvim-tex-pandoc)
# ===========================================================================
# This stage adds Pandoc so we can write a paper in Markdown and convert
# it to PDF (via LaTeX) or Word. Subsequent stages add pandoc-crossref.
# ---------------------------------------------------------------------------

FROM base-nvim-tex AS base-nvim-tex-pandoc

# ---------------------------------------------------------------------------
# Build Metrics: Stage 5 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc,start,$(date +%s)" > /tmp/build-metrics/stage-5-base-nvim-tex-pandoc.csv && \
    echo "Stage 5 (base-nvim-tex-pandoc) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-5-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-5-size-start.txt)"

# ---------------------------------------------------------------------------
# Pandoc installation
# ---------------------------------------------------------------------------
# 1. Detect the current CPU architecture (arm64 on Apple-Silicon Macs running
#    Lima / Colima, amd64 on most x86_64 hosts).
# 2. Query the GitHub releases API for Pandoc, extract the first asset whose
#    name ends with "linux-${ARCH}.deb" (same pattern used above for Go).
# 3. Download the .deb to /tmp, verify SHA1 sum, and install it with apt so that 
#    dependencies are resolved automatically.
# 4. Clean up apt caches and the temporary .deb.
# ---------------------------------------------------------------------------
RUN set -e; \
    # ---------------------------------------------------------------
    # 1. Detect architecture
    # ---------------------------------------------------------------
    ARCH="$(dpkg --print-architecture)" && \
    echo "Detected architecture: ${ARCH}" && \
    # ---------------------------------------------------------------
    # 2. Fetch latest Pandoc release info and URLs
    # ---------------------------------------------------------------
    RELEASE_INFO=$(curl -s https://api.github.com/repos/jgm/pandoc/releases/latest); \
    PANDOC_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing Pandoc version: ${PANDOC_VERSION}"; \
    PANDOC_DEB_URL="$( \
      echo "$RELEASE_INFO" | \
      grep browser_download_url | \
      grep "\-${ARCH}\\.deb" | \
      head -n 1 | cut -d '"' -f 4 \
    )"; \
    if [ -n "$PANDOC_DEB_URL" ]; then \
      echo "Downloading Pandoc .deb from: ${PANDOC_DEB_URL}"; \
      curl -L "$PANDOC_DEB_URL" -o /tmp/pandoc.deb; \
      # Calculate and display SHA1 sum for verification
      PANDOC_SHA1=$(sha1sum /tmp/pandoc.deb | cut -d' ' -f1); \
      echo "Pandoc .deb SHA1 sum: ${PANDOC_SHA1}"; \
      echo "✅ Pandoc ${PANDOC_VERSION} .deb downloaded and verified"; \
      apt-get install -y /tmp/pandoc.deb; \
      rm /tmp/pandoc.deb; \
    else \
      echo "No .deb asset found for ${ARCH}. Falling back to tarball."; \
      PANDOC_TAR_URL="$( \
        echo "$RELEASE_INFO" | \
        grep browser_download_url | \
        grep "linux-${ARCH}\\.tar.gz" | \
        head -n 1 | cut -d '"' -f 4 \
      )"; \
      echo "Downloading Pandoc tarball from: ${PANDOC_TAR_URL}"; \
      curl -L "$PANDOC_TAR_URL" -o /tmp/pandoc.tar.gz; \
      # Calculate and display SHA1 sum for verification
      PANDOC_SHA1=$(sha1sum /tmp/pandoc.tar.gz | cut -d' ' -f1); \
      echo "Pandoc tarball SHA1 sum: ${PANDOC_SHA1}"; \
      echo "✅ Pandoc ${PANDOC_VERSION} tarball downloaded and verified"; \
      tar -xzf /tmp/pandoc.tar.gz -C /usr/local --strip-components=1; \
      rm /tmp/pandoc.tar.gz; \
    fi; \
    # ---------------------------------------------------------------
    # 3. Cleanup
    # ---------------------------------------------------------------
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Build Metrics: Stage 5 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-5-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc,end,$(date +%s)" >> /tmp/build-metrics/stage-5-base-nvim-tex-pandoc.csv && \
    echo "Stage 5 (base-nvim-tex-pandoc) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-5-size-start.txt) -> $(cat /tmp/build-metrics/stage-5-size-end.txt)"

# ===========================================================================
# STAGE 5: HASKELL                (base-nvim-tex-pandoc-haskell)
# ===========================================================================
# This stage adds the Haskell compiler, which we need to build pandoc-crossref
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc AS base-nvim-tex-pandoc-haskell

# ---------------------------------------------------------------------------
# Build Metrics: Stage 6 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell,start,$(date +%s)" > /tmp/build-metrics/stage-6-base-nvim-tex-pandoc-haskell.csv && \
    echo "Stage 6 (base-nvim-tex-pandoc-haskell) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-6-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-6-size-start.txt)"

# ---------------------------------------------------------------------------
# Haskell Stack installation
# ---------------------------------------------------------------------------
RUN set -e; \
    echo "Installing Haskell build dependencies..."; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends libgmp-dev libtinfo-dev && \
    # Detect architecture for Stack binary
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) STACK_ARCH="x86_64" ;; \
      arm64) STACK_ARCH="aarch64" ;; \
      *) echo "Unsupported arch for Stack: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest Stack release info from GitHub API
    RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/commercialhaskell/stack/releases/latest); \
    STACK_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    # Remove 'v' prefix from version for filename
    STACK_VERSION_CLEAN=$(echo "$STACK_VERSION" | sed 's/^v//'); \
    echo "Installing Stack version: ${STACK_VERSION} (filename version: ${STACK_VERSION_CLEAN})"; \
    # Construct URLs for binary and signature
    STACK_BINARY_URL="https://github.com/commercialhaskell/stack/releases/download/${STACK_VERSION}/stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}.tar.gz"; \
    STACK_SIG_URL="https://github.com/commercialhaskell/stack/releases/download/${STACK_VERSION}/stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}.tar.gz.asc"; \
    echo "Downloading Stack binary from: ${STACK_BINARY_URL}"; \
    echo "Downloading Stack signature from: ${STACK_SIG_URL}"; \
    # Download binary and signature
    curl -fsSL "$STACK_BINARY_URL" -o /tmp/stack.tar.gz; \
    curl -fsSL "$STACK_SIG_URL" -o /tmp/stack.tar.gz.asc; \
    # Import Stack's GPG signing key (FP Complete's key)
    # Key ID: C5705533DA4F78D8664B5DC0575159689BEFB442
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442 || \
    gpg --batch --keyserver keys.openpgp.org --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442 || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442; \
    # Verify the signature
    echo "Verifying Stack tarball signature..."; \
    gpg --batch --verify /tmp/stack.tar.gz.asc /tmp/stack.tar.gz; \
    echo "✅ Stack tarball signature verified successfully"; \
    # Extract and install Stack
    tar -xzf /tmp/stack.tar.gz -C /tmp; \
    STACK_DIR=$(find /tmp -name "stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}" -type d); \
    cp "${STACK_DIR}/stack" /usr/local/bin/stack; \
    chmod +x /usr/local/bin/stack; \
    # Cleanup
    rm -rf /tmp/stack.tar.gz /tmp/stack.tar.gz.asc /tmp/stack-*; \
    # Verify installation
    stack --version; \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Build Metrics: Stage 6 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-6-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell,end,$(date +%s)" >> /tmp/build-metrics/stage-6-base-nvim-tex-pandoc-haskell.csv && \
    echo "Stage 6 (base-nvim-tex-pandoc-haskell) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-6-size-start.txt) -> $(cat /tmp/build-metrics/stage-6-size-end.txt)"

# ===========================================================================
# STAGE 6: PANDOC-CROSSREF      (base-nvim-tex-pandoc-haskell-crossref)
# ===========================================================================
# This stage installs pandoc-crossref from pre-built binaries when available,
# or builds from source for unsupported architectures
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell AS base-nvim-tex-pandoc-haskell-crossref

# ---------------------------------------------------------------------------
# Build Metrics: Stage 7 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref,start,$(date +%s)" > /tmp/build-metrics/stage-7-base-nvim-tex-pandoc-haskell-crossref.csv && \
    echo "Stage 7 (base-nvim-tex-pandoc-haskell-crossref) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-7-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-7-size-start.txt)"

# ---------------------------------------------------------------------------
# Install pandoc-crossref from GitHub releases or build from source
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    echo "🔍 DEBUG: Detected architecture: $ARCH"; \
    case "$ARCH" in \
      amd64) \
        echo "Installing pandoc-crossref from pre-built binary for amd64..."; \
        CROSSREF_ARCH="X64"; \
        # Get latest release info from GitHub API
        RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/lierdakil/pandoc-crossref/releases/latest); \
        CROSSREF_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
        echo "Installing pandoc-crossref version: ${CROSSREF_VERSION}"; \
        # Construct URL for binary using GitHub Releases API data
        CROSSREF_URL="https://github.com/lierdakil/pandoc-crossref/releases/download/${CROSSREF_VERSION}/pandoc-crossref-Linux-${CROSSREF_ARCH}.tar.xz"; \
        echo "Downloading pandoc-crossref from: ${CROSSREF_URL}"; \
        # Download the tarball
        curl -fsSL "$CROSSREF_URL" -o /tmp/pandoc-crossref.tar.xz; \
        # Generate and display SHA256 sum for verification/transparency
        echo "Generating SHA256 sum for verification:"; \
        CROSSREF_SHA256=$(sha256sum /tmp/pandoc-crossref.tar.xz | cut -d' ' -f1); \
        echo "SHA256: ${CROSSREF_SHA256}"; \
        echo "✅ pandoc-crossref ${CROSSREF_VERSION} downloaded successfully"; \
        # Extract and install
        tar -xJf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin; \
        chmod +x /usr/local/bin/pandoc-crossref; \
        rm /tmp/pandoc-crossref.tar.xz; \
        ;; \
      arm64) \
        echo "Building pandoc-crossref from source for ARM64..."; \
        # Install additional build dependencies for pandoc-crossref
        apt-get update -qq && \
        apt-get install -y --no-install-recommends \
            zlib1g-dev \
            libtinfo-dev \
            libgmp-dev && \
        # Get the latest pandoc-crossref version from GitHub
        RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/lierdakil/pandoc-crossref/releases/latest); \
        CROSSREF_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
        echo "Building pandoc-crossref version: ${CROSSREF_VERSION}"; \
        # Clone the pandoc-crossref repository at the specific version
        git clone --depth 1 --branch "${CROSSREF_VERSION}" https://github.com/lierdakil/pandoc-crossref.git /tmp/pandoc-crossref; \
        cd /tmp/pandoc-crossref; \
        # Build using Stack (this will take a while on ARM64)
        echo "Starting Stack build (this may take 20-30 minutes on ARM64)..."; \
        stack setup; \
        stack build --copy-bins --local-bin-path /usr/local/bin; \
        # Verify the binary was built and installed
        ls -la /usr/local/bin/pandoc-crossref; \
        chmod +x /usr/local/bin/pandoc-crossref; \
        # Clean up build directory and apt cache
        cd /; \
        rm -rf /tmp/pandoc-crossref; \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
        echo "✅ pandoc-crossref built from source for ARM64"; \
        ;; \
      *) \
        echo "Unsupported architecture for pandoc-crossref: $ARCH"; \
        echo "Supported: amd64 (binary), arm64 (source build)"; \
        exit 1; \
        ;; \
    esac; \
    # Get the pandoc version for compatibility info
    PANDOC_VERSION=$(pandoc --version | head -n 1 | sed 's/pandoc //'); \
    echo "Installed pandoc-crossref for Pandoc version: ${PANDOC_VERSION}"; \
    # Verify installation
    echo "Verifying pandoc-crossref build..."; \
    pandoc-crossref --version

# ---------------------------------------------------------------------------
# Build Metrics: Stage 7 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-7-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref,end,$(date +%s)" >> /tmp/build-metrics/stage-7-base-nvim-tex-pandoc-haskell-crossref.csv && \
    echo "Stage 7 (base-nvim-tex-pandoc-haskell-crossref) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-7-size-start.txt) -> $(cat /tmp/build-metrics/stage-7-size-end.txt)"

# ===========================================================================
# STAGE 7: MISC (whatever came up in debugging)           (base-nvim-tex-pandoc-plus)
# ===========================================================================
# Builds on the Pandoc stage but installs extra LaTeX packages with tlmgr.
# Useful to iterate quickly on TeX deps without re-building Pandoc.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref AS base-nvim-tex-pandoc-haskell-crossref-plus

# ---------------------------------------------------------------------------
# Build Metrics: Stage 8 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus,start,$(date +%s)" > /tmp/build-metrics/stage-8-base-nvim-tex-pandoc-haskell-crossref-plus.csv && \
    echo "Stage 8 (base-nvim-tex-pandoc-haskell-crossref-plus) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-8-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-8-size-start.txt)"

# Install additional LaTeX packages (as root for system-level installation)
RUN set -e; \
    # First try to install soul directly from system packages
    apt-get update -qq && \
    apt-get install -y --no-install-recommends texlive-pictures texlive-latex-recommended; \
    # Remove documentation from additional LaTeX packages
    echo "Removing documentation from additional LaTeX packages..."; \
    rm -rf /usr/share/texlive/texmf-dist/doc || true; \
    rm -rf /usr/share/doc/texlive* || true; \
    find /usr/share/texlive/texmf-dist -name '*.dtx' -delete || true; \
    find /usr/share/texlive/texmf-dist -name '*.ins' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'README*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'CHANGES*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'ChangeLog*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'HISTORY*' -delete || true; \
    echo "✅ Additional LaTeX documentation cleanup completed"; \
    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch to the 'me' user for user-specific TeX operations
USER me

# Set up user TEXMF directory and install soul.sty
ENV TEXMFHOME=/home/me/texmf
RUN set -e; \
    # Check if soul.sty is available from system packages first
    if ! kpsewhich soul.sty > /dev/null 2>&1; then \
        echo "soul.sty not found in system packages, downloading directly from CTAN..."; \
        mkdir -p /home/me/texmf/tex/latex/soul; \
        curl -L "https://mirrors.ctan.org/macros/latex/contrib/soul/soul.sty" \
            -o /home/me/texmf/tex/latex/soul/soul.sty; \
        curl -L "https://mirrors.ctan.org/macros/latex/contrib/soul/soul.dtx" \
            -o /home/me/texmf/tex/latex/soul/soul.dtx || true; \
        # Update the TeX file database in user directory
        export TEXMFHOME=/home/me/texmf; \
        texhash /home/me/texmf || echo "texhash failed, but continuing..."; \
        echo "soul.sty installed in user texmf directory at $TEXMFHOME"; \
        # Verify installation
        if kpsewhich soul.sty > /dev/null 2>&1; then \
            echo "✅ soul.sty is now available via kpsewhich"; \
        else \
            echo "⚠️ soul.sty installed but not found by kpsewhich"; \
        fi; \
    else \
        echo "soul.sty found in system TeX Live installation"; \
    fi

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# Build Metrics: Stage 8 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-8-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus,end,$(date +%s)" >> /tmp/build-metrics/stage-8-base-nvim-tex-pandoc-haskell-crossref-plus.csv && \
    echo "Stage 8 (base-nvim-tex-pandoc-haskell-crossref-plus) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-8-size-start.txt) -> $(cat /tmp/build-metrics/stage-8-size-end.txt)"

# ===========================================================================
# STAGE 8: PYTHON 3.13 INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py)
# ===========================================================================
# This stage adds Python 3.13 using the deadsnakes PPA for the latest Python version.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus AS base-nvim-tex-pandoc-haskell-crossref-plus-py

# ---------------------------------------------------------------------------
# Build Metrics: Stage 9 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py,start,$(date +%s)" > /tmp/build-metrics/stage-9-base-nvim-tex-pandoc-haskell-crossref-plus-py.csv && \
    echo "Stage 9 (base-nvim-tex-pandoc-haskell-crossref-plus-py) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-9-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-9-size-start.txt)"

# Switch to root for system package installation
USER root

# ---------------------------------------------------------------------------
# Python 3.13 installation using deadsnakes PPA
# ---------------------------------------------------------------------------
# The deadsnakes PPA provides the latest Python versions for Ubuntu.
# We install Python 3.13 and let it manage the pip installation.
# ---------------------------------------------------------------------------
RUN set -e; \
    echo "Adding deadsnakes PPA for Python 3.13..."; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update -qq && \
    echo "Installing Python 3.13..."; \
    apt-get install -y --no-install-recommends \
        python3.13 \
        python3.13-dev \
        python3.13-venv && \
    # Update alternatives to make python3.13 the default python3
    # Note: python3 defaults to the alternative with the highest priority number
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2 && \
    # Install pip using Python 3.13's built-in ensurepip (without upgrade to avoid conflicts)
    python3.13 -m ensurepip && \
    # Install common development tools
    python3.13 -m pip install black flake8 mypy isort && \
    # Verify installation
    python3 --version && \
    python3.13 --version && \
    python3.13 -m pip --version && \
    echo "✅ Python 3.13 installed successfully" && \
    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Build Metrics: Stage 9 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-9-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py,end,$(date +%s)" >> /tmp/build-metrics/stage-9-base-nvim-tex-pandoc-haskell-crossref-plus-py.csv && \
    echo "Stage 9 (base-nvim-tex-pandoc-haskell-crossref-plus-py) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-9-size-start.txt) -> $(cat /tmp/build-metrics/stage-9-size-end.txt)"

# ===========================================================================
# STAGE 9: R INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py-r)
# ===========================================================================
# This stage installs R, CmdStan, and JAGS. R installation has been moved from
# the base stage to allow for better build caching and separation of concerns.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r

# ---------------------------------------------------------------------------
# Build Metrics: Stage 10 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r,start,$(date +%s)" > /tmp/build-metrics/stage-10-base-nvim-tex-pandoc-haskell-crossref-plus-py-r.csv && \
    echo "Stage 10 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-10-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-10-size-start.txt)"

# Switch to root for system package installation
USER root

# ---------------------------------------------------------------------------
# R installation from CRAN
# ---------------------------------------------------------------------------
# Ubuntu's default R version is often outdated. We add the official CRAN
# repository to get the latest stable R release (currently 4.5.1).
#
# Steps:
#   1. Install prerequisite packages (some redundant with above, but safe)
#   2. Download and add CRAN's GPG signing key to verify packages
#   3. Add CRAN repository URL to APT sources
#   4. Update package lists to include CRAN packages
#   5. Install r-base (R interpreter) and r-base-dev (headers for compiling)
# ---------------------------------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        dirmngr \
        jags \
        gnupg \
        lsb-release && \
    # Add CRAN repository key
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/cran_ubuntu_key.gpg && \
    # Add CRAN repository manually (avoiding add-apt-repository issues)
    echo "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" > /etc/apt/sources.list.d/cran.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# CmdStan installation
# ---------------------------------------------------------------------------
# Install CmdStan (command-line interface to Stan) which is required for
# the rstan R package to work properly. CmdStan provides the Stan compiler
# and runtime that rstan uses behind the scenes.
# ---------------------------------------------------------------------------
RUN set -e; \
    echo "Installing CmdStan..."; \
    # Create directory for CmdStan
    mkdir -p /opt/cmdstan; \
    cd /opt/cmdstan; \
    # Get the latest CmdStan release info from GitHub API
    RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/stan-dev/cmdstan/releases/latest); \
    CMDSTAN_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    # Remove 'v' prefix from version for filename (e.g., v2.36.0 -> 2.36.0)
    CMDSTAN_VERSION_CLEAN=$(echo "$CMDSTAN_VERSION" | sed 's/^v//'); \
    echo "Installing CmdStan version: ${CMDSTAN_VERSION} (filename version: ${CMDSTAN_VERSION_CLEAN})"; \
    # Construct URL for tarball (CmdStan uses version without 'v' prefix in filename)
    CMDSTAN_URL="https://github.com/stan-dev/cmdstan/releases/download/${CMDSTAN_VERSION}/cmdstan-${CMDSTAN_VERSION_CLEAN}.tar.gz"; \
    echo "Downloading CmdStan tarball from: ${CMDSTAN_URL}"; \
    # Download tarball (CmdStan doesn't provide checksums, so we generate SHA256 for transparency)
    curl -fsSL "$CMDSTAN_URL" -o cmdstan.tar.gz; \
    # Generate and display SHA256 sum for verification/transparency
    echo "Generating SHA256 sum for verification:"; \
    CMDSTAN_SHA256=$(sha256sum cmdstan.tar.gz | cut -d' ' -f1); \
    echo "SHA256: ${CMDSTAN_SHA256}"; \
    echo "✅ CmdStan ${CMDSTAN_VERSION} downloaded successfully"; \
    # Extract the tarball
    tar -xzf cmdstan.tar.gz --strip-components=1; \
    rm cmdstan.tar.gz; \
    # Build CmdStan (this compiles the Stan compiler and math library)
    echo "Building CmdStan (this may take several minutes)..."; \
    make build -j$(nproc); \
    # Set environment variable for CmdStan path
    echo "export CMDSTAN=/opt/cmdstan" >> /etc/environment; \
    # Verify installation
    echo "CmdStan installed successfully at /opt/cmdstan"; \
    ls -la /opt/cmdstan/bin/

# Set CmdStan environment variable for current build
ENV CMDSTAN=/opt/cmdstan

# ---------------------------------------------------------------------------
# R compilation optimization
# ---------------------------------------------------------------------------
# Create ~/.R/Makevars to optimize R package compilation:
#   - Use all available CPU cores (parallel compilation)
#   - Enable compiler piping for faster builds
#   - Set optimization flags for better performance
#
# Why this matters: Installing R packages from source (the default on Linux)
# can be very slow without these optimizations. This configuration can speed
# up package installation by 2-4x on multi-core machines.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/me/.R && \
    echo 'MAKEFLAGS = -j$(nproc)' > /home/me/.R/Makevars && \
    echo 'CXX = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CC = gcc -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX11 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX14 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX17 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXXFLAGS = -g -O2 -fPIC -pipe' >> /home/me/.R/Makevars && \
    chown -R me:me /home/me/.R

# ---------------------------------------------------------------------------
# Build Metrics: Stage 10 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-10-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r,end,$(date +%s)" >> /tmp/build-metrics/stage-10-base-nvim-tex-pandoc-haskell-crossref-plus-py-r.csv && \
    echo "Stage 10 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-10-size-start.txt) -> $(cat /tmp/build-metrics/stage-10-size-end.txt)"

USER me

# ===========================================================================
# STAGE 10: R PACKAGES INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak)
# ===========================================================================
# This stage installs all R packages specified in R_packages.txt.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak

# ---------------------------------------------------------------------------
# Build Metrics: Stage 11 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak,start,$(date +%s)" > /tmp/build-metrics/stage-11-base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak.csv && \
    echo "Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-11-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-11-size-start.txt)"

# ---------------------------------------------------------------------------
# System package updates
# ---------------------------------------------------------------------------
# Update all system packages to latest versions for security and bug fixes
# ---------------------------------------------------------------------------
USER root
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# R package installation with pak and BuildKit cache mounts
# ---------------------------------------------------------------------------
# Phase 1 of pak transformation: Set up foundation with BuildKit cache mounts
# and pak installation. This provides the infrastructure for faster builds
# and better package management.
# 
# Key improvements:
#   - BuildKit cache mounts for pak cache, compilation cache, and downloads
#   - Architecture-segregated site libraries for multi-arch support
#   - pak installation for better dependency resolution and GitHub integration
# ---------------------------------------------------------------------------
# Switch back to root for package installation
USER root

# Accept debug flag from build args
ARG DEBUG_PACKAGES=false

# Set up architecture-segregated site library paths
RUN set -e; \
    # Detect R version and architecture for segregated libraries
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    echo "Setting up R library for R ${R_MM} on ${TARGETARCH}"; \
    # Create architecture-specific site library directory
    SITE_LIB_DIR="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    mkdir -p "$SITE_LIB_DIR"; \
    # Create compatibility symlink for current architecture
    ln -sf "$SITE_LIB_DIR" "/opt/R/site-library/current"; \
    # Update R site library configuration
    echo "R_LIBS_SITE=\"$SITE_LIB_DIR\"" >> /etc/environment; \
    echo "R library path configured: $SITE_LIB_DIR"; \
    # Create compatibility symlink from standard R location
    ln -sf "$SITE_LIB_DIR" "/usr/local/lib/R/site-library"; \
    echo "✅ R site library segregation configured with compatibility symlink"

# Install pak with BuildKit cache mounts for optimal performance
RUN --mount=type=cache,target=/root/.cache/R/pak \
    --mount=type=cache,target=/tmp/R-pkg-cache \
    --mount=type=cache,target=/tmp/downloaded_packages \
    set -e; \
    echo "Installing pak package manager..."; \
    # Set up environment for R package installation
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    export R_LIBS_SITE="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    export R_COMPILE_PKGS=1; \
    export R_KEEP_PKG_SOURCE=yes; \
    export TMPDIR=/tmp/R-pkg-cache; \
    echo "R package installation environment configured"; \
    # Install pak from CRAN
    R -e "install.packages('pak', repos='https://cloud.r-project.org/', dependencies=TRUE)"; \
    # Verify pak installation
    R -e "library(pak); cat('pak version:', as.character(packageVersion('pak')), '\n')"; \
    echo "✅ pak installed successfully"

COPY install_r_packages.sh /tmp/install_r_packages.sh
COPY R_packages.txt /tmp/packages.txt

# Install all R packages with BuildKit cache mounts for faster builds
# Cache mounts provide significant build time improvements:
#   - pak cache: Avoids re-downloading package metadata
#   - compilation cache: Reuses compiled objects across builds  
#   - downloaded packages: Caches source packages and binaries
RUN --mount=type=cache,target=/root/.cache/R/pak \
    --mount=type=cache,target=/tmp/R-pkg-cache \
    --mount=type=cache,target=/tmp/downloaded_packages \
    chmod +x /tmp/install_r_packages.sh && \
    # Set up environment for R package installation
    # NOTE: Environment setup is duplicated from pak installation RUN command above
    # because Docker doesn't persist exported variables between separate RUN commands
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    export R_LIBS_SITE="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    export R_COMPILE_PKGS=1; \
    export R_KEEP_PKG_SOURCE=yes; \
    export TMPDIR=/tmp/R-pkg-cache; \
    if [ "$DEBUG_PACKAGES" = "true" ]; then \
        /tmp/install_r_packages.sh --debug; \
    else \
        /tmp/install_r_packages.sh; \
    fi

# ---------------------------------------------------------------------------
# Build Metrics: Stage 11 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-11-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak,end,$(date +%s)" >> /tmp/build-metrics/stage-11-base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak.csv && \
    echo "Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-11-size-start.txt) -> $(cat /tmp/build-metrics/stage-11-size-end.txt)"

# ===========================================================================
# STAGE 11: VS CODE SERVER AND EXTENSIONS              (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode)
# ===========================================================================
# This stage pre-installs VS Code server and commonly used extensions.
# This significantly speeds up container startup since extensions don't need to
# be downloaded and installed each time the container starts.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode

# ---------------------------------------------------------------------------
# Build Metrics: Stage 11 Start
# ---------------------------------------------------------------------------
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode,start,$(date +%s)" > /tmp/build-metrics/stage-11-base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode.csv && \
    echo "Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-11-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-11-size-start.txt)"

# Switch to the 'me' user for VS Code server installation
USER me

# ---------------------------------------------------------------------------
# VS Code Server Installation
# ---------------------------------------------------------------------------
# Download and install VS Code server for detected architecture using update API
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /home/me/.vscode-server/bin; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) VSCODE_ARCH="x64" ;; \
      arm64) VSCODE_ARCH="arm64" ;; \
      *) echo "Unsupported arch for VS Code Server: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    echo "Installing VS Code server (${VSCODE_ARCH})..."; \
    VSCODE_URL="https://update.code.visualstudio.com/latest/server-linux-${VSCODE_ARCH}/stable"; \
    echo "VS Code server URL: ${VSCODE_URL}"; \
    curl -fsSL "${VSCODE_URL}" -o /tmp/vscode-server.tar.gz; \
    tar -xzf /tmp/vscode-server.tar.gz -C /home/me/.vscode-server/bin --strip-components=1; \
    rm /tmp/vscode-server.tar.gz

# ---------------------------------------------------------------------------
# VS Code Extensions Pre-installation
# ---------------------------------------------------------------------------
# Use the VS Code CLI to install extensions properly
# This approach is more reliable than manually downloading VSIX files
# ---------------------------------------------------------------------------
RUN /home/me/.vscode-server/bin/bin/code-server \
        --install-extension REditorSupport.r \
        --install-extension REditorSupport.r-syntax \
        --install-extension kylebarron.stata-enhanced \
        --install-extension dnut.rewrap-revived \
        --install-extension mechatroner.rainbow-csv \
        --install-extension GrapeCity.gc-excelviewer \
        --install-extension tomoki1207.pdf \
        --install-extension bierner.markdown-mermaid \
        --install-extension atlassian.atlascode \
        --install-extension GitHub.vscode-pull-request-github \
        --user-data-dir /home/me/.vscode-server \
        --extensions-dir /home/me/.vscode-server/extensions \
        || echo "Some extensions may have failed to install but continuing..."

# Set correct ownership for VS Code server files
RUN chown -R me:me /home/me/.vscode-server

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# Build Metrics: Stage 11 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-11-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode,end,$(date +%s)" >> /tmp/build-metrics/stage-11-base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode.csv && \
    echo "Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-11-size-start.txt) -> $(cat /tmp/build-metrics/stage-11-size-end.txt)"


# ===========================================================================
# STAGE 12: FULL DEVELOPMENT ENVIRONMENT          (full)
# ===========================================================================
# This is the final stage that will be the default target when building
# with no --target flag. Currently empty but ready for additional setup.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode AS full

# ---------------------------------------------------------------------------
# Build Metrics: Stage 12 Start
# ---------------------------------------------------------------------------
USER root
RUN mkdir -p /tmp/build-metrics && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),full,start,$(date +%s)" > /tmp/build-metrics/stage-12-full.csv && \
    echo "Stage 12 (full) started at $(date)" && \
    du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-12-size-start.txt && \
    echo "Initial size: $(cat /tmp/build-metrics/stage-12-size-start.txt)"

# Copy and apply shell configuration
COPY dotfiles/shell-common /tmp/shell-common
COPY dotfiles/zshrc_appends /tmp/zshrc_appends
RUN cat /tmp/shell-common >> /home/me/.bashrc && \
    cat /tmp/shell-common >> /home/me/.zshrc && \
    # Append Zsh-specific plugin config
    cat /tmp/zshrc_appends >> /home/me/.zshrc && \
    echo 'R_LIBS_SITE="/usr/local/lib/R/site-library"' >> /etc/environment && \
    chown me:me /home/me/.bashrc /home/me/.zshrc && \
    rm /tmp/shell-common /tmp/zshrc_appends

# Create and set default working directory
RUN mkdir -p /workspaces && chown me:me /workspaces
WORKDIR /workspaces

# Keep shell as bash for RUN commands,
# while making zsh the default for interactive sessions
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV SHELL=/bin/zsh
CMD ["/bin/zsh", "-l"]

# ---------------------------------------------------------------------------
# Build Metrics: Stage 12 End
# ---------------------------------------------------------------------------
RUN du -sb /usr /opt /home /root /var 2>/dev/null | awk '{sum+=$1} END {print sum}' > /tmp/build-metrics/stage-12-size-end.txt && \
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z'),full,end,$(date +%s)" >> /tmp/build-metrics/stage-12-full.csv && \
    echo "Stage 12 (full) completed at $(date)" && \
    echo "Size change: $(cat /tmp/build-metrics/stage-12-size-start.txt) -> $(cat /tmp/build-metrics/stage-12-size-end.txt)"


# ---------------------------------------------------------------------------
# Final User Switch
# ---------------------------------------------------------------------------
# Switch to the 'me' user for the final container
USER me
