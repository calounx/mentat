# Available Modules Directory

This directory is reserved for community-contributed and third-party observability modules.

## Purpose

The `_available/` directory stores modules that are:
- Community-contributed exporters
- Third-party integrations
- Experimental modules
- Platform-specific exporters

## Structure

Place modules here following the standard module structure:

```
_available/
└── your-module/
    ├── module.yaml          # Module manifest
    ├── dashboards/          # Grafana dashboards
    ├── alerts/              # Alert rules
    ├── README.md            # Module documentation
    └── ...
```

## Installing Available Modules

```bash
# List available modules
./scripts/module-manager.sh list --available

# Install an available module
./scripts/module-manager.sh install your-module --from-available
```

## Contributing Modules

See [../../CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines on contributing new modules.

### Module Requirements

1. **module.yaml**: Valid module manifest
2. **README.md**: Documentation and usage instructions
3. **Tests**: Module-specific tests
4. **Dashboards**: At least one Grafana dashboard
5. **Alerts**: Recommended alert rules

## Current Status

**Available Modules**: 0 (This directory is currently empty)

Community contributions welcome!

## See Also

- [Core Modules](../_core/README.md) - Production-ready modules
- [Custom Modules](../_custom/README.md) - User-created modules
- [Module Development Guide](../../docs/MODULE_DEVELOPMENT.md)
