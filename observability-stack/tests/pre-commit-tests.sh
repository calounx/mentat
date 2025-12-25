#!/bin/bash
#===============================================================================
# Pre-commit Test Script
# Runs quick tests before allowing commit
# Install: ln -s ../../tests/pre-commit-tests.sh .git/hooks/pre-commit
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Track results
CHECKS_PASSED=0
CHECKS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get list of staged shell files
get_staged_shell_files() {
    git diff --cached --name-only --diff-filter=ACMR | grep '\.sh$' || true
}

# Get list of staged bats files
get_staged_bats_files() {
    git diff --cached --name-only --diff-filter=ACMR | grep '\.bats$' || true
}

# Get list of staged YAML files
get_staged_yaml_files() {
    git diff --cached --name-only --diff-filter=ACMR | grep -E '\.(yaml|yml)$' || true
}

# Check shell syntax
check_shell_syntax() {
    local files
    files=$(get_staged_shell_files)

    if [[ -z "$files" ]]; then
        log_info "No shell files staged, skipping syntax check"
        return 0
    fi

    log_info "Checking shell syntax..."

    local failed=0
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            if bash -n "$file" 2>/dev/null; then
                echo "  ✓ $file"
            else
                echo "  ✗ $file - syntax error"
                ((failed++))
            fi
        fi
    done <<< "$files"

    if [[ $failed -eq 0 ]]; then
        log_success "Shell syntax check passed"
        ((CHECKS_PASSED++))
        return 0
    else
        log_error "Shell syntax check failed ($failed file(s))"
        ((CHECKS_FAILED++))
        return 1
    fi
}

# Run shellcheck on staged files
check_shellcheck() {
    if ! command -v shellcheck &> /dev/null; then
        log_warn "shellcheck not installed, skipping"
        return 0
    fi

    local files
    files=$(get_staged_shell_files)

    if [[ -z "$files" ]]; then
        log_info "No shell files staged, skipping shellcheck"
        return 0
    fi

    log_info "Running shellcheck..."

    local failed=0
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            if shellcheck -S warning "$file" 2>/dev/null; then
                echo "  ✓ $file"
            else
                ((failed++))
            fi
        fi
    done <<< "$files"

    if [[ $failed -eq 0 ]]; then
        log_success "ShellCheck passed"
        ((CHECKS_PASSED++))
        return 0
    else
        log_error "ShellCheck failed ($failed file(s))"
        ((CHECKS_FAILED++))
        return 1
    fi
}

# Validate YAML syntax
check_yaml_syntax() {
    local files
    files=$(get_staged_yaml_files)

    if [[ -z "$files" ]]; then
        log_info "No YAML files staged, skipping YAML validation"
        return 0
    fi

    log_info "Validating YAML syntax..."

    local failed=0
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            # Try yamllint first, fall back to python
            if command -v yamllint &> /dev/null; then
                if yamllint -d relaxed "$file" 2>/dev/null; then
                    echo "  ✓ $file"
                else
                    echo "  ✗ $file"
                    ((failed++))
                fi
            elif command -v python3 &> /dev/null; then
                if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
                    echo "  ✓ $file"
                else
                    echo "  ✗ $file"
                    ((failed++))
                fi
            else
                log_warn "No YAML validator found, skipping $file"
            fi
        fi
    done <<< "$files"

    if [[ $failed -eq 0 ]]; then
        log_success "YAML validation passed"
        ((CHECKS_PASSED++))
        return 0
    else
        log_error "YAML validation failed ($failed file(s))"
        ((CHECKS_FAILED++))
        return 1
    fi
}

# Run quick unit tests if test files changed
check_unit_tests() {
    if ! command -v bats &> /dev/null; then
        log_warn "bats not installed, skipping unit tests"
        return 0
    fi

    # Check if test files or lib files changed
    local changed_files
    changed_files=$(git diff --cached --name-only --diff-filter=ACMR)

    if echo "$changed_files" | grep -qE '(scripts/lib/|tests/test-common\.bats)'; then
        log_info "Running unit tests..."

        if [[ -f "$REPO_ROOT/tests/test-common.bats" ]]; then
            if bats "$REPO_ROOT/tests/test-common.bats" 2>/dev/null; then
                log_success "Unit tests passed"
                ((CHECKS_PASSED++))
                return 0
            else
                log_error "Unit tests failed"
                ((CHECKS_FAILED++))
                return 1
            fi
        fi
    else
        log_info "No lib files changed, skipping unit tests"
    fi

    return 0
}

# Check for common mistakes
check_common_mistakes() {
    local files
    files=$(get_staged_shell_files)

    if [[ -z "$files" ]]; then
        return 0
    fi

    log_info "Checking for common mistakes..."

    local warnings=0

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            # Check for hardcoded passwords
            if grep -nE '(password|passwd)=["'\''][^"'\'']+["'\'']' "$file" | grep -v "YOUR_PASSWORD_HERE" | grep -qv "CHANGE_ME"; then
                log_warn "Possible hardcoded password in $file"
                ((warnings++))
            fi

            # Check for debugging statements
            if grep -nE '^\s*(echo|printf).*DEBUG' "$file" >/dev/null; then
                log_warn "Debug statements found in $file (consider removing)"
                ((warnings++))
            fi

            # Check for TODO comments
            if grep -nE 'TODO|FIXME|XXX' "$file" >/dev/null; then
                log_warn "TODO/FIXME found in $file"
            fi
        fi
    done <<< "$files"

    if [[ $warnings -eq 0 ]]; then
        log_success "No common mistakes found"
        ((CHECKS_PASSED++))
    else
        log_warn "Found $warnings potential issue(s)"
        # Don't fail on warnings
    fi

    return 0
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "Pre-commit Checks"
    echo "=========================================="
    echo ""

    # Run all checks
    check_shell_syntax
    check_shellcheck
    check_yaml_syntax
    check_unit_tests
    check_common_mistakes

    # Summary
    echo ""
    echo "=========================================="
    echo "Pre-commit Summary"
    echo "=========================================="
    echo ""
    echo "Passed: $CHECKS_PASSED"
    echo "Failed: $CHECKS_FAILED"
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_success "All pre-commit checks passed! 🎉"
        echo ""
        return 0
    else
        log_error "Pre-commit checks failed"
        echo ""
        echo "Fix the issues above before committing."
        echo "To bypass (not recommended): git commit --no-verify"
        echo ""
        return 1
    fi
}

# Run main
main
