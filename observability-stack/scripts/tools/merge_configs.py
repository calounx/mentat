#!/usr/bin/env python3
"""
Configuration Merger for Observability Stack

Merges host-specific configurations with global defaults.
Resolves template variables and handles inheritance/overrides.
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

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


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    """
    Recursively merge two dictionaries.

    Override values take precedence over base values.
    For nested dicts, merge recursively.
    For lists, override replaces base.

    Args:
        base: Base dictionary
        override: Override dictionary

    Returns:
        Merged dictionary
    """
    result = base.copy()

    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            # Recursively merge nested dicts
            result[key] = deep_merge(result[key], value)
        else:
            # Override value (including lists)
            result[key] = value

    return result


def find_template_variables(data: Any) -> Set[str]:
    """
    Find all template variables in data structure.

    Template variables are in format: ${VAR_NAME}

    Args:
        data: Data structure to scan

    Returns:
        Set of variable names (without ${} wrapper)
    """
    variables: Set[str] = set()
    pattern = re.compile(r'\$\{([A-Z_][A-Z0-9_]*)\}')

    def scan(obj: Any) -> None:
        if isinstance(obj, str):
            matches = pattern.findall(obj)
            variables.update(matches)
        elif isinstance(obj, dict):
            for value in obj.values():
                scan(value)
        elif isinstance(obj, list):
            for item in obj:
                scan(item)

    scan(data)
    return variables


def resolve_template_variables(
    data: Any,
    variables: Dict[str, str],
    strict: bool = False
) -> Any:
    """
    Resolve template variables in data structure.

    Replaces ${VAR_NAME} with values from variables dict.

    Args:
        data: Data structure to process
        variables: Variable name -> value mapping
        strict: If True, raise error on unresolved variables

    Returns:
        Data with resolved variables
    """
    pattern = re.compile(r'\$\{([A-Z_][A-Z0-9_]*)\}')

    def resolve(obj: Any) -> Any:
        if isinstance(obj, str):
            def replacer(match: re.Match) -> str:
                var_name = match.group(1)
                if var_name in variables:
                    return variables[var_name]
                elif strict:
                    raise ValueError(f"Unresolved template variable: {var_name}")
                else:
                    warning_print(f"Unresolved variable: {var_name}")
                    return match.group(0)  # Keep original

            return pattern.sub(replacer, obj)
        elif isinstance(obj, dict):
            return {k: resolve(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [resolve(item) for item in obj]
        else:
            return obj

    return resolve(data)


def extract_host_variables(global_config: Dict[str, Any], host_name: str) -> Dict[str, str]:
    """
    Extract variables for a specific host from global config.

    Args:
        global_config: Global configuration
        host_name: Name of host

    Returns:
        Dictionary of variables for template resolution
    """
    variables: Dict[str, str] = {}

    # Add global network variables
    if 'network' in global_config:
        network = global_config['network']
        variables['OBSERVABILITY_VPS_IP'] = network.get('observability_vps_ip', '')
        variables['GRAFANA_DOMAIN'] = network.get('grafana_domain', '')
        variables['LETSENCRYPT_EMAIL'] = network.get('letsencrypt_email', '')

    # Find host-specific config
    if 'monitored_hosts' in global_config:
        for host in global_config['monitored_hosts']:
            if host.get('name') == host_name:
                variables['HOST_NAME'] = host.get('name', '')
                variables['HOST_IP'] = host.get('ip', '')
                variables['HOST_DESCRIPTION'] = host.get('description', '')
                break

    # Add port variables
    if 'ports' in global_config:
        for port_name, port_value in global_config['ports'].items():
            var_name = f"{port_name.upper()}_PORT"
            variables[var_name] = str(port_value)

    # Add version variable if available
    variables['VERSION'] = '${VERSION}'  # Preserve for module-specific resolution

    return variables


def merge_host_config(
    global_config: Dict[str, Any],
    host_config: Optional[Dict[str, Any]],
    module_configs: Dict[str, Dict[str, Any]],
    host_name: str,
    resolve_vars: bool = True
) -> Dict[str, Any]:
    """
    Merge global, host, and module configurations.

    Args:
        global_config: Global configuration
        host_config: Host-specific configuration (optional)
        module_configs: Module name -> module config mapping
        host_name: Name of host
        resolve_vars: Whether to resolve template variables

    Returns:
        Merged configuration for the host
    """
    # Start with global config as base
    merged = global_config.copy()

    # Find host in global config
    host_global = None
    if 'monitored_hosts' in global_config:
        for host in global_config['monitored_hosts']:
            if host.get('name') == host_name:
                host_global = host
                break

    if host_global is None:
        warning_print(f"Host '{host_name}' not found in global config")

    # Merge host-specific overrides
    if host_config:
        merged = deep_merge(merged, host_config)

    # Add module configurations
    merged['modules'] = {}

    if host_global and 'exporters' in host_global:
        for exporter_name in host_global['exporters']:
            if exporter_name in module_configs:
                module_cfg = module_configs[exporter_name].copy()

                # Merge host-specific module config if present
                if host_config and 'modules' in host_config:
                    if exporter_name in host_config['modules']:
                        module_cfg = deep_merge(
                            module_cfg,
                            host_config['modules'][exporter_name]
                        )

                merged['modules'][exporter_name] = module_cfg

    # Resolve template variables
    if resolve_vars:
        variables = extract_host_variables(global_config, host_name)
        merged = resolve_template_variables(merged, variables, strict=False)

    return merged


def load_all_modules(modules_dir: Path) -> Dict[str, Dict[str, Any]]:
    """
    Load all module configurations from modules directory.

    Args:
        modules_dir: Path to modules directory

    Returns:
        Module name -> module config mapping
    """
    modules: Dict[str, Dict[str, Any]] = {}

    # Find all module.yaml files
    for module_file in modules_dir.glob("**/module.yaml"):
        module_data = load_yaml_file(module_file)
        if module_data and 'module' in module_data:
            module_name = module_data['module'].get('name')
            if module_name:
                modules[module_name] = module_data

    return modules


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Merge host configurations with global defaults",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Merge config for a specific host
  %(prog)s --global config/global.yaml --host webserver-01

  # Include host-specific overrides
  %(prog)s --global config/global.yaml --host webserver-01 \\
           --host-config config/hosts/webserver-01.yaml

  # Load modules from custom directory
  %(prog)s --global config/global.yaml --host webserver-01 \\
           --modules-dir /path/to/modules

  # Output to file instead of stdout
  %(prog)s --global config/global.yaml --host webserver-01 \\
           --output merged-config.yaml

  # Show unresolved template variables
  %(prog)s --global config/global.yaml --host webserver-01 --no-resolve

  # List all available template variables
  %(prog)s --global config/global.yaml --host webserver-01 --list-vars

Exit codes:
  0 - Success
  1 - Validation or merge error
  2 - Execution error
        """
    )

    parser.add_argument(
        "-g", "--global",
        dest="global_config",
        type=Path,
        required=True,
        help="Path to global.yaml configuration file"
    )

    parser.add_argument(
        "-H", "--host",
        required=True,
        help="Host name to generate config for"
    )

    parser.add_argument(
        "-c", "--host-config",
        type=Path,
        help="Path to host-specific configuration file (optional)"
    )

    parser.add_argument(
        "-m", "--modules-dir",
        type=Path,
        help="Path to modules directory (default: auto-detect from global config path)"
    )

    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Output file path (default: stdout)"
    )

    parser.add_argument(
        "--no-resolve",
        action="store_true",
        help="Don't resolve template variables"
    )

    parser.add_argument(
        "--list-vars",
        action="store_true",
        help="List all template variables found in config"
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
        # Load global config
        info_print(f"Loading global config: {args.global_config}")
        global_config = load_yaml_file(args.global_config)
        if global_config is None:
            return 1

        # Load host config if provided
        host_config = None
        if args.host_config:
            info_print(f"Loading host config: {args.host_config}")
            host_config = load_yaml_file(args.host_config)
            if host_config is None:
                return 1

        # Determine modules directory
        if args.modules_dir:
            modules_dir = args.modules_dir
        else:
            # Auto-detect: assume modules/ is sibling to config/
            modules_dir = args.global_config.parent.parent / "modules"

        if not modules_dir.exists():
            error_print(f"Modules directory not found: {modules_dir}")
            return 1

        # Load all modules
        info_print(f"Loading modules from: {modules_dir}")
        modules = load_all_modules(modules_dir)
        info_print(f"Loaded {len(modules)} modules")

        # Merge configurations
        info_print(f"Merging configuration for host: {args.host}")
        merged = merge_host_config(
            global_config,
            host_config,
            modules,
            args.host,
            resolve_vars=not args.no_resolve
        )

        # List variables if requested
        if args.list_vars:
            variables = find_template_variables(merged)
            if variables:
                info_print("Template variables found:")
                for var in sorted(variables):
                    print(f"  - {var}")
            else:
                info_print("No template variables found")
            print()

        # Output merged config
        yaml_output = yaml.dump(merged, default_flow_style=False, sort_keys=False)

        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(yaml_output)
            success_print(f"Merged configuration written to: {args.output}")
        else:
            print(yaml_output)

        return 0

    except KeyboardInterrupt:
        print("\n")
        warning_print("Merge interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
