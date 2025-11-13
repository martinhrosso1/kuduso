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
  // Windows path with escaped backslashes for JSON
  const ghxPath = `${COMPUTE_DEFINITIONS_PATH}\\\\${definition}\\\\${version}\\\\ghlogic.ghx`;
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
    const { timeout_ms } = enforceManifest(inputs, definition, version, correlationId);

    // Step 2: Map JSON inputs to Grasshopper DataTree format
    const ghInputs = await mapInputsToDataTree(inputs, definition, version, correlationId);

    // Step 3: Build Grasshopper request
    const ghPath = buildDefinitionPath(definition, version);
    const request: GrasshopperRequest = {
      algo: ghPath,
      pointer: true, // File is on the Compute VM
      values: ghInputs
    };

    logger.debug({
      event: 'compute.grasshopper.request',
      cid: correlationId,
      algo: ghPath,
      timeout_ms
    });

    // Step 4: Call Rhino.Compute with timeout
    const ghResponse = await callGrasshopper(request, correlationId, timeout_ms);

    // Step 5: Map outputs back to JSON
    const result = mapDataTreeToOutputs(ghResponse, definition, version, correlationId);

    const duration_ms = Date.now() - startTime;

    logger.info({
      event: 'compute.solve.success',
      cid: correlationId,
      def: definition,
      ver: version,
      duration_ms,
      results_count: result.results?.length || 0
    });

    // Add duration to metadata
    result.metadata.duration_ms = duration_ms;

    return result;

  } catch (error: any) {
    const duration_ms = Date.now() - startTime;

    logger.error({
      event: 'compute.solve.error',
      cid: correlationId,
      def: definition,
      ver: version,
      error: error.message,
      code: error.code || 500,
      duration_ms
    });

    // Re-throw with proper error structure
    throw {
      code: error.code || 500,
      message: error.message || 'Compute solve failed',
      details: error.details || []
    };
  }
}

