#!/usr/bin/env python3
"""
Secret Scanner for Observability Stack

Scans YAML files for potential secrets, detects patterns (password, key, token),
checks for default/placeholder values, and warns about plaintext credentials.
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Pattern, Set, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install PyYAML", file=sys.stderr)
    sys.exit(1)


# ANSI color codes
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    BOLD = '\033[1m'
    RESET = '\033[0m'


def color_print(message: str, color: str = Colors.RESET) -> None:
    """Print colored message."""
    print(f"{color}{message}{Colors.RESET}")


def error_print(message: str) -> None:
    """Print error message."""
    print(f"{Colors.RED}{Colors.BOLD}ERROR:{Colors.RESET} {Colors.RED}{message}{Colors.RESET}", file=sys.stderr)


def warning_print(message: str) -> None:
    """Print warning message."""
    print(f"{Colors.YELLOW}{Colors.BOLD}WARNING:{Colors.RESET} {Colors.YELLOW}{message}{Colors.RESET}")


def success_print(message: str) -> None:
    """Print success message."""
    print(f"{Colors.GREEN}{Colors.BOLD}SUCCESS:{Colors.RESET} {Colors.GREEN}{message}{Colors.RESET}")


def info_print(message: str) -> None:
    """Print info message."""
    print(f"{Colors.BLUE}{Colors.BOLD}INFO:{Colors.RESET} {message}")


# Secret detection patterns
SECRET_PATTERNS: Dict[str, Pattern] = {
    'password': re.compile(r'password|passwd|pwd', re.IGNORECASE),
    'secret': re.compile(r'secret|private', re.IGNORECASE),
    'key': re.compile(r'(?:api|auth|access|private)[_-]?key', re.IGNORECASE),
    'token': re.compile(r'token|bearer', re.IGNORECASE),
    'credential': re.compile(r'credential|cred', re.IGNORECASE),
}

# Placeholder/default value patterns
PLACEHOLDER_PATTERNS: List[Pattern] = [
    re.compile(r'^CHANGE[_-]?ME', re.IGNORECASE),
    re.compile(r'^YOUR[_-]', re.IGNORECASE),
    re.compile(r'^REPLACE[_-]', re.IGNORECASE),
    re.compile(r'^TODO', re.IGNORECASE),
    re.compile(r'^FIXME', re.IGNORECASE),
    re.compile(r'^<.*>$'),  # <placeholder>
    re.compile(r'^\[.*\]$'),  # [placeholder]
    re.compile(r'^xxx+', re.IGNORECASE),
    re.compile(r'^example', re.IGNORECASE),
]

# Common weak/default passwords
WEAK_PASSWORDS: Set[str] = {
    'password', 'Password1', '123456', 'admin', 'root',
    'changeme', 'default', 'guest', 'test', 'demo'
}

# Keys that should reference files or environment variables
SHOULD_BE_EXTERNAL: Set[str] = {
    'ssl_cert', 'ssl_key', 'tls_cert', 'tls_key',
    'ca_cert', 'client_cert', 'client_key'
}


class SecretFinding:
    """Represents a potential secret found in configuration."""

    def __init__(
        self,
        file_path: Path,
        key_path: str,
        value: Any,
        severity: str,
        reason: str,
        suggestion: Optional[str] = None
    ):
        """
        Initialize secret finding.

        Args:
            file_path: Path to file where secret was found
            key_path: Path to key in YAML structure (e.g., 'smtp.password')
            value: The value (may be masked)
            severity: 'critical', 'high', 'medium', 'low', 'info'
            reason: Why this was flagged
            suggestion: Suggested remediation
        """
        self.file_path = file_path
        self.key_path = key_path
        self.value = value
        self.severity = severity
        self.reason = reason
        self.suggestion = suggestion

    def __str__(self) -> str:
        """String representation."""
        severity_colors = {
            'critical': Colors.RED,
            'high': Colors.RED,
            'medium': Colors.YELLOW,
            'low': Colors.YELLOW,
            'info': Colors.BLUE,
        }

        color = severity_colors.get(self.severity, Colors.RESET)
        severity_str = f"{color}{self.severity.upper()}{Colors.RESET}"

        lines = [
            f"{severity_str}: {self.file_path}",
            f"  Key: {self.key_path}",
            f"  Value: {self._mask_value()}",
            f"  Reason: {self.reason}",
        ]

        if self.suggestion:
            lines.append(f"  {Colors.CYAN}Suggestion:{Colors.RESET} {self.suggestion}")

        return "\n".join(lines)

    def _mask_value(self) -> str:
        """Mask the value for display."""
        if not isinstance(self.value, str):
            return str(self.value)

        if len(self.value) <= 8:
            return '***'

        # Show first 3 and last 2 characters
        return f"{self.value[:3]}...{self.value[-2:]}"


def load_yaml_file(file_path: Path) -> Optional[Dict[str, Any]]:
    """Load and parse YAML file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        error_print(f"YAML parsing error in {file_path}: {e}")
        return None
    except FileNotFoundError:
        error_print(f"File not found: {file_path}")
        return None
    except Exception as e:
        error_print(f"Error reading {file_path}: {e}")
        return None


