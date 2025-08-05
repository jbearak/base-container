#!/usr/bin/env bash
# test_pandoc.sh - tests for Pandoc conversions
# - Generates a tiny 2x2 RGBA PNG from an inline base64 string (no external deps)
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

# Generate example.png (1x1 PNG) using Python
generate_example_png() {
    ./generate_test_png.py example.png
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
