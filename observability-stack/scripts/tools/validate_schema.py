#!/usr/bin/env python3
"""
YAML Schema Validator for Observability Stack

Validates YAML configuration files against JSON schemas.
Supports module.yaml, global.yaml, and host config files.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install PyYAML", file=sys.stderr)
    sys.exit(1)

try:
    from jsonschema import Draft7Validator, ValidationError, validators
except ImportError:
    print("Error: jsonschema is required. Install with: pip install jsonschema", file=sys.stderr)
    sys.exit(1)


# ANSI color codes for output
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
    """Print colored message to stdout."""
    print(f"{color}{message}{Colors.RESET}")


def error_print(message: str) -> None:
    """Print error message to stderr."""
    print(f"{Colors.RED}{Colors.BOLD}ERROR:{Colors.RESET} {Colors.RED}{message}{Colors.RESET}", file=sys.stderr)


def warning_print(message: str) -> None:
    """Print warning message to stdout."""
    print(f"{Colors.YELLOW}{Colors.BOLD}WARNING:{Colors.RESET} {Colors.YELLOW}{message}{Colors.RESET}")


def success_print(message: str) -> None:
    """Print success message to stdout."""
    print(f"{Colors.GREEN}{Colors.BOLD}SUCCESS:{Colors.RESET} {Colors.GREEN}{message}{Colors.RESET}")


def info_print(message: str) -> None:
    """Print info message to stdout."""
    print(f"{Colors.BLUE}{Colors.BOLD}INFO:{Colors.RESET} {message}")


# JSON Schema for module.yaml
MODULE_SCHEMA: Dict[str, Any] = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["module", "detection", "installation", "exporter", "prometheus"],
    "properties": {
        "module": {
            "type": "object",
            "required": ["name", "display_name", "version", "description", "category"],
            "properties": {
                "name": {"type": "string", "pattern": "^[a-z0-9_]+$"},
                "display_name": {"type": "string", "minLength": 1},
                "version": {"type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$"},
                "description": {"type": "string", "minLength": 1},
                "maintainer": {"type": "string"},
                "category": {"type": "string", "enum": ["system", "database", "webserver", "security", "application", "network"]},
                "capabilities": {
                    "type": "object",
                    "properties": {
                        "metrics": {"type": "boolean"},
                        "logs": {"type": "boolean"},
                        "traces": {"type": "boolean"}
                    }
                }
            }
        },
        "detection": {
            "type": "object",
            "properties": {
                "commands": {"type": "array", "items": {"type": "string"}},
                "systemd_services": {"type": "array", "items": {"type": "string"}},
                "files": {"type": "array", "items": {"type": "string"}},
                "confidence": {"type": "integer", "minimum": 0, "maximum": 100}
            }
        },
        "installation": {
            "type": "object",
            "required": ["binary", "system"],
            "properties": {
                "binary": {
                    "type": "object",
                    "required": ["url", "archive_type", "binary_name", "install_path"],
                    "properties": {
                        "url": {"type": "string", "minLength": 1},
                        "archive_type": {"type": "string", "enum": ["tar.gz", "zip", "binary"]},
                        "binary_name": {"type": "string", "minLength": 1},
                        "archive_path": {"type": "string"},
                        "install_path": {"type": "string", "pattern": "^/"},
                        "checksum_url": {"type": "string"}
                    }
                },
                "system": {
                    "type": "object",
                    "required": ["user", "group"],
                    "properties": {
                        "user": {"type": "string", "pattern": "^[a-z_][a-z0-9_-]*$"},
                        "group": {"type": "string", "pattern": "^[a-z_][a-z0-9_-]*$"},
                        "create_home": {"type": "boolean"},
                        "shell": {"type": "string"},
                        "additional_groups": {"type": "array", "items": {"type": "string"}}
                    }
                },
                "dependencies": {
                    "type": "object",
                    "properties": {
                        "modules": {"type": "array", "items": {"type": "string"}},
                        "packages": {"type": "array", "items": {"type": "string"}},
                        "optional_packages": {"type": "array", "items": {"type": "string"}}
                    }
                },
                "config_dirs": {"type": "array", "items": {"type": "string"}}
            }
        },
        "exporter": {
            "type": "object",
            "required": ["port"],
            "properties": {
                "port": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "flags": {"type": "array", "items": {"type": "string"}},
                "environment": {"type": "object"},
                "health_check": {
                    "type": "object",
                    "properties": {
                        "endpoint": {"type": "string", "pattern": "^https?://"},
                        "expected_metric": {"type": "string"},
                        "timeout": {"type": "integer", "minimum": 1}
                    }
                }
            }
        },
        "host_config": {
            "type": "object",
            "properties": {
                "required": {"type": "array", "items": {"type": "string"}},
                "optional": {"type": "object"}
            }
        },
        "prometheus": {
            "type": "object",
            "required": ["job_name"],
            "properties": {
                "job_name": {"type": "string", "pattern": "^[a-z0-9_]+$"},
                "scrape_interval": {"type": "string", "pattern": "^[0-9]+[smh]$"},
                "scrape_timeout": {"type": "string", "pattern": "^[0-9]+[smh]$"},
                "labels": {"type": "object"},
                "metric_relabel_configs": {"type": "array"}
            }
        },
        "dashboard": {
            "type": "object",
            "properties": {
                "file": {"type": "string", "pattern": "\\.json$"},
                "title": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "folder": {"type": "string"},
                "variables": {"type": "array", "items": {"type": "string"}}
            }
        },
        "alerts": {
            "type": "object",
            "properties": {
                "file": {"type": "string", "pattern": "\\.yml$"},
                "groups": {"type": "array", "items": {"type": "string"}},
                "thresholds": {"type": "object"}
            }
        },
        "documentation": {
            "type": "object",
            "properties": {
                "setup_instructions": {"type": "string"},
                "troubleshooting": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "issue": {"type": "string"},
                            "solution": {"type": "string"}
                        }
                    }
                }
            }
        },
        "hooks": {
            "type": "object",
            "properties": {
                "pre_install": {"type": "string"},
                "post_install": {"type": "string"},
                "pre_upgrade": {"type": "string"},
                "post_upgrade": {"type": "string"},
                "pre_uninstall": {"type": "string"},
                "post_uninstall": {"type": "string"}
            }
        }
    }
}


# JSON Schema for global.yaml
GLOBAL_SCHEMA: Dict[str, Any] = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["network", "monitored_hosts", "retention", "grafana", "security", "ports"],
    "properties": {
        "network": {
            "type": "object",
            "required": ["observability_vps_ip", "grafana_domain", "letsencrypt_email"],
            "properties": {
                "observability_vps_ip": {
                    "type": "string",
                    "pattern": "^([0-9]{1,3}\\.){3}[0-9]{1,3}$|^YOUR_OBSERVABILITY_VPS_IP$"
                },
                "grafana_domain": {"type": "string", "pattern": "^[a-z0-9.-]+\\.[a-z]{2,}$"},
                "letsencrypt_email": {"type": "string", "format": "email"}
            }
        },
        "monitored_hosts": {
            "type": "array",
            "minItems": 1,
            "items": {
                "type": "object",
                "required": ["name", "ip", "exporters"],
                "properties": {
                    "name": {"type": "string", "pattern": "^[a-z0-9-]+$"},
                    "ip": {
                        "type": "string",
                        "pattern": "^([0-9]{1,3}\\.){3}[0-9]{1,3}$|^MONITORED_HOST_[0-9]+_IP$"
                    },
                    "description": {"type": "string"},
                    "exporters": {
                        "type": "array",
                        "minItems": 1,
                        "items": {"type": "string"}
                    },
                    "config": {"type": "object"}
                }
            }
        },
        "smtp": {
            "type": "object",
            "properties": {
                "enabled": {"type": "boolean"},
                "host": {"type": "string"},
                "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                "username": {"type": "string"},
                "password": {"type": "string"},
                "from_address": {"type": "string", "format": "email"},
                "to_addresses": {
                    "type": "array",
                    "items": {"type": "string", "format": "email"}
                },
                "starttls": {"type": "boolean"}
            }
        },
        "retention": {
            "type": "object",
            "required": ["metrics_days", "logs_days"],
            "properties": {
                "metrics_days": {"type": "integer", "minimum": 1},
                "logs_days": {"type": "integer", "minimum": 1}
            }
        },
        "grafana": {
            "type": "object",
            "required": ["admin_password"],
            "properties": {
                "admin_password": {"type": "string", "minLength": 8},
                "anonymous_access": {"type": "boolean"}
            }
        },
        "security": {
            "type": "object",
            "required": ["prometheus_basic_auth_user", "prometheus_basic_auth_password",
                        "loki_basic_auth_user", "loki_basic_auth_password"],
            "properties": {
                "prometheus_basic_auth_user": {"type": "string", "minLength": 1},
                "prometheus_basic_auth_password": {"type": "string", "minLength": 8},
                "loki_basic_auth_user": {"type": "string", "minLength": 1},
                "loki_basic_auth_password": {"type": "string", "minLength": 8}
            }
        },
        "ports": {
            "type": "object",
            "required": ["prometheus", "loki", "grafana", "alertmanager", "node_exporter"],
            "properties": {
                "prometheus": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "loki": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "grafana": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "alertmanager": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "node_exporter": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "nginx_exporter": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "mysqld_exporter": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "phpfpm_exporter": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "fail2ban_exporter": {"type": "integer", "minimum": 1024, "maximum": 65535}
            }
        }
    }
}


# JSON Schema for host config files
HOST_CONFIG_SCHEMA: Dict[str, Any] = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["hostname", "modules"],
    "properties": {
        "hostname": {"type": "string", "pattern": "^[a-z0-9.-]+$"},
        "ip": {"type": "string", "pattern": "^([0-9]{1,3}\\.){3}[0-9]{1,3}$"},
        "description": {"type": "string"},
        "modules": {
            "type": "object",
            "patternProperties": {
                "^[a-z0-9_]+$": {
                    "type": "object",
                    "properties": {
                        "enabled": {"type": "boolean"}
                    }
                }
            }
        }
    }
}


def load_yaml_file(file_path: Path) -> Optional[Dict[str, Any]]:
    """
    Load and parse a YAML file.

    Args:
        file_path: Path to YAML file

    Returns:
        Parsed YAML data or None on error
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
            if data is None:
                error_print(f"File is empty: {file_path}")
                return None
            return data
    except yaml.YAMLError as e:
        error_print(f"YAML parsing error in {file_path}: {e}")
        return None
    except FileNotFoundError:
        error_print(f"File not found: {file_path}")
        return None
    except Exception as e:
        error_print(f"Error reading {file_path}: {e}")
        return None


