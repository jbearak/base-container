# CLAUDE.md

This file provides guidance to AI assistants when working with code in this repository.

## Repository Overview

Multi-stage R development container for research environments. Primary focus is building Docker images with R, Neovim, VS Code, LaTeX, and Pandoc for data analysis and scientific document preparation.

## Build Commands

**Container Build (primary workflow):**
- Full container: `./build-container.sh --full-container`
- R-only container: `./build-container.sh --r-container` 
- Stage-specific builds: `./build-container.sh --base` | `--base-nvim` | `--base-nvim-vscode` | `--base-nvim-vscode-tex` | `--base-nvim-vscode-tex-pandoc` | `--base-nvim-vscode-tex-pandoc-plus`
- Debug R package builds: `./build-container.sh --full-container --debug`
- No cache: add `--no-cache` to any build command
- Build with tests: add `--test` to any build command
- Build multiple targets: `./build-all.sh`
- AMD64 specific: `./build-amd64.sh`

**Additional Build Scripts:**
- `cache-helper.sh`: Docker build cache management
- `push-to-ghcr.sh`: Push images to GitHub Container Registry

**Test Commands:**
- Built-in test suite: `./build-container.sh --full-container --test`
- Pandoc comprehensive tests: `./test_pandoc.sh` (run inside container)
- One-off container check: `docker run --rm <image>:<tag> <cmd>`

**Lint/Format:**
- Dockerfile: `hadolint Dockerfile`
- Shell scripts: `shellcheck <file>; shfmt -w .`
- R code: `R -e "lintr::lint_dir()"` (uses `dotfiles/lintr`)
- Neovim Lua: `stylua dotfiles/config/nvim`

## Architecture

**Multi-stage Docker Build:**
- Stage 1 (base): Ubuntu + R + system tools
- Stage 2 (base-nvim): + Neovim with lazy.nvim plugins
- Stage 3 (base-nvim-vscode): + VS Code server and extensions
- Stage 4 (base-nvim-vscode-tex): + LaTeX/TeX Live
- Stage 5 (base-nvim-vscode-tex-pandoc): + Pandoc and pandoc-crossref
- Stage 6 (base-nvim-vscode-tex-pandoc-plus): + additional tools
- Stage 7 (full-container): + comprehensive R package suite (268 packages from `R_packages.txt`)
- Stage 8 (r-container): Slim CI image with essential R packages only

**Key Components:**
- R package installation via `install_r_packages.sh` with parallel compilation optimizations
- Neovim configured with lazy.nvim plugin manager (`dotfiles/config/nvim/`)
- Development tools: Go, Node.js, Python with language servers
- Document processing: LaTeX + Pandoc + pandoc-crossref
- Container registry support via GitHub Container Registry

**User Environment:**
- Primary user: `me` (UID 1000, shell: zsh)
- R compilation optimized via `~/.R/Makevars`
- Dotfiles structure: `dotfiles/` → `/home/me/.*`
- Support for both development and CI/CD workflows

## Development Patterns

**Shell Scripts:**
- Use `set -euo pipefail`
- Quote variables, prefer `$(...)` over backticks
- Fail fast with meaningful error messages
- Comprehensive error handling and logging

**Dockerfile:**
- Single-purpose layers, clean apt caches
- Pin versions or fetch latest via API calls
- Use ARGs for build toggles (e.g., `DEBUG_PACKAGES`)
- Multi-stage builds for optimization

**R:**
- Explicit CRAN repos, quiet installs where possible
- Use `require(..., character.only=TRUE)` for package checks
- Parallel compilation via `MAKEFLAGS = -j$(nproc)`
- Optimized package installation with fallback mechanisms

**Naming:**
- kebab-case for scripts
- snake_case for environment variables
- UPPER_SNAKE for constants
- lowercase for image/tag names

## File Structure

- `Dockerfile`: Multi-stage container definition
- `build-container.sh`: Main build script with stage options
- `build-all.sh`: Build multiple container targets
- `build-amd64.sh`: AMD64-specific build script
- `install_r_packages.sh`: Optimized R package installer with fallback
- `R_packages.txt`: List of CRAN packages (268 total)
- `test_pandoc.sh`: Comprehensive Pandoc testing suite
- `cache-helper.sh`: Docker build cache management
- `push-to-ghcr.sh`: GitHub Container Registry deployment
- `dotfiles/`: User configuration (tmux, Neovim, R profile, lintr)
- `.devcontainer/`: VS Code development container configuration
- `.amazonq/`: Amazon Q assistant rules and guidelines