#!/usr/bin/env python3
"""
Module Dependency Resolver for Observability Stack

Parses module dependencies, builds dependency graph, detects circular dependencies,
and outputs installation order.
"""

import argparse
import sys
from collections import defaultdict, deque
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


class DependencyGraph:
    """Represents module dependency graph."""

    def __init__(self) -> None:
        """Initialize empty dependency graph."""
        self.modules: Dict[str, Dict[str, Any]] = {}
        self.dependencies: Dict[str, List[str]] = defaultdict(list)
        self.reverse_deps: Dict[str, List[str]] = defaultdict(list)

    def add_module(self, name: str, config: Dict[str, Any]) -> None:
        """
        Add module to graph.

        Args:
            name: Module name
            config: Module configuration
        """
        self.modules[name] = config

        # Extract dependencies
        deps: List[str] = []
        if 'installation' in config:
            installation = config['installation']
            if 'dependencies' in installation:
                module_deps = installation['dependencies']
                if 'modules' in module_deps:
                    deps = module_deps['modules']

        self.dependencies[name] = deps

        # Build reverse dependency map
        for dep in deps:
            self.reverse_deps[dep].append(name)

    def get_all_modules(self) -> List[str]:
        """Get list of all module names."""
        return list(self.modules.keys())

    def get_dependencies(self, module: str) -> List[str]:
        """Get direct dependencies of a module."""
        return self.dependencies.get(module, [])

    def get_dependents(self, module: str) -> List[str]:
        """Get modules that depend on this module."""
        return self.reverse_deps.get(module, [])

    def validate_dependencies(self) -> Tuple[bool, List[str]]:
        """
        Validate that all dependencies are satisfied.

        Returns:
            Tuple of (is_valid, list_of_errors)
        """
        errors: List[str] = []
        all_modules = set(self.modules.keys())

        for module, deps in self.dependencies.items():
            for dep in deps:
                if dep not in all_modules:
                    errors.append(
                        f"Module '{module}' depends on '{dep}' which is not available"
                    )

        return len(errors) == 0, errors

    def detect_circular_dependencies(self) -> Tuple[bool, List[List[str]]]:
        """
        Detect circular dependencies using DFS.

        Returns:
            Tuple of (has_cycles, list_of_cycles)
        """
        cycles: List[List[str]] = []
        visited: Set[str] = set()
        rec_stack: Set[str] = set()
        path: List[str] = []

        def dfs(node: str) -> bool:
            """DFS helper to detect cycles."""
            visited.add(node)
            rec_stack.add(node)
            path.append(node)

            for neighbor in self.dependencies.get(node, []):
                if neighbor not in visited:
                    if dfs(neighbor):
                        return True
                elif neighbor in rec_stack:
                    # Found cycle
                    cycle_start = path.index(neighbor)
                    cycle = path[cycle_start:] + [neighbor]
                    cycles.append(cycle)
                    return True

            path.pop()
            rec_stack.remove(node)
            return False

        for module in self.modules:
            if module not in visited:
                dfs(module)

        return len(cycles) > 0, cycles

    def topological_sort(self) -> Optional[List[str]]:
        """
        Perform topological sort to determine installation order.

        Returns:
            List of modules in installation order, or None if cycles detected
        """
        # Check for cycles first
        has_cycles, cycles = self.detect_circular_dependencies()
        if has_cycles:
            return None

        # Kahn's algorithm for topological sort
        in_degree: Dict[str, int] = {module: 0 for module in self.modules}

        # Calculate in-degrees
        for module, deps in self.dependencies.items():
            for dep in deps:
                if dep in in_degree:
                    in_degree[module] += 1

        # Queue of modules with no dependencies
        queue: deque = deque([m for m, deg in in_degree.items() if deg == 0])
        result: List[str] = []

        while queue:
            module = queue.popleft()
            result.append(module)

            # Reduce in-degree for dependents
            for dependent in self.reverse_deps.get(module, []):
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    queue.append(dependent)

        # If not all modules processed, there's a cycle (shouldn't happen due to check above)
        if len(result) != len(self.modules):
            return None

        return result

    def get_module_level(self, module: str, cache: Optional[Dict[str, int]] = None) -> int:
        """
        Get dependency level of module (0 = no deps, 1 = depends on level 0, etc).

        Args:
            module: Module name
            cache: Cache of computed levels

        Returns:
            Dependency level
        """
        if cache is None:
            cache = {}

        if module in cache:
            return cache[module]

        deps = self.dependencies.get(module, [])
        if not deps:
            level = 0
        else:
            level = 1 + max(self.get_module_level(dep, cache) for dep in deps)

        cache[module] = level
        return level


def load_all_modules(modules_dir: Path) -> DependencyGraph:
    """
    Load all modules from directory into dependency graph.

    Args:
        modules_dir: Path to modules directory

    Returns:
        Dependency graph
    """
    graph = DependencyGraph()

    # Find all module.yaml files
    module_files = list(modules_dir.glob("**/module.yaml"))

    if not module_files:
        warning_print(f"No module.yaml files found in {modules_dir}")
        return graph

    info_print(f"Loading modules from {modules_dir}")

    for module_file in module_files:
        module_data = load_yaml_file(module_file)
        if module_data and 'module' in module_data:
            module_name = module_data['module'].get('name')
            if module_name:
                graph.add_module(module_name, module_data)
                info_print(f"  Loaded: {module_name}")

    return graph