def is_placeholder(value: str) -> bool:
    """Check if value appears to be a placeholder."""
    for pattern in PLACEHOLDER_PATTERNS:
        if pattern.match(value):
            return True
    return False


def is_weak_password(value: str) -> bool:
    """Check if value is a known weak password."""
    return value.lower() in {p.lower() for p in WEAK_PASSWORDS}


def detect_secret_type(key: str) -> Optional[str]:
    """
    Detect if a key name suggests it contains a secret.

    Args:
        key: Key name

    Returns:
        Secret type or None
    """
    for secret_type, pattern in SECRET_PATTERNS.items():
        if pattern.search(key):
            return secret_type
    return None


def scan_yaml_structure(
    data: Any,
    file_path: Path,
    findings: List[SecretFinding],
    key_path: str = "",
    check_values: bool = True
) -> None:
    """
    Recursively scan YAML structure for secrets.

    Args:
        data: YAML data to scan
        file_path: Path to file being scanned
        findings: List to append findings to
        key_path: Current path in YAML structure
        check_values: Whether to check actual values
    """
    if isinstance(data, dict):
        for key, value in data.items():
            new_path = f"{key_path}.{key}" if key_path else key

            # Check if key name suggests a secret
            secret_type = detect_secret_type(key)

            if secret_type and isinstance(value, str):
                severity = 'info'
                reason = f"Key name suggests {secret_type}"
                suggestion = None

                # Check for placeholders
                if is_placeholder(value):
                    severity = 'medium'
                    reason = f"Placeholder {secret_type} detected"
                    suggestion = "Replace with actual value before deployment"

                # Check for weak passwords
                elif secret_type == 'password' and is_weak_password(value):
                    severity = 'critical'
                    reason = f"Weak/default password detected"
                    suggestion = "Use a strong, unique password (at least 16 characters)"

                # Check for short passwords
                elif secret_type == 'password' and len(value) < 8:
                    severity = 'high'
                    reason = f"Password is too short ({len(value)} characters)"
                    suggestion = "Use at least 16 characters with mixed case, numbers, and symbols"

                # Check if should be in external file
                elif key in SHOULD_BE_EXTERNAL:
                    severity = 'medium'
                    reason = f"Sensitive data should be in external file"
                    suggestion = f"Store in separate file and reference path, or use environment variable"

                # General plaintext secret warning
                elif not is_placeholder(value):
                    severity = 'high'
                    reason = f"Plaintext {secret_type} in configuration file"
                    suggestion = "Use environment variables, secrets management, or encrypted storage"

                findings.append(SecretFinding(
                    file_path=file_path,
                    key_path=new_path,
                    value=value,
                    severity=severity,
                    reason=reason,
                    suggestion=suggestion
                ))

            # Recurse into nested structures
            scan_yaml_structure(value, file_path, findings, new_path, check_values)

    elif isinstance(data, list):
        for i, item in enumerate(data):
            new_path = f"{key_path}[{i}]"
            scan_yaml_structure(item, file_path, findings, new_path, check_values)


def scan_file(file_path: Path) -> List[SecretFinding]:
    """
    Scan a single YAML file for secrets.

    Args:
        file_path: Path to YAML file

    Returns:
        List of findings
    """
    findings: List[SecretFinding] = []

    data = load_yaml_file(file_path)
    if data is None:
        return findings

    scan_yaml_structure(data, file_path, findings)

    return findings


def scan_directory(directory: Path, recursive: bool = True) -> List[SecretFinding]:
    """
    Scan directory for secrets in YAML files.

    Args:
        directory: Directory to scan
        recursive: Whether to scan recursively

    Returns:
        List of findings
    """
    pattern = "**/*.yaml" if recursive else "*.yaml"
    yaml_files = list(directory.glob(pattern))

    findings: List[SecretFinding] = []

    for file_path in yaml_files:
        file_findings = scan_file(file_path)
        findings.extend(file_findings)

    return findings


