# Observability Stack YAML Tools

Production-quality Python tools for YAML validation and management in the observability stack.

## Requirements

- Python 3.8+
- PyYAML: `pip install PyYAML`
- jsonschema: `pip install jsonschema` (for validate_schema.py)
- requests: `pip install requests` (for validate-exporters.py)

Install all dependencies:
```bash
pip install -r requirements.txt
```

## Tools Overview

### 1. validate_schema.py - YAML Schema Validator

Validates YAML configuration files against JSON schemas.

**Features:**
- JSON schemas for module.yaml, global.yaml, and host config files
- Detailed validation error reporting
- Auto-detection of file types
- Recursive directory validation

**Usage:**
```bash
# Validate a single module file
./validate_schema.py modules/_core/node_exporter/module.yaml

# Validate global configuration
./validate_schema.py config/global.yaml

# Validate all modules recursively
./validate_schema.py modules/ --recursive

# Validate with explicit type
./validate_schema.py config/custom.yaml --type global
```

**Exit Codes:**
- 0: All validations passed
- 1: One or more validations failed
- 2: Error in execution

### 2. merge_configs.py - Configuration Merger

Merges host-specific configurations with global defaults and resolves template variables.

**Features:**
- Deep merging of configuration hierarchies
- Template variable resolution (${VAR_NAME})
- Host-specific override support
- Module configuration integration

**Usage:**
```bash
# Merge config for a specific host
./merge_configs.py --global config/global.yaml --host webserver-01

# Include host-specific overrides
./merge_configs.py --global config/global.yaml --host webserver-01 \
                   --host-config config/hosts/webserver-01.yaml

# Output to file
./merge_configs.py --global config/global.yaml --host webserver-01 \
                   --output merged-config.yaml

# List template variables
./merge_configs.py --global config/global.yaml --host webserver-01 --list-vars
```

**Exit Codes:**
- 0: Success
- 1: Validation or merge error
- 2: Execution error

### 3. resolve_deps.py - Module Dependency Resolver

Analyzes module dependencies, builds dependency graph, and determines installation order.

**Features:**
- Dependency graph visualization
- Circular dependency detection
- Topological sort for installation order
- Dependency level grouping

**Usage:**
```bash
# Analyze dependencies
./resolve_deps.py modules/

# Show dependency tree for specific module
./resolve_deps.py modules/ --tree node_exporter

# Output installation order to file
./resolve_deps.py modules/ --output install-order.txt

# Show detailed dependency information
./resolve_deps.py modules/ --verbose

# Check for circular dependencies only
./resolve_deps.py modules/ --check-cycles

# Show modules grouped by dependency level
./resolve_deps.py modules/ --by-level
```

**Exit Codes:**
- 0: Success (all dependencies satisfied, no cycles)
- 1: Dependency errors or circular dependencies detected
- 2: Execution error

### 4. check_ports.py - Port Conflict Detector

Scans for port assignments and detects conflicts.

**Features:**
- Port conflict detection across modules and global config
- System port availability checking
- Port range validation (privileged, dynamic)
- Detailed port usage report

**Usage:**
```bash
# Check ports in modules
./check_ports.py --modules modules/

# Check global.yaml ports
./check_ports.py --global config/global.yaml

# Check both modules and global
./check_ports.py --modules modules/ --global config/global.yaml

# Check system port availability
./check_ports.py --modules modules/ --check-system

# List only conflicts
./check_ports.py --modules modules/ --conflicts-only

# Export port list to file
./check_ports.py --modules modules/ --export ports.txt
```

**Exit Codes:**
- 0: No conflicts found
- 1: Port conflicts detected
- 2: Execution error

### 5. scan_secrets.py - Secret Scanner

Scans YAML files for potential secrets and security issues.

**Features:**
- Pattern-based secret detection (password, key, token, secret)
- Placeholder/default value detection
- Weak password detection
- Security recommendations

**Usage:**
```bash
# Scan a single file
./scan_secrets.py config/global.yaml

# Scan entire directory recursively
./scan_secrets.py config/ --recursive

# Show all findings including info level
./scan_secrets.py config/ --show-info

# Export findings to JSON
./scan_secrets.py config/ --export findings.json

# Fail on any findings (for CI/CD)
./scan_secrets.py config/ --strict
```

**Exit Codes:**
- 0: No issues found (or only info-level)
- 1: Security issues found
- 2: Execution error

### 6. config_diff.py - Configuration Diff Tool

Compares two YAML configurations and generates migration plans.

**Features:**
- Deep comparison of configuration structures
- Sensitive value masking
- Detailed unified diff output
- Migration plan generation

**Usage:**
```bash
# Compare two configuration files
./config_diff.py old-config.yaml new-config.yaml

# Show detailed differences
./config_diff.py old-config.yaml new-config.yaml --detailed

# Generate migration plan
./config_diff.py old-config.yaml new-config.yaml --migration-plan

# Don't mask sensitive values
./config_diff.py old-config.yaml new-config.yaml --no-mask

# Export diff to file
./config_diff.py old-config.yaml new-config.yaml --export diff-report.txt
```

**Exit Codes:**
- 0: Files are identical
- 1: Files have differences
- 2: Execution error

### 7. format_yaml.py - YAML Pretty-Printer

Normalizes YAML formatting and validates syntax.

**Features:**
- Consistent indentation and formatting
- Optional alphabetical key sorting
- Syntax validation
- Common issue fixes (trailing whitespace, multiple blank lines)

