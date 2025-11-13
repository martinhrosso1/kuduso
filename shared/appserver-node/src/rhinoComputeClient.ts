/**
 * Rhino.Compute client for calling the Grasshopper solver
 * Handles HTTP communication with Rhino.Compute server
 */

import { logger } from './logger.js';

const COMPUTE_URL = process.env.COMPUTE_URL || 'http://localhost:8081';
const COMPUTE_API_KEY = process.env.COMPUTE_API_KEY || '';
const TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS || '240000', 10);

export interface GrasshopperValue {
  ParamName: string;
  InnerTree: {
    [branch: string]: Array<{
      type: string;
      data: any;
    }>;
  };
}

export interface GrasshopperRequest {
  algo: string;
  pointer: boolean;
  values: GrasshopperValue[];
}

export interface GrasshopperResponse {
  values: GrasshopperValue[];
  warnings?: string[];
  errors?: string[];
}

export class RhinoComputeError extends Error {
  constructor(
    message: string,
    public code: number,
    public details?: any
  ) {
    super(message);
    this.name = 'RhinoComputeError';
  }
}

/**
 * Call Rhino.Compute /grasshopper endpoint with timeout and error handling
 */
export async function callGrasshopper(
  request: GrasshopperRequest,
  correlationId: string,
  timeoutMs: number = TIMEOUT_MS
): Promise<GrasshopperResponse> {
  const url = `${COMPUTE_URL}/grasshopper`;
  
  logger.debug({
    event: 'compute.request',
    cid: correlationId,
    url,
    algo: request.algo,
    input_params: request.values.map(v => v.ParamName)
  });

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'RhinoComputeKey': COMPUTE_API_KEY,
        'x-correlation-id': correlationId
      },
      body: JSON.stringify(request),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      
      // Try to parse as JSON for more details
      let errorDetails = errorText;
      try {
        const errorJson = JSON.parse(errorText);
        errorDetails = JSON.stringify(errorJson, null, 2);
      } catch {
        // Not JSON, use as-is
      }
      
      logger.error({
        event: 'compute.http_error',
        cid: correlationId,
        status: response.status,
        statusText: response.statusText,
        contentType: response.headers.get('content-type'),
        errorBody: errorDetails,
        errorLength: errorText.length,
        hasContent: errorText.length > 0
      });

      // Map Compute errors to appropriate HTTP codes
      if (response.status === 401 || response.status === 403) {
        throw new RhinoComputeError('Compute authentication failed', 502, { status: response.status });
      } else if (response.status >= 500) {
        throw new RhinoComputeError('Compute server error', 503, { status: response.status, error: errorDetails });
      } else {
        throw new RhinoComputeError('Compute request failed', 422, { status: response.status, error: errorDetails });
      }
    }

    const result = (await response.json()) as GrasshopperResponse;

    logger.info({
      event: 'compute.response_success',
      cid: correlationId,
      output_params: result.values?.map(v => v.ParamName) || [],
      warnings_count: result.warnings?.length || 0,
      errors_count: result.errors?.length || 0,
      has_values: !!result.values && result.values.length > 0
    });

    // Log warnings if present
    if (result.warnings && result.warnings.length > 0) {
      logger.warn({
        event: 'compute.grasshopper_warnings',
        cid: correlationId,
        warnings: result.warnings
      });
    }

    // If Compute returned errors, log and throw
    if (result.errors && result.errors.length > 0) {
      logger.error({
        event: 'compute.grasshopper_errors',
        cid: correlationId,
        errors: result.errors
      });
      
      throw new RhinoComputeError(
        'Grasshopper execution failed',
        422,
        { errors: result.errors }
      );
    }

    return result;

  } catch (error: any) {
    clearTimeout(timeoutId);

    if (error.name === 'AbortError') {
      logger.error({
        event: 'compute.timeout',
        cid: correlationId,
        timeout_ms: timeoutMs
      });
      throw new RhinoComputeError('Compute request timed out', 504, { timeout_ms: timeoutMs });
    }

    if (error instanceof RhinoComputeError) {
      throw error;
    }

    // Network or other errors
    logger.error({
      event: 'compute.connection_failed',
      cid: correlationId,
      error: error.message,
      url
    });
    throw new RhinoComputeError('Failed to connect to Compute', 503, { error: error.message });
  }
}

/**
 * Check Compute health/availability
 */
export async function checkComputeHealth(): Promise<boolean> {
  try {
    const url = `${COMPUTE_URL}/version`;
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'RhinoComputeKey': COMPUTE_API_KEY
      },
      signal: AbortSignal.timeout(5000)
    });

    return response.ok;
  } catch (error) {
    logger.warn({
      event: 'compute.health_check_failed',
      url: COMPUTE_URL,
      error: error instanceof Error ? error.message : String(error)
    });
    return false;
  }
}

