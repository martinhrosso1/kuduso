# SiteFit Frontend (Next.js)

Web UI for the SiteFit house placement app.

## Features

- **Simple form**: Minimal inputs (CRS, seed)
- **Job submission**: Calls API `/jobs/run`
- **Status polling**: Automatically polls for results
- **Result display**: Shows placement transforms and KPIs

## Stage 1 Behavior

- Synchronous job execution (results appear immediately)
- In-memory state (no persistence)
- Basic UI with inline styles

## Development

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

The app will be available at http://localhost:3000

## Environment Variables

Create `.env.local` from `.env.example`:

```bash
cp .env.example .env.local
```

**Variables:**
- `NEXT_PUBLIC_API_BASE_URL` - API endpoint (default: http://localhost:8081)

## Usage

1. Start the AppServer (port 8080)
2. Start the API (port 8081)
3. Start the Frontend (port 3000)
4. Open http://localhost:3000
5. Click "Run Placement" to submit a job
6. View the results

## Future Enhancements (Stage 7+)

- Interactive map/canvas for drawing parcels and houses
- Visual placement preview (2D/3D)
- Multiple result comparison
- Client-side input validation from schema
- Real-time sliders (preview mode)
