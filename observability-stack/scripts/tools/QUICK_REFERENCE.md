# YAML Tools - Quick Reference Card

## Installation

```bash
cd scripts/tools/
pip install -r requirements.txt
```

## Common Commands

### Validate Everything
```bash
./validate-all.sh
```

### Quick Checks

| Task | Command |
|------|---------|
| Validate module | `./lint_module.py modules/_core/node_exporter/module.yaml` |
| Validate global config | `./validate_schema.py config/global.yaml` |
| Check port conflicts | `./check_ports.py --modules modules/ --global config/global.yaml` |
| Scan for secrets | `./scan_secrets.py config/ -r` |
| Check dependencies | `./resolve_deps.py modules/` |
| Format YAML | `./format_yaml.py config.yaml --in-place` |

### Development Workflow

```bash
# 1. Create/edit module
vim modules/my_module/module.yaml

# 2. Lint the module
./lint_module.py modules/my_module/module.yaml

# 3. Validate schema
./validate_schema.py modules/my_module/module.yaml

# 4. Check ports
./check_ports.py --modules modules/

# 5. Check dependencies
./resolve_deps.py modules/ --tree my_module

# 6. Format YAML
./format_yaml.py modules/my_module/module.yaml --in-place
```

### CI/CD Pipeline

```bash
#!/bin/bash
set -e

# Schema validation
./validate_schema.py modules/ --recursive
./validate_schema.py config/global.yaml

# Module linting
./lint_module.py modules/ --recursive --strict

# Port conflicts
./check_ports.py --modules modules/ --global config/global.yaml

# Secret scanning
./scan_secrets.py config/ --recursive --strict

# Dependency resolution
./resolve_deps.py modules/ --check-cycles

# Format checking
./format_yaml.py . --recursive --check

echo "All checks passed!"
```

## Tool Quick Help

### validate_schema.py
Validates YAML against JSON schemas
- Auto-detects file type (module/global/host)
- Detailed validation errors
- Recursive directory scanning

### merge_configs.py
Merges host configs with global defaults
- Resolves ${VARIABLES}
- Deep merge with overrides
- Outputs merged configuration

### resolve_deps.py
Analyzes module dependencies
- Builds dependency graph
- Detects circular dependencies
- Outputs installation order

### check_ports.py
Detects port conflicts
- Scans modules and global config
- Checks system availability
- Reports conflicts and usage

### scan_secrets.py
Scans for hardcoded secrets
- Detects passwords, keys, tokens
- Finds placeholders
- Security recommendations

### config_diff.py
Compares two configurations
- Shows added/removed/changed keys
- Masks sensitive values
- Generates migration plan

### format_yaml.py
Formats and normalizes YAML
- Consistent indentation
- Fixes common issues
- Optional key sorting

### lint_module.py
Validates module completeness
- Checks required fields
- Validates file references
- Documentation checks

## Common Options

All tools support:
- `--help` - Show detailed help
- `--no-color` - Disable colored output

Most tools support:
- `-r, --recursive` - Process directories recursively
- `-o, --output` - Write output to file

## Exit Codes

- `0` - Success
- `1` - Validation/check failed
- `2` - Execution error

## Troubleshooting

### Missing Dependencies
```bash
# Install all dependencies
pip install -r requirements.txt

# Or install individually
pip install PyYAML jsonschema
```

### Permission Denied
```bash
# Make tools executable
chmod +x scripts/tools/*.py
```

### Import Errors
```bash
# Ensure Python 3.8+
python3 --version

# Check YAML library
python3 -c "import yaml; print(yaml.__version__)"
```

## Tips

1. Use `--help` on any tool for detailed usage
2. Run `validate-all.sh` before committing changes
3. Use `--no-color` when redirecting output to files
4. Most tools can process single files or directories
5. Combine tools in scripts for custom workflows
6. Use `--strict` mode in CI/CD for stricter validation
