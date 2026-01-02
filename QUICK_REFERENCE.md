# CHOM API Test Suite - Quick Reference

## Test Suite Stats

- **Total Test Files:** 11 Python files
- **Total Test Functions:** 137+ test cases
- **Test Coverage:** All major API endpoints
- **Load Testing:** Locust-based concurrent user simulation

## File Structure

```
tests/api/
├── conftest.py              # Core fixtures & config
├── utils.py                 # Helper functions
├── test_auth.py             # 35+ auth tests
├── test_sites.py            # 40+ site tests
├── test_backups.py          # 35+ backup tests
├── test_team.py             # 30+ team tests
├── test_health.py           # 10+ health tests
├── test_schema_validation.py # 15+ schema tests
└── load/locustfile.py       # Load testing
```

## Common Commands

### Run All Tests
```bash
./run_tests.sh
```

### Run Specific Category
```bash
./run_tests.sh auth
./run_tests.sh sites
./run_tests.sh backups
./run_tests.sh team
```

### Run with Options
```bash
./run_tests.sh --verbose      # Detailed output
./run_tests.sh --coverage     # Generate coverage report
./run_tests.sh --parallel     # Parallel execution
```

### Run Specific Tests
```bash
# Run one file
pytest tests/api/test_auth.py -v

# Run one class
pytest tests/api/test_auth.py::TestLogin -v

# Run one test
pytest tests/api/test_auth.py::TestLogin::test_login_success -v

# Run by pattern
pytest tests/api/ -k "login" -v

# Run by marker
pytest tests/api/ -m "performance" -v
```

### Load Testing
```bash
# Interactive web UI
./run_load_test.sh

# Headless (automated)
./run_load_test.sh --headless

# Custom config
./run_load_test.sh --headless --users 50 --duration 300
```

## Test Markers

Use `-m` flag to filter tests:

```bash
pytest tests/api/ -m "auth"         # Authentication tests
pytest tests/api/ -m "sites"        # Site management tests
pytest tests/api/ -m "performance"  # Performance tests
pytest tests/api/ -m "security"     # Security tests
pytest tests/api/ -m "critical"     # Critical path tests
pytest tests/api/ -m "not slow"     # Skip slow tests
```

## Environment Setup

### Quick Setup
```bash
# 1. Install dependencies
pip install -r requirements-test.txt

# 2. Configure
cp .env.testing .env.test

# 3. Run tests
./run_tests.sh
```

### Docker Setup
```bash
# Start test environment
docker-compose -f docker-compose.test.yml up -d

# Run tests
docker-compose -f docker-compose.test.yml exec test-runner ./run_tests.sh

# Stop environment
docker-compose -f docker-compose.test.yml down
```

## Environment Variables

Edit `.env.test`:

```bash
# Essential
API_BASE_URL=http://localhost:8000/api/v1
TEST_USER_PASSWORD=Test123!@#Password

# Optional
TEST_PARALLEL_WORKERS=4
CLEANUP_AFTER_TESTS=true
PERF_THRESHOLD_P95=500
```

## Useful Options

### Debugging
```bash
pytest tests/api/ -v          # Verbose
pytest tests/api/ -vv         # Very verbose
pytest tests/api/ -s          # Show print statements
pytest tests/api/ --pdb       # Drop to debugger on failure
pytest tests/api/ -l          # Show local variables
```

### Running Subsets
```bash
pytest tests/api/ -x          # Stop on first failure
pytest tests/api/ --lf        # Run last failed
pytest tests/api/ --ff        # Run failed first
pytest tests/api/ -k "not slow" # Skip slow tests
```

### Performance
```bash
pytest tests/api/ -n auto     # Auto parallel workers
pytest tests/api/ -n 4        # 4 parallel workers
pytest tests/api/ --durations=10  # Show 10 slowest
```

## Reports

### View HTML Report
```bash
open reports/test_report.html      # macOS
xdg-open reports/test_report.html  # Linux
start reports/test_report.html     # Windows
```

### View Coverage Report
```bash
open htmlcov/index.html
```

### View Load Test Report
```bash
open reports/load/load_test_report.html
```

## API Endpoints Tested

### Authentication (/auth)
- POST /register
- POST /login
- POST /logout
- GET /me
- POST /refresh
- POST /2fa/setup
- POST /2fa/verify

### Sites (/sites)
- GET / (list)
- POST / (create)
- GET /{id}
- PATCH /{id}
- DELETE /{id}
- POST /{id}/enable
- POST /{id}/disable
- POST /{id}/ssl
- GET /{id}/metrics

### Backups (/backups)
- GET / (list)
- POST / (create)
- GET /{id}
- DELETE /{id}
- GET /{id}/download
- POST /{id}/restore
- GET /sites/{id}/backups

### Team (/team)
- GET /members
- GET /members/{id}
- PATCH /members/{id}
- DELETE /members/{id}
- POST /invitations
- GET /invitations
- DELETE /invitations/{id}
- POST /transfer-ownership

### Organization (/organization)
- GET /
- PATCH /

### Health (/health)
- GET /
- GET /detailed
- GET /security

## Performance Targets

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Avg Response | < 200ms | > 300ms | > 500ms |
| p95 Response | < 500ms | > 800ms | > 1000ms |
| Failure Rate | < 1% | > 3% | > 5% |

## Common Issues

### Cannot connect to API
```bash
curl http://localhost:8000/api/v1/health
cat .env.test | grep API_BASE_URL
```

### Import errors
```bash
source venv/bin/activate
pip install -r requirements-test.txt
```

### Authentication failures
```bash
cd chom && php artisan config:clear
```

### Database errors
```bash
cd chom && php artisan migrate:fresh --force
```

## CI/CD

### GitHub Actions
Place in `.github/workflows/api-tests.yml`

### GitLab CI
Place in `.gitlab-ci.yml`

See TESTING_GUIDE.md for full CI/CD configuration.

## Documentation

- **README.md** - Detailed documentation
- **TESTING_GUIDE.md** - Comprehensive guide
- **TEST_SUITE_SUMMARY.md** - Complete overview
- **QUICK_REFERENCE.md** - This file

## Getting Help

1. Check test output: `reports/test_report.html`
2. Read documentation: `tests/api/README.md`
3. View logs: `chom/storage/logs/laravel.log`
4. Debug mode: `pytest --pdb`

## Before Committing

```bash
# Run full suite
./run_tests.sh

# Run with coverage
./run_tests.sh --coverage

# Verify 80%+ coverage
pytest tests/api/ --cov-fail-under=80
```

## Before Deployment

```bash
# Critical tests
./run_tests.sh --critical

# Load test
./run_load_test.sh --headless --users 50 --duration 300

# Full validation
./run_tests.sh --parallel --coverage && echo "✓ Ready"
```

## Test Data

### Test Users
- Email: `test_*@chom.local` (auto-generated)
- Password: `Test123!@#Password`
- Org: `Test Organization`

### Test Sites
- Domain: `test-*.example.com` (auto-generated)
- Types: wordpress, html, laravel
- PHP: 8.2, 8.4

### Cleanup
- Automatic cleanup after each test (configurable)
- Set `CLEANUP_AFTER_TESTS=false` to disable

## Keyboard Shortcuts (pytest)

- `Ctrl+C` - Stop tests
- `--pdb` then `c` - Continue
- `--pdb` then `q` - Quit debugger
- `--pdb` then `l` - List code
- `--pdb` then `p variable` - Print variable

---

**Quick Start:** `./run_tests.sh`
**Documentation:** `tests/api/README.md`
**Support:** GitHub Issues
