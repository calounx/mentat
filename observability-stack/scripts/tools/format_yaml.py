#!/usr/bin/env python3
"""
YAML Pretty-Printer for Observability Stack

Normalizes indentation, sorts keys (optionally), validates syntax,
and fixes common formatting issues.
"""

import argparse
import sys
from io import StringIO
from pathlib import Path
from typing import Any, Dict, List, Optional

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


def load_yaml_file(file_path: Path) -> Optional[Dict[str, Any]]:
    """Load and parse YAML file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            return yaml.safe_load(content)
    except yaml.YAMLError as e:
        error_print(f"YAML parsing error in {file_path}: {e}")
        return None
    except FileNotFoundError:
        error_print(f"File not found: {file_path}")
        return None
    except Exception as e:
        error_print(f"Error reading {file_path}: {e}")
        return None


def sort_dict_recursive(data: Any, sort_keys: bool = True) -> Any:
    """
    Recursively sort dictionary keys.

    Args:
        data: Data structure to sort
        sort_keys: Whether to sort keys alphabetically

    Returns:
        Sorted data structure
    """
    if not sort_keys:
        return data

    if isinstance(data, dict):
        return {k: sort_dict_recursive(v, sort_keys) for k, v in sorted(data.items())}
    elif isinstance(data, list):
        return [sort_dict_recursive(item, sort_keys) for item in data]
    else:
        return data


class CustomYAMLDumper(yaml.SafeDumper):
    """Custom YAML dumper with better formatting."""

    def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
        """Increase indentation."""
        return super().increase_indent(flow, False)


def represent_none(self, _) -> Any:
    """Represent None as empty string instead of 'null'."""
    return self.represent_scalar('tag:yaml.org,2002:null', '')


# Configure custom dumper
CustomYAMLDumper.add_representer(type(None), represent_none)


def format_yaml(
    data: Any,
    sort_keys: bool = False,
    indent: int = 2,
    width: int = 80,
    preserve_quotes: bool = True
) -> str:
    """
    Format YAML data with specified options.

    Args:
        data: YAML data to format
        sort_keys: Whether to sort keys alphabetically
        indent: Number of spaces for indentation
        width: Line width for wrapping
        preserve_quotes: Preserve quotes on strings

    Returns:
        Formatted YAML string
    """
    # Sort keys if requested
    if sort_keys:
        data = sort_dict_recursive(data, sort_keys)

    # Dump YAML with custom formatting
    stream = StringIO()

    yaml.dump(
        data,
        stream,
        Dumper=CustomYAMLDumper,
        default_flow_style=False,
        allow_unicode=True,
        encoding=None,
        indent=indent,
        width=width,
        sort_keys=False  # We handle sorting separately
    )

    formatted = stream.getvalue()

    # Post-processing fixes
    formatted = fix_common_issues(formatted)

    return formatted


def fix_common_issues(content: str) -> str:
    """
    Fix common YAML formatting issues.

    Args:
        content: YAML content

    Returns:
        Fixed content
    """
    lines = content.split('\n')
    fixed_lines: List[str] = []

    for i, line in enumerate(lines):
        # Remove trailing whitespace
        line = line.rstrip()

        # Ensure empty lines between top-level keys (except first)
        if line and not line.startswith(' ') and i > 0:
            prev_line = fixed_lines[-1] if fixed_lines else ''
            if prev_line and not prev_line.startswith('#'):
                # Check if previous line was also a top-level key
                if i > 0 and lines[i-1] and not lines[i-1].startswith(' ') and not lines[i-1].startswith('#'):
                    fixed_lines.append('')

        fixed_lines.append(line)

    # Remove multiple consecutive empty lines
    result_lines: List[str] = []
    prev_empty = False

    for line in fixed_lines:
        is_empty = not line.strip()

        if is_empty and prev_empty:
            continue  # Skip multiple empty lines

        result_lines.append(line)
        prev_empty = is_empty

    # Ensure file ends with single newline
    result = '\n'.join(result_lines)
    if not result.endswith('\n'):
        result += '\n'

    return result


def validate_yaml_syntax(content: str) -> tuple[bool, Optional[str]]:
    """
    Validate YAML syntax.

    Args:
        content: YAML content to validate

    Returns:
        Tuple of (is_valid, error_message)
    """
    try:
        yaml.safe_load(content)
        return True, None
    except yaml.YAMLError as e:
        return False, str(e)


def format_file(
    file_path: Path,
    output_path: Optional[Path] = None,
    sort_keys: bool = False,
    indent: int = 2,
    width: int = 80,
    in_place: bool = False,
    check_only: bool = False
) -> bool:
    """
    Format a single YAML file.

    Args:
        file_path: Path to input file
        output_path: Path to output file (None for stdout)
        sort_keys: Whether to sort keys
        indent: Indentation spaces
        width: Line width
        in_place: Edit file in-place
        check_only: Only check if formatting is needed

    Returns:
        True if successful, False otherwise
    """
    # Load file
    data = load_yaml_file(file_path)
    if data is None:
        return False

    # Format YAML
    try:
        formatted = format_yaml(data, sort_keys, indent, width)
    except Exception as e:
        error_print(f"Error formatting {file_path}: {e}")
        return False

    # Validate formatted output
    is_valid, error = validate_yaml_syntax(formatted)
    if not is_valid:
        error_print(f"Formatted YAML is invalid: {error}")
        return False

    # Check mode - compare with original
    if check_only:
        with open(file_path, 'r', encoding='utf-8') as f:
            original = f.read()

        if original == formatted:
            success_print(f"File is already formatted: {file_path}")
            return True
        else:
            warning_print(f"File needs formatting: {file_path}")
            return False

    # Determine output location
    if in_place:
        output_path = file_path
    elif output_path is None:
        # Print to stdout
        print(formatted, end='')
        return True

    # Write formatted output
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(formatted)

        if in_place:
            success_print(f"Formatted in-place: {file_path}")
        else:
            success_print(f"Formatted {file_path} -> {output_path}")

        return True

    except Exception as e:
        error_print(f"Error writing {output_path}: {e}")
        return False


def format_directory(
    directory: Path,
    recursive: bool = True,
    sort_keys: bool = False,
    indent: int = 2,
    width: int = 80,
    in_place: bool = False,
    check_only: bool = False
) -> tuple[int, int]:
    """
    Format all YAML files in a directory.

    Args:
        directory: Directory to process
        recursive: Process recursively
        sort_keys: Whether to sort keys
        indent: Indentation spaces
        width: Line width
        in_place: Edit files in-place
        check_only: Only check formatting

    Returns:
        Tuple of (success_count, failure_count)
    """
    pattern = "**/*.yaml" if recursive else "*.yaml"
    yaml_files = list(directory.glob(pattern))

    if not yaml_files:
        warning_print(f"No YAML files found in {directory}")
        return 0, 0

    success_count = 0
    failure_count = 0

    for file_path in yaml_files:
        if format_file(file_path, None, sort_keys, indent, width, in_place, check_only):
            success_count += 1
        else:
            failure_count += 1

    return success_count, failure_count


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Format and normalize YAML configuration files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Format a file and print to stdout
  %(prog)s config.yaml

  # Format file in-place
  %(prog)s config.yaml --in-place

  # Format with sorted keys
  %(prog)s config.yaml --sort-keys --in-place

  # Format to different file
  %(prog)s input.yaml --output formatted.yaml

  # Format all YAML files in directory
  %(prog)s config/ --recursive --in-place

  # Check if files need formatting (for CI)
  %(prog)s config/ --check

  # Custom indentation and line width
  %(prog)s config.yaml --indent 4 --width 120

Exit codes:
  0 - Success (or all files already formatted in --check mode)
  1 - Formatting errors or files need formatting in --check mode
  2 - Execution error
        """
    )

    parser.add_argument(
        "path",
        type=Path,
        help="Path to YAML file or directory"
    )

    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Output file path (default: stdout or in-place if --in-place)"
    )

    parser.add_argument(
        "-i", "--in-place",
        action="store_true",
        help="Edit file(s) in-place"
    )

    parser.add_argument(
        "-s", "--sort-keys",
        action="store_true",
        help="Sort keys alphabetically"
    )

    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        help="Number of spaces for indentation (default: 2)"
    )

    parser.add_argument(
        "--width",
        type=int,
        default=80,
        help="Line width for wrapping (default: 80)"
    )

    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Process directory recursively"
    )

    parser.add_argument(
        "-c", "--check",
        action="store_true",
        help="Check if formatting is needed (don't modify files)"
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

        # Process file or directory
        if args.path.is_file():
            success = format_file(
                args.path,
                args.output,
                args.sort_keys,
                args.indent,
                args.width,
                args.in_place,
                args.check
            )
            return 0 if success else 1

        elif args.path.is_dir():
            if args.output:
                error_print("Cannot specify --output when processing directory")
                return 2

            success_count, failure_count = format_directory(
                args.path,
                args.recursive,
                args.sort_keys,
                args.indent,
                args.width,
                args.in_place,
                args.check
            )

            # Print summary
            print()
            color_print("Formatting Summary:", Colors.BOLD)
            success_print(f"Successful: {success_count}")
            if failure_count > 0:
                error_print(f"Failed: {failure_count}")

            return 0 if failure_count == 0 else 1

        else:
            error_print(f"Path is neither file nor directory: {args.path}")
            return 2

    except KeyboardInterrupt:
        print("\n")
        warning_print("Formatting interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
