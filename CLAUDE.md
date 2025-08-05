# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Multi-stage R development container for research environments. Primary focus is building Docker images with R, Neovim, VS Code, LaTeX, and Pandoc for data analysis and scientific document preparation.

## Build Commands

**Container Build (primary workflow):**
- Full image: `./build-container.sh --full`
- Stage-specific builds: `./build-container.sh --base` | `--base-nvim` | `--base-nvim-vscode` | `--base-nvim-vscode-tex` | `--base-nvim-vscode-tex-pandoc` | `--base-nvim-vscode-tex-pandoc-plus`
- Debug R package builds: `./build-container.sh --full --debug`
- No cache: add `--no-cache` to any build command
- Build with tests: add `--test` to any build command

**Test Commands:**
- Built-in test suite: `./build-container.sh --full --test` (works for other stages)
- Pandoc smoke tests: `./test_pandoc.sh` (run inside container)
- R packages quick test: `./test_packages.sh` (requires R on host)
- One-off container check: `docker run --rm dev-container:<tag> <cmd>`

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
- Stage 4-6: LaTeX, Pandoc, and additional packages
- Stage 7 (full): + comprehensive R package suite (262 packages from `R_packages.txt`)

**Key Components:**
- R package installation via `install_packages.sh` with parallel compilation optimizations
- Neovim configured with lazy.nvim plugin manager (`dotfiles/config/nvim/`)
- Development tools: Go, Node.js, Python with language servers
- Document processing: LaTeX + Pandoc + pandoc-crossref

**User Environment:**
- Primary user: `me` (UID 1000, shell: zsh)
- R compilation optimized via `~/.R/Makevars`
- Dotfiles structure: `dotfiles/` → `/home/me/.*`

## Development Patterns

**Shell Scripts:**
- Use `set -euo pipefail`
- Quote variables, prefer `$(...)` over backticks
- Fail fast with meaningful error messages

**Dockerfile:**
- Single-purpose layers, clean apt caches
- Pin versions or fetch latest via API calls
- Use ARGs for build toggles (e.g., `DEBUG_PACKAGES`)

**R:**
- Explicit CRAN repos, quiet installs where possible
- Use `require(..., character.only=TRUE)` for package checks
- Parallel compilation via `MAKEFLAGS = -j$(nproc)`

**Naming:**
- kebab-case for scripts
- snake_case for environment variables
- UPPER_SNAKE for constants
- lowercase for image/tag names

## File Structure

- `Dockerfile`: Multi-stage container definition
- `build-container.sh`: Main build script with stage options
- `install_packages.sh`: Sequential R package installer
- `R_packages.txt`: List of CRAN packages (262 total)
- `test_*.sh`: Various test scripts
- `dotfiles/`: User configuration (tmux, Neovim, R profile, lintr)