def validate_against_schema(
    data: Dict[str, Any],
    schema: Dict[str, Any],
    file_path: Path
) -> Tuple[bool, List[str]]:
    """
    Validate data against JSON schema.

    Args:
        data: Data to validate
        schema: JSON schema
        file_path: Path to file being validated (for error messages)

    Returns:
        Tuple of (is_valid, list_of_errors)
    """
    validator = Draft7Validator(schema)
    errors: List[str] = []

    for error in sorted(validator.iter_errors(data), key=lambda e: e.path):
        # Build path to error location
        path_parts = [str(p) for p in error.path]
        location = ".".join(path_parts) if path_parts else "root"

        # Format error message
        error_msg = f"  - At '{location}': {error.message}"
        errors.append(error_msg)

    return len(errors) == 0, errors


def detect_file_type(file_path: Path) -> Optional[str]:
    """
    Detect the type of YAML file based on path and content.

    Args:
        file_path: Path to YAML file

    Returns:
        File type: 'module', 'global', 'host', or None
    """
    if file_path.name == "global.yaml":
        return "global"
    elif file_path.name == "module.yaml":
        return "module"
    elif file_path.parent.name == "hosts":
        return "host"

    # Try to detect from content
    data = load_yaml_file(file_path)
    if data:
        if "module" in data and "installation" in data:
            return "module"
        elif "network" in data and "monitored_hosts" in data:
            return "global"
        elif "hostname" in data and "modules" in data:
            return "host"

    return None


