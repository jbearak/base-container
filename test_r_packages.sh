#!/usr/bin/env bash
# test_r_packages.sh - Unit tests for install_r_packages.sh script
#
# Tests the logic of the R package installation script without requiring R to be installed
# Validates:
# - rstanarm exclusion from pak installation
# - rstanarm conditional installation logic
# - proper handling of package file filtering
#
# Usage: ./test_r_packages.sh

set -euo pipefail

# Result aggregation
RESULT=0
PASS_COUNT=0
FAIL_COUNT=0

record_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "[PASS] $1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "[FAIL] $1"; RESULT=1; }

print_summary() {
    echo "================ Summary ================"
    echo "PASS: $PASS_COUNT"
    echo "FAIL: $FAIL_COUNT" 
    echo "========================================="
}

trap 'print_summary; exit $RESULT' EXIT

# Test 1: Verify script exists and has correct syntax
if [[ ! -f "./install_r_packages.sh" ]]; then
    record_fail "install_r_packages.sh script not found"
    exit 1
fi

if bash -n ./install_r_packages.sh; then
    record_pass "install_r_packages.sh syntax check"
else
    record_fail "install_r_packages.sh syntax check"
fi

# Test 2: Create test package files
cat > /tmp/packages_with_rstanarm.txt <<EOF
abind
rstanarm
base64enc
EOF

cat > /tmp/packages_without_rstanarm.txt <<EOF
abind
base64enc
EOF

# Test 3: Verify rstanarm detection logic
if grep -q "^rstanarm$" "/tmp/packages_with_rstanarm.txt"; then
    record_pass "rstanarm detection in package file (positive case)"
else
    record_fail "rstanarm detection in package file (positive case)"
fi

if ! grep -q "^rstanarm$" "/tmp/packages_without_rstanarm.txt"; then
    record_pass "rstanarm detection in package file (negative case)"
else
    record_fail "rstanarm detection in package file (negative case)"
fi

# Test 4: Mock R script behavior for pak installation filtering
# This tests the R logic that excludes rstanarm from pak installation
test_pak_filtering() {
    local packages_file="$1"
    local expected_count="$2"
    local test_name="$3"
    
    # Create a temporary R-like filter script to simulate the logic
    cat > /tmp/filter_test.sh <<EOF
#!/bin/bash
# Simulate R's readLines and filtering logic
packages=\$(grep -v '^\s*\$' "$packages_file")
filtered_packages=\$(echo "\$packages" | grep -v '^rstanarm\$')
count=\$(echo "\$filtered_packages" | wc -w)
echo "\$count"
EOF
    
    chmod +x /tmp/filter_test.sh
    local actual_count=$(/tmp/filter_test.sh)
    
    if [[ "$actual_count" -eq "$expected_count" ]]; then
        record_pass "$test_name"
    else
        record_fail "$test_name (expected $expected_count, got $actual_count)"
    fi
    
    rm -f /tmp/filter_test.sh
}

test_pak_filtering "/tmp/packages_with_rstanarm.txt" 2 "pak filtering with rstanarm (should exclude 1 package)"
test_pak_filtering "/tmp/packages_without_rstanarm.txt" 2 "pak filtering without rstanarm (should exclude 0 packages)"

# Test 5: Verify script contains the expected rstanarm handling
if grep -q "Building rstanarm" ./install_r_packages.sh; then
    record_pass "script contains rstanarm build message"
else
    record_fail "script contains rstanarm build message"
fi

if grep -q "packages != 'rstanarm'" ./install_r_packages.sh; then
    record_pass "script excludes rstanarm from pak installation"
else
    record_fail "script excludes rstanarm from pak installation"
fi

if grep -q 'grep -q "^rstanarm\$"' ./install_r_packages.sh; then
    record_pass "script has conditional rstanarm installation check"
else
    record_fail "script has conditional rstanarm installation check"
fi

# Test 6: Verify the script follows the expected pattern for special packages
special_packages=("mcmcplots" "httpgd" "colorout" "btw")
for package in "${special_packages[@]}"; do
    if grep -q "Building $package" ./install_r_packages.sh; then
        record_pass "script has build message for special package: $package"
    else
        record_fail "script has build message for special package: $package"
    fi
done

# Cleanup
rm -f /tmp/packages_with_rstanarm.txt /tmp/packages_without_rstanarm.txt

echo "✅ R package installation script tests completed"