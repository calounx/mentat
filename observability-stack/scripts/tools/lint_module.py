#!/usr/bin/env python3
"""
Module Linter for Observability Stack

Checks module.yaml completeness, validates referenced files exist,
checks for required fields, validates version format, and checks documentation.
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

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


class LintIssue:
    """Represents a linting issue."""

    def __init__(
        self,
        severity: str,
        category: str,
        message: str,
        fix: Optional[str] = None
    ):
        """
        Initialize lint issue.

        Args:
            severity: 'error', 'warning', 'info'
            category: Issue category (e.g., 'structure', 'files', 'documentation')
            message: Issue description
            fix: Suggested fix
        """
        self.severity = severity
        self.category = category
        self.message = message
        self.fix = fix

    def __str__(self) -> str:
        """String representation."""
        severity_colors = {
            'error': Colors.RED,
            'warning': Colors.YELLOW,
            'info': Colors.BLUE,
        }

        severity_symbols = {
            'error': '✗',
            'warning': '⚠',
            'info': 'ℹ',
        }

        color = severity_colors.get(self.severity, Colors.RESET)
        symbol = severity_symbols.get(self.severity, '•')
        severity_str = f"{color}{symbol} {self.severity.upper()}{Colors.RESET}"

        lines = [f"{severity_str} [{self.category}] {self.message}"]

        if self.fix:
            lines.append(f"  {Colors.CYAN}Fix:{Colors.RESET} {self.fix}")

        return "\n".join(lines)


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


def validate_version_format(version: str) -> bool:
    """Check if version follows semver format (X.Y.Z)."""
    pattern = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$')
    return bool(pattern.match(version))


def validate_port(port: Any) -> bool:
    """Validate port number."""
    if not isinstance(port, int):
        return False
    return 1024 <= port <= 65535


def check_required_fields(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check for required top-level fields.

    Args:
        data: Module data
        issues: List to append issues to
    """
    required_sections = {
        'module': 'Module metadata section',
        'detection': 'Service detection rules',
        'installation': 'Installation configuration',
        'exporter': 'Exporter runtime configuration',
        'prometheus': 'Prometheus scrape configuration',
    }

    for section, description in required_sections.items():
        if section not in data:
            issues.append(LintIssue(
                'error',
                'structure',
                f"Missing required section: '{section}' ({description})",
                f"Add '{section}:' section to module.yaml"
            ))


