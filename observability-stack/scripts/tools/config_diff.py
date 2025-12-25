#!/usr/bin/env python3
"""
Configuration Diff Tool for Observability Stack

Compares two YAML configurations, highlights differences,
masks sensitive values, and generates migration plans.
"""

import argparse
import difflib
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


# Patterns to identify sensitive keys
SENSITIVE_PATTERNS: List[re.Pattern] = [
    re.compile(r'password|passwd|pwd', re.IGNORECASE),
    re.compile(r'secret|private', re.IGNORECASE),
    re.compile(r'key', re.IGNORECASE),
    re.compile(r'token|bearer', re.IGNORECASE),
    re.compile(r'credential|cred', re.IGNORECASE),
]


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


def is_sensitive_key(key: str) -> bool:
    """Check if a key name suggests sensitive data."""
    for pattern in SENSITIVE_PATTERNS:
        if pattern.search(key):
            return True
    return False


def mask_value(value: Any) -> str:
    """Mask sensitive value for display."""
    if not isinstance(value, str):
        return str(value)

    if len(value) <= 3:
        return '***'

    return f"{value[:2]}...{value[-1]}"


def mask_sensitive_data(data: Any, key_path: str = "") -> Any:
    """
    Recursively mask sensitive data in configuration.

    Args:
        data: Data to mask
        key_path: Current path in structure

    Returns:
        Data with sensitive values masked
    """
    if isinstance(data, dict):
        result = {}
        for key, value in data.items():
            new_path = f"{key_path}.{key}" if key_path else key

            if is_sensitive_key(key) and isinstance(value, str):
                result[key] = mask_value(value)
            else:
                result[key] = mask_sensitive_data(value, new_path)

        return result
    elif isinstance(data, list):
        return [mask_sensitive_data(item, f"{key_path}[]") for item in data]
    else:
        return data


class ConfigDiff:
    """Represents differences between two configurations."""

    def __init__(self) -> None:
        """Initialize empty diff."""
        self.added: List[str] = []
        self.removed: List[str] = []
        self.changed: List[Tuple[str, Any, Any]] = []

    def add_added(self, key_path: str) -> None:
        """Record an added key."""
        self.added.append(key_path)

    def add_removed(self, key_path: str) -> None:
        """Record a removed key."""
        self.removed.append(key_path)

    def add_changed(self, key_path: str, old_value: Any, new_value: Any) -> None:
        """Record a changed value."""
        self.changed.append((key_path, old_value, new_value))

    def has_differences(self) -> bool:
        """Check if there are any differences."""
        return bool(self.added or self.removed or self.changed)

    def count_differences(self) -> int:
        """Count total number of differences."""
        return len(self.added) + len(self.removed) + len(self.changed)


def compare_structures(
    old_data: Any,
    new_data: Any,
    diff: ConfigDiff,
    key_path: str = "",
    mask_secrets: bool = True
) -> None:
    """
    Recursively compare two data structures.

    Args:
        old_data: Old configuration data
        new_data: New configuration data
        diff: ConfigDiff object to populate
        key_path: Current path in structure
        mask_secrets: Whether to mask sensitive values
    """
    # Both are dicts
    if isinstance(old_data, dict) and isinstance(new_data, dict):
        old_keys = set(old_data.keys())
        new_keys = set(new_data.keys())

        # Added keys
        for key in new_keys - old_keys:
            new_path = f"{key_path}.{key}" if key_path else key
            diff.add_added(new_path)

        # Removed keys
        for key in old_keys - new_keys:
            old_path = f"{key_path}.{key}" if key_path else key
            diff.add_removed(old_path)

        # Common keys - check for changes
        for key in old_keys & new_keys:
            new_path = f"{key_path}.{key}" if key_path else key
            compare_structures(old_data[key], new_data[key], diff, new_path, mask_secrets)

    # Both are lists
    elif isinstance(old_data, list) and isinstance(new_data, list):
        if old_data != new_data:
            old_val = old_data
            new_val = new_data

            # Mask sensitive data if needed
            if mask_secrets and key_path and is_sensitive_key(key_path.split('.')[-1]):
                old_val = "[masked list]"
                new_val = "[masked list]"

            diff.add_changed(key_path, old_val, new_val)

    # Different types or values
    elif old_data != new_data:
        old_val = old_data
        new_val = new_data

        # Mask sensitive values
        if mask_secrets and key_path:
            key_name = key_path.split('.')[-1]
            if is_sensitive_key(key_name):
                if isinstance(old_val, str):
                    old_val = mask_value(old_val)
                if isinstance(new_val, str):
                    new_val = mask_value(new_val)

        diff.add_changed(key_path, old_val, new_val)


