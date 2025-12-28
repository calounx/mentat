# Custom Modules Directory

This directory is for user-created custom observability modules specific to your environment.

## Purpose

The `_custom/` directory is for:
- Internal exporters for proprietary systems
- Organization-specific monitoring modules
- Custom integrations not suitable for public release
- Experimental modules under development

## Structure

Create your custom modules following the standard structure:

```
_custom/
└── my-app-exporter/
    ├── module.yaml          # Module manifest
    ├── dashboards/          # Grafana dashboards
    ├── alerts/              # Alert rules
    ├── README.md            # Module documentation
    ├── install.sh           # Optional installation script
    └── ...
```

## Creating Custom Modules

1. **Create module directory**:
   ```bash
   mkdir -p _custom/my-app-exporter
   ```

2. **Create module.yaml**:
   See [module template](../../docs/templates/module.yaml.template)

3. **Install custom module**:
   ```bash
   ./scripts/module-manager.sh install my-app-exporter --custom
   ```

## Module Template

```yaml
---
module:
  name: my-app-exporter
  version: 1.0.0
  description: "Custom exporter for my application"
  category: application

detection:
  services:
    - my-app
  ports:
    - 8080

installation:
  binary:
    url: "https://internal.company.com/exporters/my-app-exporter.tar.gz"
    install_path: "/usr/local/bin/my-app-exporter"

configuration:
  port: 9999

prometheus:
  scrape_config: |
    - job_name: 'my-app'
      static_configs:
        - targets: ['localhost:9999']

health_check:
  command: "curl -s http://localhost:9999/metrics | grep -q my_app_up"
```

## Custom vs Core Modules

| Aspect | Core Modules | Custom Modules |
|--------|--------------|----------------|
| **Versioning** | Managed by project | Self-managed |
| **Updates** | Automatic via upgrade | Manual updates |
| **Visibility** | Public | Private |
| **Support** | Community | Self-supported |

## Best Practices

1. **Follow naming conventions**: Use descriptive module names
2. **Document thoroughly**: Future you will thank you
3. **Test before deploying**: Use test environments
4. **Version control**: Keep your modules in git
5. **Security**: Don't commit secrets in module.yaml

## Git Ignore

Custom modules are gitignored by default. To version control your modules:

```bash
# Add to .gitignore exception
!modules/_custom/my-app-exporter/
```

## Current Status

**Custom Modules**: 0 (This directory is currently empty)

## See Also

- [Core Modules](../_core/README.md) - Production modules
- [Available Modules](../_available/README.md) - Community modules
- [Module Development Guide](../../docs/MODULE_DEVELOPMENT.md)
