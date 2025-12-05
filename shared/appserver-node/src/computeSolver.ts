/**
 * Compute solver - orchestrates real Rhino.Compute calls
 * Replaces mockSolver when USE_COMPUTE=true
 */

import path from 'node:path';
import { logger } from './logger.js';
import { enforceManifest } from './manifest.js';
import { mapInputsToDataTree, mapDataTreeToOutputs } from './bindings.js';
import { callGrasshopper, type GrasshopperRequest } from './rhinoComputeClient.js';

// Path to Grasshopper definitions on the Compute VM
const COMPUTE_DEFINITIONS_PATH = process.env.COMPUTE_DEFINITIONS_PATH || 'C:\\\\compute';

/**
 * Build the full path to the .ghx file on the Compute VM
 */
function buildDefinitionPath(definition: string, version: string): string {
  // Windows path - COMPUTE_DEFINITIONS_PATH already has escaped backslashes
  const ghxPath = `${COMPUTE_DEFINITIONS_PATH}\\${definition}\\${version}\\ghlogic.ghx`;
  return ghxPath;
}

/**
 * Real compute solver - calls Rhino.Compute via Grasshopper API
 */
export async function computeSolve(
  inputs: any,
  definition: string,
  version: string,
  correlationId: string
): Promise<any> {
  const startTime = Date.now();

  logger.info({
    event: 'compute.solve.start',
    cid: correlationId,
    def: definition,
    ver: version
  });

  try {
    // Step 1: Enforce manifest limits and get timeout
    logger.debug({ event: 'compute.step1.manifest', cid: correlationId });
    const manifestStart = Date.now();
    const { timeout_ms } = enforceManifest(inputs, definition, version, correlationId);
    logger.debug({ 
      event: 'compute.step1.complete', 
      cid: correlationId, 
      timeout_ms, 
      duration_ms: Date.now() - manifestStart 
    });

    // Step 2: Map JSON inputs to Grasshopper DataTree format
    logger.debug({ event: 'compute.step2.bindings_input', cid: correlationId });
    const bindingsStart = Date.now();
    const ghInputs = await mapInputsToDataTree(inputs, definition, version, correlationId);
    logger.debug({ 
      event: 'compute.step2.complete', 
      cid: correlationId, 
      gh_inputs_count: ghInputs.length,
      duration_ms: Date.now() - bindingsStart 
    });

    // Step 3: Build Grasshopper request
    logger.debug({ event: 'compute.step3.build_request', cid: correlationId });
    const ghPath = buildDefinitionPath(definition, version);
    const request: GrasshopperRequest = {
      pointer: ghPath,
      values: ghInputs
    };

    logger.debug({
      event: 'compute.grasshopper.request',
      cid: correlationId,
      pointer: ghPath,
      timeout_ms,
      input_count: ghInputs.length,
      input_params: ghInputs.map(v => ({
        param: v.ParamName,
        path_count: Object.keys(v.InnerTree).length
      })),
      request_size: JSON.stringify(request).length
    });

    // Step 4: Call Rhino.Compute with timeout
    logger.info({ 
      event: 'compute.step4.calling_rhino', 
      cid: correlationId, 
      timeout_ms 
    });
    const computeStart = Date.now();
    const ghResponse = await callGrasshopper(request, correlationId, timeout_ms);
    const computeDuration = Date.now() - computeStart;
    logger.info({ 
      event: 'compute.step4.complete', 
      cid: correlationId, 
      duration_ms: computeDuration 
    });

    // Step 5: Map outputs back to JSON
    logger.debug({ event: 'compute.step5.bindings_output', cid: correlationId });
    const outputStart = Date.now();
    const result = mapDataTreeToOutputs(ghResponse, definition, version, correlationId);
    logger.debug({ 
      event: 'compute.step5.complete', 
      cid: correlationId,
      output_keys: Object.keys(result),
      duration_ms: Date.now() - outputStart 
    });

    const duration_ms = Date.now() - startTime;

    logger.info({
      event: 'compute.solve.success',
      cid: correlationId,
      def: definition,
      ver: version,
      duration_ms,
      timing: {
        manifest: manifestStart - startTime,
        input_bindings: bindingsStart - manifestStart,
        compute_call: computeDuration,
        output_bindings: Date.now() - outputStart,
        total: duration_ms
      },
      output_structure: Object.keys(result)
    });

    return result;

  } catch (error: any) {
    const duration_ms = Date.now() - startTime;

    logger.error({
      event: 'compute.solve.error',
      cid: correlationId,
      def: definition,
      ver: version,
      error: error.message,
      error_name: error.name,
      code: error.code || 500,
      duration_ms,
      stack: error.stack?.split('\n').slice(0, 3), // First 3 lines of stack
      details: error.details
    });

    // Re-throw with proper error structure
    throw {
      code: error.code || 500,
      message: error.message || 'Compute solve failed',
      details: error.details || []
    };
  }
}

