import express, { Request, Response } from 'express';
import cors from 'cors';
import { randomUUID } from 'crypto';
import { validateInputs, validateOutputs } from './validate.js';
import { mockSolve } from './mockSolver.js';
import { computeSolve } from './computeSolver.js';
import { checkComputeHealth } from './rhinoComputeClient.js';
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
app.get('/ready', async (req: Request, res: Response) => {
  let computeHealthy = true;
  
  if (USE_COMPUTE) {
    computeHealthy = await checkComputeHealth();
    if (!computeHealthy) {
      return res.status(503).json({ 
        status: 'not_ready', 
        service: 'appserver-node',
        reason: 'Compute server unavailable'
      });
    }
  }
  
  res.json({ 
    status: 'ready', 
    service: 'appserver-node',
    mode: USE_COMPUTE ? 'compute' : 'mock',
    compute_healthy: computeHealthy
  });
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

    // Route to appropriate solver based on USE_COMPUTE flag
    let result;
    if (USE_COMPUTE) {
      result = await computeSolve(inputs, def, ver, cid);
    } else {
      result = await mockSolve(inputs, def, ver);
    }
    
    logger.debug({ cid, def, ver, event: 'solve.complete', duration_ms: Date.now() - startTime });

    // Validate outputs against contract schema
    validateOutputs(def, ver, result);
    
    logger.info({ 
      cid, 
      def, 
      ver, 
      event: 'solve.success', 
      duration_ms: Date.now() - startTime,
      results_count: result.results?.length || 0,
      mode: USE_COMPUTE ? 'compute' : 'mock'
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
