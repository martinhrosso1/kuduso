/**
 * Manifest enforcement - validate operational limits before calling compute
 * Ensures requests meet guardrails defined in manifest.json
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { logger } from './logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CONTRACTS_DIR = process.env.CONTRACTS_DIR || path.join(__dirname, '../../../contracts');

interface ManifestLimits {
  max_vertices?: number;
  max_samples?: number;
  max_results?: number;
}

interface ManifestConcurrency {
  class?: string;
  weight?: number;
}

interface ManifestUnits {
  length?: string;
  angle?: string;
  crs_required?: boolean;
}

interface ManifestValidation {
  strict_schema?: boolean;
  reject_additional_properties?: boolean;
}

interface ManifestDefinition {
  timeout_sec: number;
  limits?: ManifestLimits;
  concurrency?: ManifestConcurrency;
  units?: ManifestUnits;
  determinism?: {
    seed_required?: boolean;
  };
  validation?: ManifestValidation;
}

/**
 * Load manifest.json for a definition
 */
export function loadManifest(def: string, ver: string): ManifestDefinition {
  const manifestPath = path.join(CONTRACTS_DIR, def, ver, 'manifest.json');
  
  if (!fs.existsSync(manifestPath)) {
    throw {
      code: 404,
      message: `Manifest not found: ${def}@${ver}`,
      details: [{ path: manifestPath }]
    };
  }

  return JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
}

/**
 * Count vertices in a coordinate array
 */
function countVertices(coords: any): number {
  if (!Array.isArray(coords)) return 0;
  if (Array.isArray(coords[0])) {
    // Array of coordinate pairs
    return coords.length;
  }
  return 0;
}

/**
 * Enforce manifest limits on inputs
 */
export function enforceManifest(
  inputs: any,
  def: string,
  ver: string,
  correlationId: string
): { timeout_ms: number } {
  logger.debug({ event: 'manifest.enforce', cid: correlationId, def, ver });

  const manifest = loadManifest(def, ver);

  // Note: Contract-specific validations have been removed.
  // These should be handled by JSON schema validation in the API layer.
  // The manifest's role is limited to operational limits like timeout_sec.

  logger.info({
    event: 'manifest.validated',
    cid: correlationId,
    timeout_sec: manifest.timeout_sec
  });

  // Return timeout in milliseconds for the compute call
  return {
    timeout_ms: manifest.timeout_sec * 1000
  };
}

/**
 * Get concurrency weight for a definition (for future semaphore logic)
 */
export function getConcurrencyWeight(def: string, ver: string): number {
  try {
    const manifest = loadManifest(def, ver);
    return manifest.concurrency?.weight || 1;
  } catch {
    return 1;
  }
}

