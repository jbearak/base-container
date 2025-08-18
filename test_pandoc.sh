#!/usr/bin/env bash
# test_pandoc.sh - tests for Pandoc conversions
#
# REQUIRED DEPENDENCIES (must be present in repository root):
#   - generate_test_png.py: Creates minimal PNG files for image embedding tests
#   - install_r_packages.sh: R package installation script (used by Dockerfile)
#   - R_packages.txt: List of R packages to install (used by Dockerfile)
#   - r-shell-config: Shell configuration for R environment (used by Dockerfile)
#   - dotfiles/: Directory containing configuration files (used by Dockerfile)
#
# If dependencies are missing, this script will fail with clear error messages.
#
# Features:
# - Generates test PNG images using generate_test_png.py (no external image deps)
# - Verifies formats, handles optional dependencies with SKIP, and supports debug mode
# - Cleans artifacts by default; preserves when PANDOC_DEBUG=1
#
# Debugging:
#   PANDOC_DEBUG=1  -> enable set -x, print versions/ENV, and preserve temp files
#
# Cleanup policy (default on unless PANDOC_DEBUG=1):
#   Removes: test.{pdf,docx,html,log,aux,out}, _minted*, ./build/latex/*
#
# Minimal matrix covered:
#   - md -> pdf via LaTeX (with image and citeproc)
#   - md -> docx
#   - md -> html

set -euo pipefail

# Check required dependencies before running any tests
check_dependencies() {
    local missing_deps=0
    
    # Test-specific dependencies
    if [[ ! -f "./generate_test_png.py" ]]; then
        echo "❌ FATAL: generate_test_png.py is missing!"
        echo "This is a required test dependency for Pandoc image tests."
        echo "The script should be in the repository root directory."
        echo "If missing, restore from git history:"
        echo "  git show 827e83e:generate_test_png.py > generate_test_png.py"
        echo "  chmod +x generate_test_png.py"
        missing_deps=1
    fi
    
    # Build dependencies (required by Dockerfile)
    if [[ ! -f "./install_r_packages.sh" ]]; then
        echo "❌ FATAL: install_r_packages.sh is missing!"
        echo "This script is required by the Dockerfile for R package installation."
        missing_deps=1
    fi
    
    if [[ ! -f "./R_packages.txt" ]]; then
        echo "❌ FATAL: R_packages.txt is missing!"
        echo "This file contains the list of R packages to install and is required by the Dockerfile."
        missing_deps=1
    fi
    
    if [[ ! -f "./r-shell-config" ]]; then
        echo "❌ FATAL: r-shell-config is missing!"
        echo "This file contains shell configuration for R and is required by the Dockerfile."
        missing_deps=1
    fi
    
    if [[ ! -d "./dotfiles" ]]; then
        echo "❌ FATAL: dotfiles/ directory is missing!"
        echo "This directory contains configuration files required by the Dockerfile."
        missing_deps=1
    else
        # Check key dotfiles that are explicitly copied by Dockerfile
        local required_dotfiles=(
            "dotfiles/tmux.conf"
            "dotfiles/Rprofile" 
            "dotfiles/lintr"
            "dotfiles/shell-common"
            "dotfiles/zshrc_appends"
            "dotfiles/config/nvim/init.lua"
        )
        
        for file in "${required_dotfiles[@]}"; do
            if [[ ! -f "./$file" ]]; then
                echo "❌ FATAL: $file is missing!"
                echo "This configuration file is required by the Dockerfile."
                missing_deps=1
            fi
        done
    fi
    
    if [[ $missing_deps -eq 1 ]]; then
        echo ""
        echo "Cannot proceed with tests due to missing required dependencies."
        echo "These files are needed for both testing and container builds."
        exit 1
    fi
}

# Check dependencies first, before any other setup
check_dependencies

# Result aggregation: run all tests, report summary, exit non-zero if any FAIL
RESULT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

record_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "[PASS] $1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "[FAIL] $1"; RESULT=1; }
record_skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); echo "[SKIP] $1"; }

if [[ "${PANDOC_DEBUG:-0}" == "1" ]]; then
    set -x
    echo "[DEBUG] pandoc version:"; pandoc --version || true
    # Try to print TeX engine versions if present
    command -v xelatex &>/dev/null && { echo "[DEBUG] xelatex version:"; xelatex --version | head -n 1; } || true
    command -v tectonic &>/dev/null && { echo "[DEBUG] tectonic version:"; tectonic --version; } || true
    command -v latexmk &>/dev/null && { echo "[DEBUG] latexmk version:"; latexmk -v | head -n 1; } || true
    echo "[DEBUG] PATH: $PATH"
fi

