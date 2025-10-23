# AppServer (Node.js)

Internal-only service that validates contracts and routes compute requests.

## Features

- **Contract validation**: Validates inputs/outputs against JSON schemas
- **Mock solver**: Returns deterministic results (Stage 1)
- **Correlation tracking**: Propagates `x-correlation-id` for request tracing
- **Structured logging**: JSON logs for observability

## API

### `POST /gh/:def::ver/solve`

Solve a computational problem using the specified definition and version.

**Headers:**
- `x-correlation-id` (optional): Request correlation ID
- `Content-Type: application/json`

**Request body**: Must match `contracts/{def}/{ver}/inputs.schema.json`

**Response**: Matches `contracts/{def}/{ver}/outputs.schema.json`

**Status codes:**
- `200` - Success
- `400` - Input validation failed
- `404` - Contract definition not found
- `500` - Internal error or output validation failed

### `GET /health`

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "service": "appserver-node",
  "mode": "mock"
}
```

## Development

```bash
# Install dependencies
npm install

# Run in development mode (hot reload)
npm run dev

# Build
npm run build

# Run production
npm start

# Run tests
npm test
```

## Environment Variables

See `.env.example` for configuration options.

## Usage Example

```bash
# Start the server
npm run dev

# Test with a contract example
curl -X POST http://localhost:8080/gh/sitefit:1.0.0/solve \
  -H "Content-Type: application/json" \
  -H "x-correlation-id: test-123" \
  -d @../../contracts/sitefit/1.0.0/examples/valid/minimal.json
```

## Stage 1 vs Future

**Stage 1 (current)**: Mock solver returns deterministic results
**Stage 4+**: Will call real Rhino.Compute when `USE_COMPUTE=true`

The contract validation and API structure remain the same.