def validate_file(file_path: Path, file_type: Optional[str] = None) -> bool:
    """
    Validate a single YAML file.

    Args:
        file_path: Path to YAML file
        file_type: Type of file ('module', 'global', 'host'), auto-detect if None

    Returns:
        True if validation passed, False otherwise
    """
    info_print(f"Validating: {file_path}")

    # Detect file type if not provided
    if file_type is None:
        file_type = detect_file_type(file_path)
        if file_type is None:
            warning_print(f"Cannot determine file type for {file_path}, skipping")
            return True  # Don't fail on unknown files

    # Load YAML
    data = load_yaml_file(file_path)
    if data is None:
        return False

    # Select schema
    schema_map = {
        "module": MODULE_SCHEMA,
        "global": GLOBAL_SCHEMA,
        "host": HOST_CONFIG_SCHEMA
    }

    schema = schema_map.get(file_type)
    if schema is None:
        error_print(f"Unknown file type: {file_type}")
        return False

    # Validate
    is_valid, errors = validate_against_schema(data, schema, file_path)

    if is_valid:
        success_print(f"Valid {file_type} config: {file_path}")
        return True
    else:
        error_print(f"Validation failed for {file_path}:")
        for error in errors:
            print(f"{Colors.RED}{error}{Colors.RESET}", file=sys.stderr)
        return False