cleanup() {
    if [[ "${PANDOC_DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] Preserving artifacts due to PANDOC_DEBUG=1"
        return 0
    fi
    rm -f test.{pdf,docx,html,log,aux,out,md} || true
    rm -f refs.bib || true
    rm -f crossref_test.md || true
    rm -f example.png || true
    rm -rf _minted* ./build/latex || true
}

# Summary printed at exit
print_summary() {
    echo "================ Summary ================"
    echo "PASS: $PASS_COUNT"
    echo "FAIL: $FAIL_COUNT"
    echo "SKIP: $SKIP_COUNT"
    echo "========================================="
    return 0
}
# Ensure cleanup runs on any exit, then summary prints, then exit with aggregated RESULT
trap 'cleanup; print_summary; exit $RESULT' EXIT

# Generate example.png (1x1 PNG) using Python script
generate_example_png() {
    # Note: Dependency check already performed at script start
    if ! ./generate_test_png.py example.png; then
        echo "❌ FATAL: Failed to generate test PNG file"
        echo "The generate_test_png.py script exists but failed to execute."
        echo "Possible causes:"
        echo "  - The script does not have execute or read permissions."
        echo "  - Python 3 is not available or not in PATH."
        echo "  - Required Python modules (e.g., zlib) are missing."
        echo "Check permissions, Python 3 installation, and required modules."
        exit 1
    fi
}
# Helper: check a pattern in pandoc format lists, else SKIP
check_pandoc_support_or_skip() {
    local my_label="$1"
    local my_pattern="$2"
    if ! pandoc --list-output-formats | grep -q "$my_pattern"; then
        echo "SKIP: $my_label not supported by pandoc output formats"
        return 1
    fi
    return 0
}

# Verify core formats (docx input/output and pdf output) — treat as required
DOCX_IN_OK=1
DOCX_OUT_OK=1
PDF_OUT_OK=1

if ! pandoc --list-input-formats  | grep -q docx; then
    record_fail "pandoc docx input format support"
    DOCX_IN_OK=0
else
    record_pass "pandoc docx input format support"
fi
if ! pandoc --list-output-formats | grep -q docx; then
    record_fail "pandoc docx output format support"
    DOCX_OUT_OK=0
else
    record_pass "pandoc docx output format support"
fi
if ! pandoc --list-output-formats | grep -q pdf; then
    record_fail "pandoc pdf output format support"
    PDF_OUT_OK=0
else
    record_pass "pandoc pdf output format support"
fi

# md -> docx
if echo "# Test Document" | pandoc -f markdown -t docx -o test.docx; then
    record_pass "md -> docx"
else
    record_fail "md -> docx"
fi

# md -> html (basic smoke)
if echo "# Test HTML" | pandoc -f markdown -t html -o test.html; then
    record_pass "md -> html"
else
    record_fail "md -> html"
fi

# Prepare example files for pdf with citeproc and image
generate_example_png
cat > test.md <<'MD'
---
bibliography: refs.bib
---
# Test

This is a citation [@test2024], and an image:

![Example figure](example.png){#fig:example width=2cm}
MD

cat > refs.bib <<'BIB'
@article{test2024,
  title = {Test Article},
  author = {Author, Test},
  year = {2024},
  journal = {Journal of Tests}
}
BIB

# Use a fixed TeX engine: xelatex
my_tex_engine=""
if command -v xelatex >/dev/null 2>&1; then
    my_tex_engine="--pdf-engine=xelatex"
fi
# md -> pdf via LaTeX with citeproc and embedded image
if [[ -z "$my_tex_engine" ]]; then
    record_fail "TeX engine (xelatex) not found; required for md -> pdf"
else
    if pandoc test.md --citeproc $my_tex_engine -o test.pdf; then
        record_pass "md -> pdf (LaTeX, citeproc, image)"
    else
        record_fail "md -> pdf (LaTeX, citeproc, image)"
    fi
fi

# pandoc-crossref tests — treat filter as required, but continue and aggregate
if command -v pandoc-crossref >/dev/null 2>&1; then
    cat > crossref_test.md <<'MD'
# Test Document

See @fig:example and @eq:formula.

![Example figure](example.png){#fig:example width=1cm}

$$
y = m x + b
$$ {#eq:formula}
MD
    if [[ -z "$my_tex_engine" ]]; then
        record_fail "pandoc-crossref pdf test (no TeX engine)"
    else
        # Use --citeproc to ensure consistent metadata pipeline; capture log for debugging
        if pandoc crossref_test.md --filter pandoc-crossref --citeproc $my_tex_engine -o crossref_test.pdf 2> crossref_test.log; then
            record_pass "pandoc-crossref pdf"
        else
            echo "[DEBUG] pandoc-crossref log (tail):"
            tail -n 50 crossref_test.log || true
            record_fail "pandoc-crossref pdf"
        fi
    fi
    pandoc-crossref --version >/dev/null 2>&1 || true
else
    record_fail "pandoc-crossref not installed"
fi