**Usage:**
```bash
# Format a file and print to stdout
./format_yaml.py config.yaml

# Format file in-place
./format_yaml.py config.yaml --in-place

# Format with sorted keys
./format_yaml.py config.yaml --sort-keys --in-place

# Format to different file
./format_yaml.py input.yaml --output formatted.yaml

# Format all YAML files in directory
./format_yaml.py config/ --recursive --in-place

# Check if files need formatting (for CI)
./format_yaml.py config/ --check

# Custom indentation and line width
./format_yaml.py config.yaml --indent 4 --width 120
```

**Exit Codes:**
- 0: Success (or all files already formatted in --check mode)
- 1: Formatting errors or files need formatting
- 2: Execution error

### 8. lint_module.py - Module Linter

Validates module.yaml files for completeness and correctness.

**Features:**
- Required field checking
- Version format validation
- Referenced file verification
- Documentation completeness checking
- Port number validation

**Usage:**
```bash
# Lint a single module
./lint_module.py modules/_core/node_exporter/module.yaml

# Lint all modules in directory
./lint_module.py modules/ --recursive

# Show info-level issues
./lint_module.py modules/ --show-info

# Strict mode (fail on warnings)
./lint_module.py modules/ --strict
```

**Exit Codes:**
- 0: No issues found
- 1: Issues found
- 2: Execution error

### 9. validate-exporters.py - Exporter Metrics Validator

Validates Prometheus exporter metrics format, health, and integration with Prometheus.

**Features:**
- Prometheus text format parsing and validation
- Metric naming convention enforcement
- High cardinality detection (performance issues)
- Metric staleness detection
- Prometheus scraping verification
- JSON output for automation
- CI/CD integration support

**Usage:**
```bash
# Validate single exporter
./validate-exporters.py --endpoint http://localhost:9100/metrics

# Scan host for exporters
./validate-exporters.py --scan-host localhost

# Validate with Prometheus integration
./validate-exporters.py --endpoint http://localhost:9100/metrics \
                        --prometheus http://prometheus:9090 \
                        --job node_exporter

# CI/CD integration with JSON output
./validate-exporters.py --endpoint http://localhost:9100/metrics \
                        --json --exit-on-warning

# Validate from endpoints file
./validate-exporters.py --endpoints-file endpoints.txt

# Custom thresholds
./validate-exporters.py --endpoint http://localhost:9100/metrics \
                        --max-cardinality 500 \
                        --staleness-threshold 60
```

**Validation Checks:**
1. HTTP endpoint health (200 OK, response time)
2. Metrics format compliance (Prometheus text format)
3. Naming conventions (metric/label names)
4. Label cardinality (detect performance issues)
5. Metric staleness (detect stuck exporters)
6. Type consistency (counter, gauge, histogram, summary)
7. Prometheus target status (optional)

**Exit Codes:**
- 0: All checks passed
- 1: Warnings detected
- 2: Critical errors detected

**Documentation:**
- Quick Start: [QUICK_START_VALIDATION.md](QUICK_START_VALIDATION.md)
- Full Documentation: [EXPORTER_VALIDATION.md](EXPORTER_VALIDATION.md)
- Examples: [examples/](examples/)

## Common Workflows

### Pre-commit Validation
```bash
# Validate all YAML files
./validate_schema.py . --recursive

# Check for secrets
./scan_secrets.py . --recursive --strict

# Format all YAML files
./format_yaml.py . --recursive --check

# Lint all modules
./lint_module.py modules/ --recursive

# Validate exporters
./validate-exporters.py --scan-host localhost
```

### CI/CD Integration
```bash
#!/bin/bash
set -e

# Run all validation tools
./scripts/tools/validate_schema.py modules/ --recursive
./scripts/tools/lint_module.py modules/ --recursive --strict
./scripts/tools/check_ports.py --modules modules/ --global config/global.yaml
./scripts/tools/scan_secrets.py config/ --recursive --strict
./scripts/tools/resolve_deps.py modules/ --check-cycles

# Validate exporter metrics
./scripts/tools/validate-exporters.py --scan-host localhost \
    --prometheus http://localhost:9090 \
    --exit-on-warning

echo "All validations passed!"
```

### Configuration Migration
```bash
# Compare old and new configs
./config_diff.py old-global.yaml new-global.yaml --migration-plan

# Validate new config
./validate_schema.py new-global.yaml

# Check for new secrets
./scan_secrets.py new-global.yaml
```

### Module Development
```bash
# Lint module during development
./lint_module.py modules/my_new_module/module.yaml

# Validate schema
./validate_schema.py modules/my_new_module/module.yaml --type module

# Check port conflicts
./check_ports.py --modules modules/

# Check dependencies
./resolve_deps.py modules/ --tree my_new_module
```

## Output Features

All tools support:
- Colored output for better readability (can be disabled with --no-color)
- Detailed error messages with suggested fixes
- Proper exit codes for CI/CD integration
- Help text with examples (use --help)

## Error Handling

All tools implement:
- Comprehensive error handling
- Type hints for better code quality
- Input validation
- Graceful failure with meaningful error messages

## Python Version Compatibility

All tools are compatible with Python 3.8+ and use only standard library features plus:
- PyYAML for YAML parsing
- jsonschema for schema validation (validate_schema.py only)

## Development

These tools follow Python best practices:
- Type hints throughout
- Docstrings for all functions and classes
- PEP 8 compliant code
- Modular design
- Comprehensive error handling