def print_dependency_tree(graph: DependencyGraph, module: str, indent: int = 0, visited: Optional[Set[str]] = None) -> None:
    """
    Print dependency tree for a module.

    Args:
        graph: Dependency graph
        module: Module name
        indent: Current indentation level
        visited: Set of already visited modules (to detect cycles in display)
    """
    if visited is None:
        visited = set()

    prefix = "  " * indent
    symbol = "└─" if indent > 0 else ""

    # Check if we've seen this before (cycle or repeated)
    if module in visited:
        color_print(f"{prefix}{symbol} {module} (circular/repeated)", Colors.YELLOW)
        return

    visited.add(module)

    # Print module
    deps = graph.get_dependencies(module)
    if deps:
        color_print(f"{prefix}{symbol} {module}", Colors.CYAN)
        for dep in deps:
            print_dependency_tree(graph, dep, indent + 1, visited.copy())
    else:
        color_print(f"{prefix}{symbol} {module}", Colors.GREEN)


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Resolve module dependencies and determine installation order",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze dependencies in modules directory
  %(prog)s modules/

  # Show dependency tree for specific module
  %(prog)s modules/ --tree node_exporter

  # Output installation order to file
  %(prog)s modules/ --output install-order.txt

  # Show detailed dependency information
  %(prog)s modules/ --verbose

  # Check for circular dependencies only
  %(prog)s modules/ --check-cycles

  # Show modules grouped by dependency level
  %(prog)s modules/ --by-level

Exit codes:
  0 - Success (all dependencies satisfied, no cycles)
  1 - Dependency errors or circular dependencies detected
  2 - Execution error
        """
    )

    parser.add_argument(
        "modules_dir",
        type=Path,
        help="Path to modules directory"
    )

    parser.add_argument(
        "-t", "--tree",
        metavar="MODULE",
        help="Show dependency tree for specific module"
    )

    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Write installation order to file"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed dependency information"
    )

    parser.add_argument(
        "--check-cycles",
        action="store_true",
        help="Only check for circular dependencies"
    )

    parser.add_argument(
        "--by-level",
        action="store_true",
        help="Group modules by dependency level"
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
        # Validate modules directory
        if not args.modules_dir.exists():
            error_print(f"Modules directory not found: {args.modules_dir}")
            return 2

        # Load modules
        graph = load_all_modules(args.modules_dir)

        if not graph.get_all_modules():
            error_print("No modules found")
            return 1

        success_print(f"Loaded {len(graph.get_all_modules())} modules")
        print()

        # Validate dependencies
        is_valid, errors = graph.validate_dependencies()
        if not is_valid:
            error_print("Dependency validation failed:")
            for error in errors:
                print(f"  {Colors.RED}✗{Colors.RESET} {error}")
            print()
            return 1

        success_print("All dependencies satisfied")
        print()

        # Check for circular dependencies
        has_cycles, cycles = graph.detect_circular_dependencies()
        if has_cycles:
            error_print("Circular dependencies detected:")
            for cycle in cycles:
                cycle_str = " -> ".join(cycle)
                print(f"  {Colors.RED}✗{Colors.RESET} {cycle_str}")
            print()

            if args.check_cycles:
                return 1
            else:
                warning_print("Cannot generate installation order due to circular dependencies")
                return 1

        success_print("No circular dependencies detected")
        print()

        # If only checking cycles, we're done
        if args.check_cycles:
            return 0

        # Show dependency tree if requested
        if args.tree:
            if args.tree not in graph.modules:
                error_print(f"Module not found: {args.tree}")
                return 1

            color_print(f"Dependency tree for '{args.tree}':", Colors.BOLD)
            print_dependency_tree(graph, args.tree)
            print()

        # Generate installation order
        install_order = graph.topological_sort()
        if install_order is None:
            error_print("Cannot determine installation order")
            return 1

        # Show installation order
        color_print("Installation order:", Colors.BOLD)
        for i, module in enumerate(install_order, 1):
            deps = graph.get_dependencies(module)
            if deps:
                deps_str = f" (depends on: {', '.join(deps)})"
            else:
                deps_str = ""

            color_print(f"  {i:2d}. {module}{deps_str}", Colors.CYAN)

        print()

        # Show by dependency level if requested
        if args.by_level:
            color_print("Modules by dependency level:", Colors.BOLD)
            levels: Dict[int, List[str]] = defaultdict(list)
            level_cache: Dict[str, int] = {}

            for module in graph.get_all_modules():
                level = graph.get_module_level(module, level_cache)
                levels[level].append(module)

            for level in sorted(levels.keys()):
                color_print(f"\n  Level {level}:", Colors.MAGENTA)
                for module in sorted(levels[level]):
                    print(f"    - {module}")

            print()

        # Show verbose information if requested
        if args.verbose:
            color_print("Detailed dependency information:", Colors.BOLD)
            for module in sorted(graph.get_all_modules()):
                deps = graph.get_dependencies(module)
                dependents = graph.get_dependents(module)

                color_print(f"\n  {module}:", Colors.CYAN)

                if deps:
                    print(f"    Dependencies: {', '.join(deps)}")
                else:
                    print(f"    Dependencies: none")

                if dependents:
                    print(f"    Required by: {', '.join(dependents)}")
                else:
                    print(f"    Required by: none")

            print()

        # Write to file if requested
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                for module in install_order:
                    f.write(f"{module}\n")
            success_print(f"Installation order written to: {args.output}")

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
