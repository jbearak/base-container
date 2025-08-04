#!/usr/bin/env bash
set -euo pipefail

# Verify docx & pdf formats are supported
pandoc --list-input-formats  | grep -q docx
pandoc --list-output-formats | grep -q docx
pandoc --list-output-formats | grep -q pdf

# Basic docx → pdf round-trip
echo "# Test Document" | pandoc -f markdown -t docx -o test.docx
pandoc test.docx -o test.pdf

# Bibliography + citeproc test
echo -e "---\nbibliography: refs.bib\n---\n\n# Test\n\nThis is a citation [@test2024]." > test.md
echo -e "@article{test2024,\n  title={Test Article},\n  author={Author, Test},\n  year={2024}\n}" > refs.bib
pandoc test.md --citeproc -o test_cite.pdf

# Test pandoc-crossref functionality
echo -e "# Test Document\n\nSee @fig:example and @eq:formula.\n\n![Example figure](example.png){#fig:example}\n\n$$y = mx + b$$ {#eq:formula}" > crossref_test.md
pandoc crossref_test.md --filter pandoc-crossref -o crossref_test.pdf

# Verify pandoc-crossref is available
pandoc-crossref --version
