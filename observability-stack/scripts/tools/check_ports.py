#!/usr/bin/env python3
"""
Port Conflict Detector for Observability Stack

Scans module.yaml and global.yaml for port assignments, detects conflicts,
and checks if ports are available on the system.
"""

import argparse
import socket
import sys
from collections import defaultdict
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


def is_port_available(port: int, host: str = '0.0.0.0') -> bool:
    """
    Check if a port is available on the system.

    Args:
        port: Port number to check
        host: Host address to bind to

    Returns:
        True if port is available, False if in use
    """
    try:
        # Try TCP
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((host, port))
            return True
    except OSError:
        return False


def check_port_range(port: int) -> Tuple[bool, Optional[str]]:
    """
    Validate port number is in valid range.

    Args:
        port: Port number

    Returns:
        Tuple of (is_valid, warning_message)
    """
    if port < 1 or port > 65535:
        return False, f"Port {port} is out of valid range (1-65535)"

    if port < 1024:
        return True, f"Port {port} is in privileged range (< 1024), may require root"

    if port >= 49152:
        return True, f"Port {port} is in dynamic/private range (49152-65535)"

    return True, None


class PortRegistry:
    """Registry of port assignments."""

    def __init__(self) -> None:
        """Initialize empty port registry."""
        self.port_assignments: Dict[int, List[Tuple[str, str]]] = defaultdict(list)
        self.component_ports: Dict[str, int] = {}

    def register_port(self, port: int, component: str, source: str) -> None:
        """
        Register a port assignment.

        Args:
            port: Port number
            component: Component name (e.g., 'node_exporter', 'prometheus')
            source: Source of assignment (e.g., file path)
        """
        self.port_assignments[port].append((component, source))
        self.component_ports[component] = port

    def get_conflicts(self) -> Dict[int, List[Tuple[str, str]]]:
        """
        Get all port conflicts (ports assigned to multiple components).

        Returns:
            Dictionary of port -> list of (component, source) tuples
        """
        return {
            port: assignments
            for port, assignments in self.port_assignments.items()
            if len(assignments) > 1
        }

    def get_all_ports(self) -> List[int]:
        """Get sorted list of all registered ports."""
        return sorted(self.port_assignments.keys())

    def get_component_port(self, component: str) -> Optional[int]:
        """Get port assigned to a component."""
        return self.component_ports.get(component)


def scan_module_ports(modules_dir: Path, registry: PortRegistry) -> None:
    """
    Scan all module.yaml files for port assignments.

    Args:
        modules_dir: Path to modules directory
        registry: Port registry to populate
    """
    module_files = list(modules_dir.glob("**/module.yaml"))

    for module_file in module_files:
        module_data = load_yaml_file(module_file)
        if not module_data:
            continue

        # Get module name
        module_name = "unknown"
        if 'module' in module_data:
            module_name = module_data['module'].get('name', module_name)

        # Extract port from exporter section
        if 'exporter' in module_data:
            exporter = module_data['exporter']
            if 'port' in exporter:
                port = exporter['port']
                registry.register_port(port, module_name, str(module_file))


def scan_global_ports(global_file: Path, registry: PortRegistry) -> None:
    """
    Scan global.yaml for port configurations.

    Args:
        global_file: Path to global.yaml
        registry: Port registry to populate
    """
    global_data = load_yaml_file(global_file)
    if not global_data:
        return

    if 'ports' in global_data:
        ports = global_data['ports']
        for component, port in ports.items():
            if isinstance(port, int):
                registry.register_port(port, f"global:{component}", str(global_file))


def check_system_ports(registry: PortRegistry, check_availability: bool = True) -> Tuple[List[int], List[int]]:
    """
    Check if registered ports are available on the system.

    Args:
        registry: Port registry
        check_availability: Whether to actually check port availability

    Returns:
        Tuple of (available_ports, unavailable_ports)
    """
    if not check_availability:
        return [], []

    available: List[int] = []
    unavailable: List[int] = []

    for port in registry.get_all_ports():
        if is_port_available(port):
            available.append(port)
        else:
            unavailable.append(port)

    return available, unavailable