def generate_diff_report(
    diff: ConfigDiff,
    old_file: Path,
    new_file: Path,
    show_all: bool = False
) -> None:
    """
    Generate and print difference report.

    Args:
        diff: ConfigDiff object
        old_file: Path to old configuration file
        new_file: Path to new configuration file
        show_all: Show all differences in detail
    """
    color_print(f"\nConfiguration Diff Report", Colors.BOLD)
    color_print("=" * 80, Colors.BOLD)

    print(f"\nComparing:")
    print(f"  Old: {old_file}")
    print(f"  New: {new_file}")

    if not diff.has_differences():
        success_print("\nNo differences found - configurations are identical")
        return

    # Summary
    print(f"\nSummary:")
    print(f"  Added keys: {len(diff.added)}")
    print(f"  Removed keys: {len(diff.removed)}")
    print(f"  Changed values: {len(diff.changed)}")
    print(f"  Total differences: {diff.count_differences()}")

    # Added keys
    if diff.added:
        color_print(f"\nAdded Keys ({len(diff.added)}):", Colors.GREEN)
        for key_path in sorted(diff.added):
            print(f"  {Colors.GREEN}+{Colors.RESET} {key_path}")

    # Removed keys
    if diff.removed:
        color_print(f"\nRemoved Keys ({len(diff.removed)}):", Colors.RED)
        for key_path in sorted(diff.removed):
            print(f"  {Colors.RED}-{Colors.RESET} {key_path}")

    # Changed values
    if diff.changed:
        color_print(f"\nChanged Values ({len(diff.changed)}):", Colors.YELLOW)
        for key_path, old_val, new_val in sorted(diff.changed):
            print(f"\n  {Colors.YELLOW}~{Colors.RESET} {key_path}")

            if show_all:
                # Show detailed diff
                old_str = yaml.dump(old_val, default_flow_style=False).strip()
                new_str = yaml.dump(new_val, default_flow_style=False).strip()

                old_lines = old_str.split('\n')
                new_lines = new_str.split('\n')

                differ = difflib.unified_diff(
                    old_lines, new_lines,
                    lineterm='',
                    n=0
                )

                for line in differ:
                    if line.startswith('+'):
                        color_print(f"      {line}", Colors.GREEN)
                    elif line.startswith('-'):
                        color_print(f"      {line}", Colors.RED)
            else:
                # Show simple before/after
                print(f"    Old: {old_val}")
                print(f"    New: {new_val}")


def generate_migration_plan(
    diff: ConfigDiff,
    old_file: Path,
    new_file: Path
) -> None:
    """
    Generate migration plan based on differences.

    Args:
        diff: ConfigDiff object
        old_file: Path to old configuration file
        new_file: Path to new configuration file
    """
    if not diff.has_differences():
        return

    color_print("\nMigration Plan", Colors.BOLD)
    color_print("=" * 80, Colors.BOLD)

    print("\nTo migrate from old to new configuration:\n")

    step = 1

    # Handle removed keys
    if diff.removed:
        print(f"{step}. Review and handle removed keys:")
        for key_path in sorted(diff.removed):
            print(f"   - {key_path}")
            print(f"     Action: Verify this key is no longer needed")
        print()
        step += 1

    # Handle added keys
    if diff.added:
        print(f"{step}. Add new required keys:")
        for key_path in sorted(diff.added):
            print(f"   - {key_path}")
            print(f"     Action: Add this key with appropriate value")
        print()
        step += 1

    # Handle changed values
    if diff.changed:
        print(f"{step}. Update changed values:")
        for key_path, old_val, new_val in sorted(diff.changed):
            print(f"   - {key_path}")
            print(f"     Old value: {old_val}")
            print(f"     New value: {new_val}")
            print(f"     Action: Update value and verify compatibility")
        print()
        step += 1

    # General recommendations
    print(f"{step}. Validation steps:")
    print("   - Backup current configuration")
    print("   - Test new configuration in development environment")
    print("   - Run validation tools (validate_schema.py, check_ports.py)")
    print("   - Update documentation if needed")
    print("   - Plan rollback strategy")
    print()


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Compare two YAML configuration files and show differences",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compare two configuration files
  %(prog)s old-config.yaml new-config.yaml

  # Show detailed differences
  %(prog)s old-config.yaml new-config.yaml --detailed

  # Generate migration plan
  %(prog)s old-config.yaml new-config.yaml --migration-plan

  # Don't mask sensitive values
  %(prog)s old-config.yaml new-config.yaml --no-mask

  # Export diff to file
  %(prog)s old-config.yaml new-config.yaml --export diff-report.txt

Exit codes:
  0 - Files are identical (or comparison successful)
  1 - Files have differences
  2 - Execution error
        """
    )

    parser.add_argument(
        "old_config",
        type=Path,
        help="Path to old configuration file"
    )

    parser.add_argument(
        "new_config",
        type=Path,
        help="Path to new configuration file"
    )

    parser.add_argument(
        "-d", "--detailed",
        action="store_true",
        help="Show detailed unified diff for changed values"
    )

    parser.add_argument(
        "-m", "--migration-plan",
        action="store_true",
        help="Generate migration plan"
    )

    parser.add_argument(
        "--no-mask",
        action="store_true",
        help="Don't mask sensitive values (use with caution)"
    )

    parser.add_argument(
        "--export",
        type=Path,
        help="Export report to file"
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
        # Validate files exist
        if not args.old_config.exists():
            error_print(f"Old config file not found: {args.old_config}")
            return 2

        if not args.new_config.exists():
            error_print(f"New config file not found: {args.new_config}")
            return 2

        # Load configurations
        info_print(f"Loading old config: {args.old_config}")
        old_data = load_yaml_file(args.old_config)
        if old_data is None:
            return 2

        info_print(f"Loading new config: {args.new_config}")
        new_data = load_yaml_file(args.new_config)
        if new_data is None:
            return 2

        # Compare configurations
        info_print("Comparing configurations...")
        diff = ConfigDiff()
        compare_structures(old_data, new_data, diff, mask_secrets=not args.no_mask)

        # Redirect output to file if requested
        if args.export:
            original_stdout = sys.stdout
            sys.stdout = open(args.export, 'w', encoding='utf-8')

        # Generate report
        generate_diff_report(diff, args.old_config, args.new_config, args.detailed)

        # Generate migration plan if requested
        if args.migration_plan:
            generate_migration_plan(diff, args.old_config, args.new_config)

        # Restore stdout if redirected
        if args.export:
            sys.stdout.close()
            sys.stdout = original_stdout
            success_print(f"Diff report exported to: {args.export}")

        # Return exit code based on differences
        return 1 if diff.has_differences() else 0

    except KeyboardInterrupt:
        print("\n")
        warning_print("Comparison interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
