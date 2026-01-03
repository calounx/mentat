#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="/home/calounx/repositories/mentat"
cd "$SCRIPT_DIR"

REPORT_FILE="$SCRIPT_DIR/script-validation-report.md"

echo "# COMPREHENSIVE SHELL SCRIPT VALIDATION REPORT" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

total=0
errors=0
warnings=0
passed=0
no_exec=0

declare -a error_files=()
declare -a warning_files=()
declare -a passed_files=()
declare -a no_exec_files=()

echo "Scanning scripts..."

while IFS= read -r -d '' script; do
    ((total++))

    echo "Checking: $script"

    has_error=0
    has_warning=0

    # Check executable
    if [[ ! -x "$script" ]]; then
        no_exec_files+=("$script")
        ((no_exec++))
    fi

    # Bash syntax check
    if ! bash -n "$script" 2>&1; then
        has_error=1
    fi

    # Shellcheck
    shellcheck_out=$(shellcheck -f gcc "$script" 2>&1 || true)

    if echo "$shellcheck_out" | grep -q "error:"; then
        has_error=1
    elif echo "$shellcheck_out" | grep -q "warning:"; then
        has_warning=1
    fi

    # Categorize
    if [[ $has_error -eq 1 ]]; then
        error_files+=("$script")
        ((errors++))

        echo "" >> "$REPORT_FILE"
        echo "## ERROR: $script" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        bash -n "$script" 2>&1 || true >> "$REPORT_FILE"
        echo "$shellcheck_out" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"

    elif [[ $has_warning -eq 1 ]]; then
        warning_files+=("$script")
        ((warnings++))

        echo "" >> "$REPORT_FILE"
        echo "## WARNING: $script" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "$shellcheck_out" | head -50 >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"

    else
        passed_files+=("$script")
        ((passed++))
    fi

done < <(find deploy chom/deploy -name "*.sh" -type f -print0 | sort -z)

# Write summary
{
    echo ""
    echo "# SUMMARY"
    echo ""
    echo "- **Total Scripts**: $total"
    echo "- **Passed**: $passed"
    echo "- **Warnings**: $warnings"
    echo "- **Errors**: $errors"
    echo "- **No Execute Permission**: $no_exec"
    echo ""
} >> "$REPORT_FILE"

# Lists
if [[ ${#error_files[@]} -gt 0 ]]; then
    echo "## Scripts with ERRORS (${#error_files[@]})" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    for f in "${error_files[@]}"; do
        echo "- $f" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

if [[ ${#warning_files[@]} -gt 0 ]]; then
    echo "## Scripts with WARNINGS (${#warning_files[@]})" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    for f in "${warning_files[@]}"; do
        echo "- $f" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

if [[ ${#no_exec_files[@]} -gt 0 ]]; then
    echo "## Scripts without Execute Permission (${#no_exec_files[@]})" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    for f in "${no_exec_files[@]}"; do
        echo "- $f" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

echo ""
echo "==================================================================="
echo "VALIDATION COMPLETE"
echo "==================================================================="
echo "Total Scripts: $total"
echo "Passed: $passed"
echo "Warnings: $warnings"
echo "Errors: $errors"
echo "No Execute Permission: $no_exec"
echo ""
echo "Report saved to: $REPORT_FILE"
echo "==================================================================="