def generate_port_report(
    registry: PortRegistry,
    available_ports: List[int],
    unavailable_ports: List[int],
    check_availability: bool
) -> None:
    """
    Generate and print port usage report.

    Args:
        registry: Port registry
        available_ports: List of available ports
        unavailable_ports: List of unavailable ports
        check_availability: Whether availability was checked
    """
    all_ports = registry.get_all_ports()

    color_print("\nPort Usage Report", Colors.BOLD)
    color_print("=" * 80, Colors.BOLD)

    # Port assignments table
    color_print("\nPort Assignments:", Colors.CYAN)
    print(f"{'Port':<8} {'Component':<30} {'Status':<15} {'Source'}")
    print("-" * 80)

    for port in all_ports:
        assignments = registry.port_assignments[port]
        is_conflict = len(assignments) > 1

        for i, (component, source) in enumerate(assignments):
            port_str = str(port) if i == 0 else ""

            # Determine status
            if is_conflict:
                status = f"{Colors.RED}CONFLICT{Colors.RESET}"
            elif check_availability:
                if port in available_ports:
                    status = f"{Colors.GREEN}Available{Colors.RESET}"
                elif port in unavailable_ports:
                    status = f"{Colors.YELLOW}In Use{Colors.RESET}"
                else:
                    status = "Unknown"
            else:
                status = "Not Checked"

            # Validate port range
            is_valid, warning = check_port_range(port)
            if warning and i == 0:
                status += f" {Colors.YELLOW}⚠{Colors.RESET}"

            print(f"{port_str:<8} {component:<30} {status:<24} {Path(source).name}")

    # Conflicts section
    conflicts = registry.get_conflicts()
    if conflicts:
        color_print(f"\n{Colors.RED}Port Conflicts Detected:{Colors.RESET}", Colors.BOLD)
        for port, assignments in conflicts.items():
            error_print(f"Port {port} assigned to {len(assignments)} components:")
            for component, source in assignments:
                print(f"  - {component} (in {source})")

    # Range warnings
    color_print("\nPort Range Analysis:", Colors.CYAN)
    privileged = [p for p in all_ports if p < 1024]
    dynamic = [p for p in all_ports if p >= 49152]

    if privileged:
        warning_print(f"Privileged ports (< 1024): {', '.join(map(str, privileged))}")
        print("  These ports may require root privileges to bind")

    if dynamic:
        warning_print(f"Dynamic/private range ports (>= 49152): {', '.join(map(str, dynamic))}")
        print("  These ports may conflict with ephemeral ports")

    # System availability
    if check_availability:
        color_print("\nSystem Port Availability:", Colors.CYAN)
        if unavailable_ports:
            warning_print(f"Ports in use: {', '.join(map(str, unavailable_ports))}")
            print("  These ports are currently bound on the system")
        else:
            success_print("All configured ports are available")

    # Summary
    color_print("\nSummary:", Colors.BOLD)
    print(f"  Total ports configured: {len(all_ports)}")
    print(f"  Unique ports: {len(registry.port_assignments)}")
    print(f"  Port conflicts: {len(conflicts)}")

    if check_availability:
        print(f"  Available ports: {len(available_ports)}")
        print(f"  Ports in use: {len(unavailable_ports)}")


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Check for port conflicts and availability in observability stack",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check ports in modules directory
  %(prog)s --modules modules/

  # Check global.yaml ports
  %(prog)s --global config/global.yaml

  # Check both modules and global
  %(prog)s --modules modules/ --global config/global.yaml

  # Check system port availability
  %(prog)s --modules modules/ --check-system

  # List only conflicts
  %(prog)s --modules modules/ --conflicts-only

  # Export port list to file
  %(prog)s --modules modules/ --export ports.txt

Exit codes:
  0 - No conflicts found
  1 - Port conflicts detected
  2 - Execution error
        """
    )

    parser.add_argument(
        "-m", "--modules",
        type=Path,
        help="Path to modules directory"
    )

    parser.add_argument(
        "-g", "--global",
        dest="global_config",
        type=Path,
        help="Path to global.yaml configuration"
    )

    parser.add_argument(
        "-c", "--check-system",
        action="store_true",
        help="Check if ports are available on system (requires permissions)"
    )

    parser.add_argument(
        "--conflicts-only",
        action="store_true",
        help="Only show port conflicts"
    )

    parser.add_argument(
        "--export",
        type=Path,
        help="Export port list to file"
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

    # Validate inputs
    if not args.modules and not args.global_config:
        error_print("Must specify --modules and/or --global")
        return 2

    try:
        registry = PortRegistry()

        # Scan modules
        if args.modules:
            if not args.modules.exists():
                error_print(f"Modules directory not found: {args.modules}")
                return 2

            info_print(f"Scanning modules: {args.modules}")
            scan_module_ports(args.modules, registry)

        # Scan global config
        if args.global_config:
            if not args.global_config.exists():
                error_print(f"Global config not found: {args.global_config}")
                return 2

            info_print(f"Scanning global config: {args.global_config}")
            scan_global_ports(args.global_config, registry)

        # Check system availability
        available_ports: List[int] = []
        unavailable_ports: List[int] = []

        if args.check_system:
            info_print("Checking system port availability...")
            available_ports, unavailable_ports = check_system_ports(registry, True)

        # Generate report
        if not args.conflicts_only:
            generate_port_report(registry, available_ports, unavailable_ports, args.check_system)
        else:
            # Show only conflicts
            conflicts = registry.get_conflicts()
            if conflicts:
                error_print(f"Found {len(conflicts)} port conflicts:")
                for port, assignments in conflicts.items():
                    print(f"\nPort {port}:")
                    for component, source in assignments:
                        print(f"  - {component} (in {source})")
            else:
                success_print("No port conflicts detected")

        # Export port list
        if args.export:
            with open(args.export, 'w', encoding='utf-8') as f:
                for port in registry.get_all_ports():
                    assignments = registry.port_assignments[port]
                    for component, _ in assignments:
                        f.write(f"{port}\t{component}\n")
            success_print(f"Port list exported to: {args.export}")

        # Determine exit code
        conflicts = registry.get_conflicts()
        if conflicts:
            return 1

        return 0

    except KeyboardInterrupt:
        print("\n")
        warning_print("Operation interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
