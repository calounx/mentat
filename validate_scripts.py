#!/usr/bin/env python3
"""Comprehensive Shell Script Validation"""

import os
import subprocess
import json
from pathlib import Path
from collections import defaultdict
import re

REPO_ROOT = Path("/home/calounx/repositories/mentat")

def find_scripts():
    """Find all shell scripts in deployment directories"""
    scripts = []
    for pattern in ["deploy/**/*.sh", "chom/deploy/**/*.sh"]:
        scripts.extend(REPO_ROOT.glob(pattern))
    return sorted(set(scripts))

def check_shebang(script_path):
    """Check if script has proper shebang"""
    try:
        with open(script_path, 'r') as f:
            first_line = f.readline().strip()

        if not first_line.startswith('#!'):
            return {'status': 'MISSING', 'line': first_line}

        if first_line in ['#!/usr/bin/env bash', '#!/bin/bash']:
            return {'status': 'OK', 'line': first_line}

        return {'status': 'INVALID', 'line': first_line}
    except Exception as e:
        return {'status': 'ERROR', 'line': str(e)}

def check_set_flags(script_path):
    """Check if script has set -euo pipefail or similar"""
    try:
        with open(script_path, 'r') as f:
            content = f.read()

        # Look for various forms of set flags
        patterns = [
            r'^set -[a-z]*e[a-z]*u[a-z]*o[a-z]* pipefail',
            r'^set -euo pipefail',
            r'^set -[a-z]*e.*pipefail.*-u',
        ]

        for i, line in enumerate(content.split('\n')[:20], 1):  # Check first 20 lines
            for pattern in patterns:
                if re.search(pattern, line):
                    return {'status': 'OK', 'line': i}

        return {'status': 'MISSING', 'line': None}
    except Exception as e:
        return {'status': 'ERROR', 'line': str(e)}

def check_executable(script_path):
    """Check if script is executable"""
    return os.access(script_path, os.X_OK)