def generate_report(findings: List[SecretFinding], show_info: bool = False) -> None:
    """
    Generate and print security report.

    Args:
        findings: List of security findings
        show_info: Whether to show info-level findings
    """
    # Filter findings by severity
    if not show_info:
        findings = [f for f in findings if f.severity != 'info']

    if not findings:
        success_print("No security issues found")
        return

    # Group by severity
    by_severity: Dict[str, List[SecretFinding]] = {
        'critical': [],
        'high': [],
        'medium': [],
        'low': [],
        'info': [],
    }

    for finding in findings:
        by_severity[finding.severity].append(finding)

    # Print summary
    color_print("\nSecurity Scan Report", Colors.BOLD)
    color_print("=" * 80, Colors.BOLD)

    total = len(findings)
    critical = len(by_severity['critical'])
    high = len(by_severity['high'])
    medium = len(by_severity['medium'])
    low = len(by_severity['low'])
    info = len(by_severity['info'])

    print(f"\nTotal findings: {total}")
    if critical > 0:
        color_print(f"  Critical: {critical}", Colors.RED)
    if high > 0:
        color_print(f"  High: {high}", Colors.RED)
    if medium > 0:
        color_print(f"  Medium: {medium}", Colors.YELLOW)
    if low > 0:
        color_print(f"  Low: {low}", Colors.YELLOW)
    if info > 0:
        color_print(f"  Info: {info}", Colors.BLUE)

    # Print findings by severity
    for severity in ['critical', 'high', 'medium', 'low', 'info']:
        severity_findings = by_severity[severity]
        if not severity_findings:
            continue

        print(f"\n{severity.upper()} Severity Findings:")
        print("-" * 80)

        for finding in severity_findings:
            print(f"\n{finding}")

    # Recommendations
    color_print("\nRecommendations:", Colors.BOLD)
    print("""
1. Never commit plaintext secrets to version control
2. Use environment variables for sensitive values
3. Consider using a secrets management solution (Vault, AWS Secrets Manager, etc.)
4. Use strong, unique passwords (at least 16 characters)
5. Rotate credentials regularly
6. Use different credentials for development, staging, and production
7. Enable encryption at rest for configuration files containing secrets
8. Review and audit access to configuration files regularly
    """)


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Scan YAML files for potential secrets and security issues",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Scan a single file
  %(prog)s config/global.yaml

  # Scan entire directory recursively
  %(prog)s config/ --recursive

  # Show all findings including info level
  %(prog)s config/ --show-info

  # Export findings to JSON
  %(prog)s config/ --export findings.json

  # Fail on any findings (for CI/CD)
  %(prog)s config/ --strict

Exit codes:
  0 - No issues found (or only info-level if --show-info not used)
  1 - Security issues found
  2 - Execution error
        """
    )

    parser.add_argument(
        "path",
        type=Path,
        help="Path to YAML file or directory to scan"
    )

    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Recursively scan directory"
    )

    parser.add_argument(
        "--show-info",
        action="store_true",
        help="Show info-level findings (informational only)"
    )

    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit with error on any findings (including info)"
    )

    parser.add_argument(
        "--export",
        type=Path,
        help="Export findings to JSON file"
    )

    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output"
    )

    args = parser.parse_args()

    # Disable colors if requested
    if args.no_color:
        for attr in dir(Colors):
            if not attr.startswith('_'):
                setattr(Colors, attr, '')

    try:
        # Validate path
        if not args.path.exists():
            error_print(f"Path does not exist: {args.path}")
            return 2

        # Scan for secrets
        findings: List[SecretFinding] = []

        if args.path.is_file():
            info_print(f"Scanning file: {args.path}")
            findings = scan_file(args.path)
        elif args.path.is_dir():
            info_print(f"Scanning directory: {args.path}")
            findings = scan_directory(args.path, args.recursive)
        else:
            error_print(f"Path is neither file nor directory: {args.path}")
            return 2

        # Generate report
        generate_report(findings, args.show_info)

        # Export to JSON if requested
        if args.export:
            import json

            export_data = []
            for finding in findings:
                export_data.append({
                    'file': str(finding.file_path),
                    'key_path': finding.key_path,
                    'severity': finding.severity,
                    'reason': finding.reason,
                    'suggestion': finding.suggestion,
                })

            with open(args.export, 'w', encoding='utf-8') as f:
                json.dump(export_data, f, indent=2)

            success_print(f"Findings exported to: {args.export}")

        # Determine exit code
        if args.strict:
            return 1 if findings else 0
        else:
            # Only fail on medium or higher
            serious = [f for f in findings if f.severity in ('critical', 'high', 'medium')]
            return 1 if serious else 0

    except KeyboardInterrupt:
        print("\n")
        warning_print("Scan interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