def validate_directory(directory: Path, recursive: bool = True) -> Tuple[int, int]:
    """
    Validate all YAML files in a directory.

    Args:
        directory: Directory to scan
        recursive: Whether to scan recursively

    Returns:
        Tuple of (valid_count, invalid_count)
    """
    pattern = "**/*.yaml" if recursive else "*.yaml"
    yaml_files = list(directory.glob(pattern))

    if not yaml_files:
        warning_print(f"No YAML files found in {directory}")
        return 0, 0

    valid_count = 0
    invalid_count = 0

    for file_path in yaml_files:
        if validate_file(file_path):
            valid_count += 1
        else:
            invalid_count += 1
        print()  # Blank line between files

    return valid_count, invalid_count


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate YAML configuration files for observability stack",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Validate a single module file
  %(prog)s modules/_core/node_exporter/module.yaml

  # Validate global configuration
  %(prog)s config/global.yaml

  # Validate all modules recursively
  %(prog)s modules/ --recursive

  # Validate with explicit type
  %(prog)s config/custom.yaml --type global

  # Validate entire observability stack
  %(prog)s /path/to/observability-stack --recursive

Exit codes:
  0 - All validations passed
  1 - One or more validations failed
  2 - Error in execution (missing dependencies, file not found, etc.)
        """
    )

    parser.add_argument(
        "path",
        type=Path,
        help="Path to YAML file or directory to validate"
    )

    parser.add_argument(
        "-t", "--type",
        choices=["module", "global", "host"],
        help="Explicitly specify file type (auto-detect if not provided)"
    )

    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Recursively validate all YAML files in directory"
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

    # Validate path exists
    if not args.path.exists():
        error_print(f"Path does not exist: {args.path}")
        return 2

    # Validate file or directory
    try:
        if args.path.is_file():
            if validate_file(args.path, args.type):
                return 0
            else:
                return 1
        elif args.path.is_dir():
            valid_count, invalid_count = validate_directory(args.path, args.recursive)

            # Print summary
            print("=" * 60)
            color_print(f"Validation Summary:", Colors.BOLD)
            success_print(f"Valid files: {valid_count}")
            if invalid_count > 0:
                error_print(f"Invalid files: {invalid_count}")
            print("=" * 60)

            return 0 if invalid_count == 0 else 1
        else:
            error_print(f"Path is neither a file nor directory: {args.path}")
            return 2
    except KeyboardInterrupt:
        print("\n")
        warning_print("Validation interrupted by user")
        return 2
    except Exception as e:
        error_print(f"Unexpected error: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