def check_bash_syntax(script_path):
    """Check bash syntax using bash -n"""
    try:
        result = subprocess.run(
            ['bash', '-n', str(script_path)],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return {'status': 'OK', 'output': ''}
        else:
            return {'status': 'ERROR', 'output': result.stderr}
    except Exception as e:
        return {'status': 'ERROR', 'output': str(e)}

def check_shellcheck(script_path):
    """Run shellcheck on script"""
    try:
        result = subprocess.run(
            ['shellcheck', '-f', 'gcc', str(script_path)],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            return {'status': 'CLEAN', 'output': '', 'issues': []}

        output = result.stdout + result.stderr
        issues = []

        # Parse shellcheck output
        for line in output.split('\n'):
            if line.strip():
                issues.append(line)

        # Determine severity
        has_errors = any('error:' in line for line in issues)
        has_warnings = any('warning:' in line for line in issues)

        if has_errors:
            status = 'ERROR'
        elif has_warnings:
            status = 'WARNING'
        else:
            status = 'INFO'

        return {'status': status, 'output': output, 'issues': issues}

    except Exception as e:
        return {'status': 'ERROR', 'output': str(e), 'issues': []}

def validate_script(script_path):
    """Perform all validations on a single script"""
    rel_path = script_path.relative_to(REPO_ROOT)

    result = {
        'path': str(rel_path),
        'absolute_path': str(script_path),
        'executable': check_executable(script_path),
        'shebang': check_shebang(script_path),
        'set_flags': check_set_flags(script_path),
        'bash_syntax': check_bash_syntax(script_path),
        'shellcheck': check_shellcheck(script_path),
    }

    # Determine overall severity
    if result['bash_syntax']['status'] == 'ERROR' or \
       result['shellcheck']['status'] == 'ERROR':
        result['severity'] = 'ERROR'
    elif result['shellcheck']['status'] == 'WARNING' or \
         result['shebang']['status'] != 'OK' or \
         result['set_flags']['status'] != 'OK':
        result['severity'] = 'WARNING'
    else:
        result['severity'] = 'PASS'

    return result

def main():
    """Main validation function"""
    print("=" * 70)
    print("COMPREHENSIVE SHELL SCRIPT VALIDATION")
    print("=" * 70)
    print()

    scripts = find_scripts()
    print(f"Found {len(scripts)} shell scripts to validate\n")

    results = []
    stats = {
        'total': len(scripts),
        'passed': 0,
        'warnings': 0,
        'errors': 0,
        'no_exec': 0
    }

    categorized = {
        'ERROR': [],
        'WARNING': [],
        'PASS': []
    }

    for i, script in enumerate(scripts, 1):
        rel_path = script.relative_to(REPO_ROOT)
        print(f"[{i}/{len(scripts)}] Checking: {rel_path}")

        result = validate_script(script)
        results.append(result)

        # Update stats
        categorized[result['severity']].append(result)

        if result['severity'] == 'ERROR':
            stats['errors'] += 1
            print(f"  ✗ ERRORS FOUND")
        elif result['severity'] == 'WARNING':
            stats['warnings'] += 1
            print(f"  ⚠ WARNINGS FOUND")
        else:
            stats['passed'] += 1
            print(f"  ✓ PASSED")

        if not result['executable']:
            stats['no_exec'] += 1

    # Generate markdown report
    report_path = REPO_ROOT / "SCRIPT_VALIDATION_REPORT.md"
    with open(report_path, 'w') as f:
        f.write("# COMPREHENSIVE SHELL SCRIPT VALIDATION REPORT\n\n")
        f.write(f"**Generated:** {subprocess.run(['date'], capture_output=True, text=True).stdout.strip()}\n\n")

        # Summary
        f.write("## Summary\n\n")
        f.write(f"- **Total Scripts:** {stats['total']}\n")
        f.write(f"- **Passed:** {stats['passed']}\n")
        f.write(f"- **Warnings:** {stats['warnings']}\n")
        f.write(f"- **Errors:** {stats['errors']}\n")
        f.write(f"- **No Execute Permission:** {stats['no_exec']}\n\n")

        # Scripts with errors
        if categorized['ERROR']:
            f.write(f"## Scripts with ERRORS ({len(categorized['ERROR'])})\n\n")
            for result in categorized['ERROR']:
                f.write(f"### {result['path']}\n\n")
                f.write(f"- **Executable:** {'Yes' if result['executable'] else 'No'}\n")
                f.write(f"- **Shebang:** {result['shebang']['status']}\n")
                f.write(f"- **Set Flags:** {result['set_flags']['status']}\n")
                f.write(f"- **Bash Syntax:** {result['bash_syntax']['status']}\n\n")

                if result['bash_syntax']['output']:
                    f.write("**Bash Syntax Errors:**\n```\n")
                    f.write(result['bash_syntax']['output'])
                    f.write("\n```\n\n")

                if result['shellcheck']['issues']:
                    f.write("**Shellcheck Issues:**\n```\n")
                    for issue in result['shellcheck']['issues'][:30]:  # Limit to 30 issues
                        f.write(issue + '\n')
                    if len(result['shellcheck']['issues']) > 30:
                        f.write(f"\n... and {len(result['shellcheck']['issues']) - 30} more issues\n")
                    f.write("```\n\n")

        # Scripts with warnings
        if categorized['WARNING']:
            f.write(f"## Scripts with WARNINGS ({len(categorized['WARNING'])})\n\n")
            for result in categorized['WARNING']:
                f.write(f"### {result['path']}\n\n")
                f.write(f"- **Executable:** {'Yes' if result['executable'] else 'No'}\n")
                f.write(f"- **Shebang:** {result['shebang']['status']}")
                if result['shebang']['status'] != 'OK':
                    f.write(f" (`{result['shebang']['line']}`)")
                f.write("\n")
                f.write(f"- **Set Flags:** {result['set_flags']['status']}\n")
                f.write(f"- **Bash Syntax:** {result['bash_syntax']['status']}\n\n")

                if result['shellcheck']['issues']:
                    f.write("**Shellcheck Issues:**\n```\n")
                    for issue in result['shellcheck']['issues'][:20]:  # Limit to 20 issues
                        f.write(issue + '\n')
                    if len(result['shellcheck']['issues']) > 20:
                        f.write(f"\n... and {len(result['shellcheck']['issues']) - 20} more issues\n")
                    f.write("```\n\n")

        # Scripts that passed
        if categorized['PASS']:
            f.write(f"## Scripts that PASSED ({len(categorized['PASS'])})\n\n")
            for result in categorized['PASS']:
                f.write(f"- {result['path']}\n")
            f.write("\n")

        # Scripts without execute permission
        no_exec = [r for r in results if not r['executable']]
        if no_exec:
            f.write(f"## Scripts without Execute Permission ({len(no_exec)})\n\n")
            for result in no_exec:
                f.write(f"- {result['path']}\n")
            f.write("\n")
            f.write("**Fix command:**\n```bash\n")
            for result in no_exec:
                f.write(f"chmod +x {result['absolute_path']}\n")
            f.write("```\n\n")

    # Save JSON results
    json_path = REPO_ROOT / "script-validation-results.json"
    with open(json_path, 'w') as f:
        json.dump(results, f, indent=2)

    # Print summary
    print()
    print("=" * 70)
    print("VALIDATION SUMMARY")
    print("=" * 70)
    print(f"Total Scripts: {stats['total']}")
    print(f"Passed: {stats['passed']}")
    print(f"Warnings: {stats['warnings']}")
    print(f"Errors: {stats['errors']}")
    print(f"No Execute Permission: {stats['no_exec']}")
    print()
    print(f"Detailed report saved to: {report_path}")
    print(f"JSON results saved to: {json_path}")
    print("=" * 70)

    # Exit with error if there are errors
    return 1 if stats['errors'] > 0 else 0

if __name__ == '__main__':
    exit(main())
