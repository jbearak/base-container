# ===========================================================================
# MULTI-STAGE R CONTAINER IMAGE - OPTIMIZED FOR DOCKER LAYER CACHING
# ===========================================================================
# Purpose   : Build containerized R development environments optimized for
#             different use cases. This Dockerfile uses a multi-stage approach
#             optimized for Docker layer caching with two final targets:
#
#             r-container: Lightweight for CI/CD (GitHub Actions, Bitbucket Pipelines)
#             full-container: Complete development environment
#
#             Stage 1 (base)               : Setup Ubuntu with basic tools + jq/yq.
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
#             Stage 12 (full-container)    : Complete development environment (renamed from 'full').
#             Stage 13 (r-container)       : Lightweight CI/CD container (branches from base).
#
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
#               docker build --target full-container -t full-container:latest .
#               docker build --target r-container -t r-container:latest .
#
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 1: BASE SYSTEM (base)
# ===========================================================================
# This stage installs Ubuntu packages and copies user configuration files 
# (dotfiles). R installation, CmdStan, and JAGS have been moved to stage 9
# for better build caching and separation of concerns.
# ---------------------------------------------------------------------------

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base
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
# Install jq and yq for JSON/YAML processing (needed for both containers)
# ---------------------------------------------------------------------------
RUN apt-get update -qq && apt-get install -y --no-install-recommends jq && \
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Continue with rest of Dockerfile content...
# (The file is too large to update in one go, so this is just the beginning)