def check_module_metadata(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check module metadata section.

    Args:
        data: Module data
        issues: List to append issues to
    """
    if 'module' not in data:
        return

    module = data['module']

    required_fields = {
        'name': 'Module identifier',
        'display_name': 'Human-readable name',
        'version': 'Module version',
        'description': 'Module description',
        'category': 'Module category',
    }

    for field, description in required_fields.items():
        if field not in module:
            issues.append(LintIssue(
                'error',
                'metadata',
                f"Missing required field: module.{field} ({description})",
                f"Add '{field}:' to module section"
            ))
        elif not module[field]:
            issues.append(LintIssue(
                'error',
                'metadata',
                f"Empty value: module.{field}",
                f"Provide a value for module.{field}"
            ))

    # Validate version format
    if 'version' in module and module['version']:
        if not validate_version_format(module['version']):
            issues.append(LintIssue(
                'error',
                'metadata',
                f"Invalid version format: '{module['version']}' (expected X.Y.Z)",
                "Use semantic versioning format (e.g., 1.0.0)"
            ))

    # Validate category
    valid_categories = {'system', 'database', 'webserver', 'security', 'application', 'network'}
    if 'category' in module and module['category'] not in valid_categories:
        issues.append(LintIssue(
            'warning',
            'metadata',
            f"Unknown category: '{module['category']}'",
            f"Use one of: {', '.join(sorted(valid_categories))}"
        ))

    # Check for maintainer (optional but recommended)
    if 'maintainer' not in module:
        issues.append(LintIssue(
            'info',
            'metadata',
            "Missing optional field: module.maintainer",
            "Add maintainer information for better documentation"
        ))


def check_installation_config(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check installation configuration.

    Args:
        data: Module data
        issues: List to append issues to
    """
    if 'installation' not in data:
        return

    installation = data['installation']

    # Check binary configuration
    if 'binary' not in installation:
        issues.append(LintIssue(
            'error',
            'installation',
            "Missing required section: installation.binary",
            "Add binary installation configuration"
        ))
    else:
        binary = installation['binary']
        required_binary_fields = ['url', 'archive_type', 'binary_name', 'install_path']

        for field in required_binary_fields:
            if field not in binary:
                issues.append(LintIssue(
                    'error',
                    'installation',
                    f"Missing required field: installation.binary.{field}",
                    f"Add '{field}:' to installation.binary section"
                ))

        # Check install path is absolute
        if 'install_path' in binary and binary['install_path']:
            if not binary['install_path'].startswith('/'):
                issues.append(LintIssue(
                    'error',
                    'installation',
                    "installation.binary.install_path must be an absolute path",
                    "Start install_path with '/'"
                ))

    # Check system configuration
    if 'system' not in installation:
        issues.append(LintIssue(
            'error',
            'installation',
            "Missing required section: installation.system",
            "Add system user/group configuration"
        ))
    else:
        system = installation['system']
        required_system_fields = ['user', 'group']

        for field in required_system_fields:
            if field not in system:
                issues.append(LintIssue(
                    'error',
                    'installation',
                    f"Missing required field: installation.system.{field}",
                    f"Add '{field}:' to installation.system section"
                ))


def check_exporter_config(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check exporter runtime configuration.

    Args:
        data: Module data
        issues: List to append issues to
    """
    if 'exporter' not in data:
        return

    exporter = data['exporter']

    # Check port
    if 'port' not in exporter:
        issues.append(LintIssue(
            'error',
            'exporter',
            "Missing required field: exporter.port",
            "Add port number to exporter section"
        ))
    elif not validate_port(exporter['port']):
        issues.append(LintIssue(
            'error',
            'exporter',
            f"Invalid port number: {exporter['port']} (must be 1024-65535)",
            "Use a port number between 1024 and 65535"
        ))

    # Check health check (recommended)
    if 'health_check' not in exporter:
        issues.append(LintIssue(
            'warning',
            'exporter',
            "Missing health check configuration",
            "Add health_check section for better monitoring"
        ))


def check_prometheus_config(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check Prometheus scrape configuration.

    Args:
        data: Module data
        issues: List to append issues to
    """
    if 'prometheus' not in data:
        return

    prometheus = data['prometheus']

    # Check job name
    if 'job_name' not in prometheus:
        issues.append(LintIssue(
            'error',
            'prometheus',
            "Missing required field: prometheus.job_name",
            "Add job_name to prometheus section"
        ))


def check_referenced_files(
    module_dir: Path,
    data: Dict[str, Any],
    issues: List[LintIssue]
) -> None:
    """
    Check that referenced files exist.

    Args:
        module_dir: Directory containing module.yaml
        data: Module data
        issues: List to append issues to
    """
    # Check dashboard file
    if 'dashboard' in data:
        dashboard = data['dashboard']
        if 'file' in dashboard:
            dashboard_file = module_dir / dashboard['file']
            if not dashboard_file.exists():
                issues.append(LintIssue(
                    'error',
                    'files',
                    f"Dashboard file not found: {dashboard['file']}",
                    f"Create dashboard file at {dashboard_file}"
                ))
            elif dashboard_file.stat().st_size == 0:
                issues.append(LintIssue(
                    'warning',
                    'files',
                    f"Dashboard file is empty: {dashboard['file']}",
                    "Add dashboard JSON content"
                ))

    # Check alerts file
    if 'alerts' in data:
        alerts = data['alerts']
        if 'file' in alerts:
            alerts_file = module_dir / alerts['file']
            if not alerts_file.exists():
                issues.append(LintIssue(
                    'error',
                    'files',
                    f"Alerts file not found: {alerts['file']}",
                    f"Create alerts file at {alerts_file}"
                ))
            elif alerts_file.stat().st_size == 0:
                issues.append(LintIssue(
                    'warning',
                    'files',
                    f"Alerts file is empty: {alerts['file']}",
                    "Add alert rules"
                ))


def check_documentation(data: Dict[str, Any], issues: List[LintIssue]) -> None:
    """
    Check documentation completeness.

    Args:
        data: Module data
        issues: List to append issues to
    """
    if 'documentation' not in data:
        issues.append(LintIssue(
            'warning',
            'documentation',
            "Missing documentation section",
            "Add documentation section with setup_instructions and troubleshooting"
        ))
        return

    documentation = data['documentation']

    # Check setup instructions
    if 'setup_instructions' not in documentation:
        issues.append(LintIssue(
            'warning',
            'documentation',
            "Missing setup instructions",
            "Add setup_instructions to documentation section"
        ))
    elif not documentation['setup_instructions'] or len(documentation['setup_instructions'].strip()) < 50:
        issues.append(LintIssue(
            'info',
            'documentation',
            "Setup instructions are very brief",
            "Expand setup_instructions with more detail"
        ))

    # Check troubleshooting
    if 'troubleshooting' not in documentation:
        issues.append(LintIssue(
            'info',
            'documentation',
            "Missing troubleshooting section",
            "Add common troubleshooting tips"
        ))
    elif not documentation['troubleshooting']:
        issues.append(LintIssue(
            'info',
            'documentation',
            "Troubleshooting section is empty",
            "Add common issues and solutions"
        ))


def lint_module(module_file: Path) -> List[LintIssue]:
    """
    Lint a module.yaml file.

    Args:
        module_file: Path to module.yaml

    Returns:
        List of lint issues
    """
    issues: List[LintIssue] = []

    # Load module data
    data = load_yaml_file(module_file)
    if data is None:
        issues.append(LintIssue(
            'error',
            'structure',
            "Failed to parse module.yaml",
            "Fix YAML syntax errors"
        ))
        return issues

    # Run checks
    check_required_fields(data, issues)
    check_module_metadata(data, issues)
    check_installation_config(data, issues)
    check_exporter_config(data, issues)
    check_prometheus_config(data, issues)
    check_referenced_files(module_file.parent, data, issues)
    check_documentation(data, issues)

    return issues


def generate_report(
    module_file: Path,
    issues: List[LintIssue],
    show_info: bool = False
) -> None:
    """
    Generate and print lint report.

    Args:
        module_file: Path to module file
        issues: List of lint issues
        show_info: Whether to show info-level issues
    """
    # Filter issues
    if not show_info:
        issues = [i for i in issues if i.severity != 'info']

    color_print(f"\nLint Report: {module_file}", Colors.BOLD)
    color_print("=" * 80, Colors.BOLD)

    if not issues:
        success_print("\nNo issues found - module is well-formed")
        return

    # Count by severity
    errors = [i for i in issues if i.severity == 'error']
    warnings = [i for i in issues if i.severity == 'warning']
    infos = [i for i in issues if i.severity == 'info']

    print(f"\nTotal issues: {len(issues)}")
    if errors:
        color_print(f"  Errors: {len(errors)}", Colors.RED)
    if warnings:
        color_print(f"  Warnings: {len(warnings)}", Colors.YELLOW)
    if infos:
        color_print(f"  Info: {len(infos)}", Colors.BLUE)

    # Group by category
    by_category: Dict[str, List[LintIssue]] = {}
    for issue in issues:
        if issue.category not in by_category:
            by_category[issue.category] = []
        by_category[issue.category].append(issue)

    # Print issues by category
    for category in sorted(by_category.keys()):
        category_issues = by_category[category]
        print(f"\n{Colors.CYAN}{category.upper()}{Colors.RESET} ({len(category_issues)} issues):")
        print("-" * 80)

        for issue in category_issues:
            print(issue)


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Lint module.yaml files for completeness and correctness",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Lint a single module
  %(prog)s modules/_core/node_exporter/module.yaml

  # Lint all modules in directory
  %(prog)s modules/ --recursive

  # Show info-level issues
  %(prog)s modules/ --show-info

  # Strict mode (fail on warnings)
  %(prog)s modules/ --strict

Exit codes:
  0 - No issues (or only info-level if --show-info not used)
  1 - Issues found
  2 - Execution error
        """
    )

    parser.add_argument(
        "path",
        type=Path,
        help="Path to module.yaml file or modules directory"
    )

    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Recursively lint all module.yaml files in directory"
    )

    parser.add_argument(
        "--show-info",
        action="store_true",
        help="Show info-level issues (informational only)"
    )

    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit with error on any issues (including warnings)"
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
        # Validate path exists
        if not args.path.exists():
            error_print(f"Path does not exist: {args.path}")
            return 2

        # Lint file or directory
        all_issues: List[LintIssue] = []

        if args.path.is_file():
            if args.path.name != "module.yaml":
                warning_print("File is not named 'module.yaml'")

            issues = lint_module(args.path)
            generate_report(args.path, issues, args.show_info)
            all_issues = issues

        elif args.path.is_dir():
            pattern = "**/module.yaml" if args.recursive else "module.yaml"
            module_files = list(args.path.glob(pattern))

            if not module_files:
                warning_print(f"No module.yaml files found in {args.path}")
                return 0

            info_print(f"Linting {len(module_files)} module(s)...")

            for module_file in module_files:
                issues = lint_module(module_file)
                generate_report(module_file, issues, args.show_info)
                all_issues.extend(issues)
                print()

            # Summary
            color_print("Overall Summary:", Colors.BOLD)
            total_errors = len([i for i in all_issues if i.severity == 'error'])
            total_warnings = len([i for i in all_issues if i.severity == 'warning'])
            total_infos = len([i for i in all_issues if i.severity == 'info'])

            print(f"  Modules checked: {len(module_files)}")
            if total_errors > 0:
                color_print(f"  Total errors: {total_errors}", Colors.RED)
            if total_warnings > 0:
                color_print(f"  Total warnings: {total_warnings}", Colors.YELLOW)
            if total_infos > 0:
                color_print(f"  Total info: {total_infos}", Colors.BLUE)

        else:
            error_print(f"Path is neither file nor directory: {args.path}")
            return 2

        # Determine exit code
        if args.strict:
            # Fail on any issue
            return 1 if all_issues else 0
        else:
            # Only fail on errors
            errors = [i for i in all_issues if i.severity == 'error']
            return 1 if errors else 0

    except KeyboardInterrupt:
        print("\n")
        warning_print("Linting interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
