# E2E API Tests

End-to-end tests for the Kuduso API and AppServer integration.

## Prerequisites

1. AppServer running on port 8080
2. API running on port 8081

## Running Tests

```bash
# Install dependencies
pip install -r requirements.txt

# Run all tests
pytest -v

# Run specific test
pytest test_mock_roundtrip.py::test_happy_path_valid_input -v

# Run with coverage
pytest --cov=. --cov-report=html
```

## Test Coverage

- ✅ Happy path with valid input
- ✅ Invalid input validation (missing required, bad CRS)
- ✅ Direct AppServer calls
- ✅ Correlation ID propagation
- ✅ Health check endpoints
- ✅ Deterministic results (same seed = same output)

## Environment Variables

- `API_BASE_URL` - API endpoint (default: http://localhost:8080)
- `APPSERVER_URL` - AppServer endpoint (default: http://localhost:8081)

## Test Data

Tests use example payloads from `contracts/sitefit/1.0.0/examples/`:
- `valid/minimal.json`
- `valid/typical.json`
- `invalid/missing-required.json`
- `invalid/bad-crs.json`
