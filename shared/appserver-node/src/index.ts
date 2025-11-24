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

  logger.info({ 
    cid, 
    def, 
    ver, 
    event: 'solve.start',
    request_size: JSON.stringify(req.body).length,
    input_keys: Object.keys(req.body || {}),
    mode: USE_COMPUTE ? 'compute' : 'mock'
  });

  try {
    // Validate inputs against contract schema
    const validationStart = Date.now();
    const inputs = validateInputs(def, ver, req.body);
    
    logger.debug({ 
      cid, 
      def, 
      ver, 
      event: 'inputs.validated',
      validation_ms: Date.now() - validationStart
    });

    // Route to appropriate solver based on USE_COMPUTE flag
    let result;
    if (USE_COMPUTE) {
      logger.debug({ cid, event: 'routing.compute' });
      result = await computeSolve(inputs, def, ver, cid);
    } else {
      logger.debug({ cid, event: 'routing.mock' });
      result = await mockSolve(inputs, def, ver);
    }
    
    logger.debug({ 
      cid, 
      def, 
      ver, 
      event: 'solve.complete', 
      duration_ms: Date.now() - startTime 
    });

    // Validate outputs against contract schema
    const outputValidationStart = Date.now();
    validateOutputs(def, ver, result);
    logger.debug({
      cid,
      event: 'outputs.validated',
      validation_ms: Date.now() - outputValidationStart
    });
    
    const duration_ms = Date.now() - startTime;
    
    logger.info({ 
      cid, 
      def, 
      ver, 
      event: 'solve.success', 
      duration_ms,
      output_keys: Object.keys(result),
      response_size: JSON.stringify(result).length,
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
      error_name: error.name,
      code,
      duration_ms,
      stack: error.stack?.split('\n').slice(0, 5) // First 5 lines
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
