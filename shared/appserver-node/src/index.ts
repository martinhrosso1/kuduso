import express, { Request, Response } from 'express';
import cors from 'cors';
import { randomUUID } from 'crypto';
import { validateInputs, validateOutputs } from './validate.js';
import { mockSolve } from './mockSolver.js';
import { logger } from './logger.js';

const app = express();
const PORT = process.env.PORT || 8080;
const USE_COMPUTE = process.env.USE_COMPUTE === 'true';

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'appserver-node', mode: USE_COMPUTE ? 'compute' : 'mock' });
});

// Readiness check
app.get('/ready', (req: Request, res: Response) => {
  res.json({ status: 'ready', service: 'appserver-node' });
});

// Main solve endpoint
app.post('/gh/:def\\::ver/solve', async (req: Request, res: Response) => {
  const cid = (req.header('x-correlation-id') || randomUUID()) as string;
  res.setHeader('x-correlation-id', cid);

  const { def, ver } = req.params;
  const startTime = Date.now();

  logger.info({ cid, def, ver, event: 'solve.start' });

  try {
    // Validate inputs against contract schema
    const inputs = validateInputs(def, ver, req.body);
    
    logger.debug({ cid, def, ver, event: 'inputs.validated' });

    // Call mock solver (or real compute in future)
    const result = await mockSolve(inputs, def, ver);
    
    logger.debug({ cid, def, ver, event: 'solve.complete', duration_ms: Date.now() - startTime });

    // Validate outputs against contract schema
    validateOutputs(def, ver, result);
    
    logger.info({ 
      cid, 
      def, 
      ver, 
      event: 'solve.success', 
      duration_ms: Date.now() - startTime,
      results_count: result.results?.length || 0
    });

    res.status(200).json(result);
  } catch (error: any) {
    const duration_ms = Date.now() - startTime;
    const code = error.code || 500;
    
    logger.error({ 
      cid, 
      def, 
      ver, 
      event: 'solve.error', 
      error: error.message,
      code,
      duration_ms
    });

    res.status(code).json({
      code,
      message: error.message || 'Internal server error',
      details: error.details || [],
      correlation_id: cid
    });
  }
});

// 404 handler
app.use((req: Request, res: Response) => {
  res.status(404).json({ 
    code: 404, 
    message: 'Endpoint not found',
    path: req.path 
  });
});

// Start server
app.listen(PORT, () => {
  logger.info({ 
    event: 'server.start', 
    port: PORT, 
    mode: USE_COMPUTE ? 'compute' : 'mock',
    contracts_dir: process.env.CONTRACTS_DIR || '../../contracts'
  });
  console.log(`🚀 AppServer listening on port ${PORT} (${USE_COMPUTE ? 'compute' : 'mock'} mode)`);
});
