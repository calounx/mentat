# Python YAML Tools - Installation Guide

## Quick Start

```bash
# 1. Navigate to tools directory
cd /home/calounx/repositories/mentat/observability-stack/scripts/tools/

# 2. Install Python dependencies
pip install -r requirements.txt

# 3. Test all tools
./test-tools.sh

# 4. Run comprehensive validation
./validate-all.sh
```

## System Requirements

### Python Version
- Python 3.8 or higher
- Check version: `python3 --version`

### Operating System
- Linux (tested on Ubuntu, Debian, CentOS)
- macOS (should work, not extensively tested)
- Windows (WSL recommended)

## Dependencies

### Required Python Packages

1. **PyYAML** (all tools)
   - YAML parsing and generation
   - Version: 6.0 or higher
   - Install: `pip install PyYAML`

2. **jsonschema** (validate_schema.py only)
   - JSON schema validation
   - Version: 4.0.0 or higher
   - Install: `pip install jsonschema`

### Installation Options

#### Option 1: Using requirements.txt (Recommended)
```bash
pip install -r scripts/tools/requirements.txt
```

#### Option 2: Using system package manager
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install python3-yaml python3-jsonschema

# CentOS/RHEL
sudo yum install python3-pyyaml python3-jsonschema

# macOS (Homebrew)
brew install python3
pip3 install PyYAML jsonschema
```

#### Option 3: Using virtual environment (Recommended for development)
```bash
# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate  # Linux/macOS
# OR
venv\Scripts\activate  # Windows

# Install dependencies
pip install -r scripts/tools/requirements.txt
```

## Verification

### Check Installation
```bash
# Check Python version
python3 --version

# Check PyYAML
python3 -c "import yaml; print(f'PyYAML {yaml.__version__}')"

# Check jsonschema
python3 -c "import jsonschema; print(f'jsonschema {jsonschema.__version__}')"
```

### Test Tools
```bash
# Test all tools at once
./scripts/tools/test-tools.sh

# Test individual tools
python3 scripts/tools/lint_module.py --help
python3 scripts/tools/scan_secrets.py --help
python3 scripts/tools/check_ports.py --help
```

### Run Validation
```bash
# Run comprehensive validation
./scripts/tools/validate-all.sh
```

## Troubleshooting

### Issue: "command not found: pip"
**Solution:**
```bash
# Install pip
sudo apt-get install python3-pip  # Ubuntu/Debian
sudo yum install python3-pip       # CentOS/RHEL
```

### Issue: "ImportError: No module named yaml"
**Solution:**
```bash
pip install PyYAML
# OR
pip3 install PyYAML
# OR
python3 -m pip install PyYAML
```

### Issue: "Permission denied"
**Solution:**
```bash
# Make tools executable
chmod +x scripts/tools/*.py
chmod +x scripts/tools/*.sh

# OR install with --user flag
pip install --user PyYAML jsonschema
```

### Issue: "ModuleNotFoundError: No module named 'jsonschema'"
**Solution:**
```bash
# jsonschema is only required for validate_schema.py
pip install jsonschema

# All other tools work without it
```

### Issue: Tools run but show "import yaml" error
**Solution:**
```bash
# Ensure you're using the right Python
which python3
python3 --version

# Install in correct environment
python3 -m pip install PyYAML jsonschema
```

### Issue: Colors not showing in output
**Cause:** Terminal doesn't support ANSI colors

**Solution:**
```bash
# Use --no-color flag
./tool.py --no-color

# OR set environment variable
export NO_COLOR=1
```

## File Permissions

All Python scripts should be executable:
```bash
# Check permissions
ls -l scripts/tools/*.py

# Make executable if needed
chmod +x scripts/tools/*.py
chmod +x scripts/tools/*.sh
```

## Path Configuration

### Option 1: Add to PATH
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/home/calounx/repositories/mentat/observability-stack/scripts/tools"

# Reload
source ~/.bashrc
```

### Option 2: Create aliases
```bash
# Add to ~/.bashrc or ~/.zshrc
alias validate-yaml='python3 /path/to/validate_schema.py'
alias lint-module='python3 /path/to/lint_module.py'
alias scan-secrets='python3 /path/to/scan_secrets.py'
```

### Option 3: Use full paths
```bash
# Always use full path
/home/calounx/repositories/mentat/observability-stack/scripts/tools/lint_module.py
```

## Integration with IDEs

### VSCode
Add to `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Validate YAML",
      "type": "shell",
      "command": "python3",
      "args": [
        "${workspaceFolder}/scripts/tools/validate_schema.py",
        "${file}"
      ]
    },
    {
      "label": "Lint Module",
      "type": "shell",
      "command": "python3",
      "args": [
        "${workspaceFolder}/scripts/tools/lint_module.py",
        "${file}"
      ]
    }
  ]
}
```

### PyCharm
1. Go to Run → Edit Configurations
2. Add External Tool
3. Program: `python3`
4. Arguments: `/path/to/tool.py $FilePath$`
5. Working directory: `$ProjectFileDir$`

## Updating

### Update Tools
```bash
cd /home/calounx/repositories/mentat/observability-stack
git pull
```

### Update Dependencies
```bash
pip install --upgrade PyYAML jsonschema
```

## Uninstallation

### Remove Python packages
```bash
pip uninstall PyYAML jsonschema
```

### Remove tools
```bash
# Just delete the directory
rm -rf scripts/tools/
```

## Next Steps

After installation:

1. Read [README.md](README.md) for tool overview
2. Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for common commands
3. Review [TOOLS_OVERVIEW.md](TOOLS_OVERVIEW.md) for detailed usage
4. Run `./validate-all.sh` to validate your configuration
5. Set up pre-commit hooks (see README.md)

## Getting Help

For each tool:
```bash
./tool.py --help
```

For comprehensive documentation:
- README.md - Main documentation
- QUICK_REFERENCE.md - Quick command reference
- TOOLS_OVERVIEW.md - Detailed tool descriptions
- This file (INSTALLATION.md) - Installation guide

## Support

If you encounter issues:
1. Check this installation guide
2. Verify Python version: `python3 --version`
3. Check dependencies: `pip list | grep -i yaml`
4. Run test script: `./test-tools.sh`
5. Check tool help: `./tool.py --help`
