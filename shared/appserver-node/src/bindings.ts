
/**
 * Bindings module - maps JSON inputs to Grasshopper Data Trees
 * Uses contracts/bindings.json to declaratively map inputs/outputs
 */

import { JSONPath } from 'jsonpath-plus';
import rhino3dm from 'rhino3dm';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { logger } from './logger.js';
import type { GrasshopperValue } from './rhinoComputeClient.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CONTRACTS_DIR = process.env.CONTRACTS_DIR || path.join(__dirname, '../../../contracts');

let rhinoModule: any = null;

/**
 * Initialize rhino3dm WASM module (async)
 */
async function initRhino() {
  if (!rhinoModule) {
    rhinoModule = await rhino3dm();
  }
  return rhinoModule;
}

interface BindingDefinition {
  engine: string;
  definition: string;
  inputs: Array<{
    jsonpath: string;
    gh_param: string;
    description: string;
  }>;
  outputs: Array<{
    gh_param: string;
    output_path: string;
    description: string;
  }>;
}

/**
 * Load bindings.json for a definition
 */
function loadBindings(def: string, ver: string): BindingDefinition {
  const bindingsPath = path.join(CONTRACTS_DIR, def, ver, 'bindings.json');
  
  if (!fs.existsSync(bindingsPath)) {
    throw {
      code: 404,
      message: `Bindings not found: ${def}@${ver}`,
      details: [{ path: bindingsPath }]
    };
  }

  return JSON.parse(fs.readFileSync(bindingsPath, 'utf8'));
}

/**
 * Convert coordinates array [[x,y], ...] to Rhino PolylineCurve
 */
async function coordinatesToCurve(coords: number[][]): Promise<any> {
  const rhino = await initRhino();
  
  // Create a Polyline from points
  const polyline = new rhino.Polyline();
  
  for (const [x, y] of coords) {
    polyline.add(x, y, 0);
  }
  
  // Close the polyline if it's not already closed
  const first = coords[0];
  const last = coords[coords.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) {
    polyline.add(first[0], first[1], 0);
  }
  
  // Create a PolylineCurve using constructor (not a static method)
  const curve = new rhino.PolylineCurve(polyline);
  
  return curve;
}

/**
 * Encode a Rhino object for Compute API
 */
async function encodeRhinoObject(obj: any): Promise<string> {
  const rhino = await initRhino();
  const encoded = JSON.stringify(obj.encode());
  return encoded;
}

/**
 * Create a Grasshopper Data Tree value for a parameter
 */
function createTreeValue(paramName: string, type: string, data: any): GrasshopperValue {
  return {
    ParamName: paramName,
    InnerTree: {
      "0": [
        {
          type,
          data
        }
      ]
    }
  };
}

/**
 * Map JSON inputs to Grasshopper Data Tree format
 */
export async function mapInputsToDataTree(
  inputs: any,
  def: string,
  ver: string,
  correlationId: string
): Promise<GrasshopperValue[]> {
  logger.debug({ event: 'bindings.map_inputs', cid: correlationId, def, ver });

  const bindings = loadBindings(def, ver);
  const values: GrasshopperValue[] = [];

  await initRhino(); // Ensure rhino3dm is loaded

  for (const binding of bindings.inputs) {
    // Extract value from JSON using JSONPath
    const result = JSONPath({ path: binding.jsonpath, json: inputs, wrap: false });
    
    if (result === undefined) {
      logger.warn({
        event: 'bindings.missing_input',
        cid: correlationId,
        param: binding.gh_param,
        jsonpath: binding.jsonpath
      });
      continue;
    }

    let ghValue: GrasshopperValue;

    // Special handling for different parameter types
    if (binding.gh_param.includes('polygon') && Array.isArray(result) && Array.isArray(result[0])) {
      // This is a polygon - convert to curve
      const curve = await coordinatesToCurve(result);
      const encoded = await encodeRhinoObject(curve);
      ghValue = createTreeValue(binding.gh_param, 'Rhino.Geometry.PolylineCurve', JSON.parse(encoded));
    } else if (binding.gh_param === 'rotation_spec') {
      // Rotation spec is passed as JSON string
      ghValue = createTreeValue(binding.gh_param, 'System.String', JSON.stringify(result));
    } else if (typeof result === 'number') {
      // Numeric values
      if (Number.isInteger(result)) {
        ghValue = createTreeValue(binding.gh_param, 'System.Int32', result);
      } else {
        ghValue = createTreeValue(binding.gh_param, 'System.Double', result);
      }
    } else if (typeof result === 'string') {
      ghValue = createTreeValue(binding.gh_param, 'System.String', result);
    } else if (typeof result === 'boolean') {
      ghValue = createTreeValue(binding.gh_param, 'System.Boolean', result);
    } else {
      // Default: stringify complex objects
      ghValue = createTreeValue(binding.gh_param, 'System.String', JSON.stringify(result));
    }

    values.push(ghValue);
    
    logger.debug({
      event: 'bindings.mapped_input',
      cid: correlationId,
      param: binding.gh_param,
      type: ghValue.InnerTree["0"][0].type
    });
  }

  return values;
}

/**
 * Map Grasshopper output Data Trees back to JSON
 */
export function mapDataTreeToOutputs(
  ghOutput: any,
  def: string,
  ver: string,
  correlationId: string
): any {
  logger.debug({ event: 'bindings.map_outputs', cid: correlationId, def, ver });

  const bindings = loadBindings(def, ver);
  
  // Extract output values by parameter name
  const outputMap: { [key: string]: any[] } = {};
  
  for (const value of ghOutput.values) {
    const paramName = value.ParamName;
    const branch = value.InnerTree["0"] || [];
    
    // Extract data from each item in the branch
    const extractedData = branch.map((item: any) => {
      if (item.type === 'System.String') {
        return item.data;
      } else {
        return item.data;
      }
    });
    
    outputMap[paramName] = extractedData;
  }

  // Build result array from the three parallel arrays
  const transforms = outputMap['placed_transforms'] || [];
  const scores = outputMap['placement_scores'] || [];
  const kpis = outputMap['kpis'] || [];

  const results = [];
  const maxLength = Math.max(transforms.length, scores.length, kpis.length);

  for (let i = 0; i < maxLength; i++) {
    const transformStr = transforms[i];
    const score = scores[i];
    const kpisStr = kpis[i];

    let transform;
    let metrics;

    try {
      transform = typeof transformStr === 'string' ? JSON.parse(transformStr) : transformStr;
    } catch (e) {
      logger.warn({
        event: 'bindings.parse_error',
        cid: correlationId,
        field: 'transform',
        index: i,
        error: e instanceof Error ? e.message : String(e)
      });
      transform = {};
    }

    try {
      metrics = typeof kpisStr === 'string' ? JSON.parse(kpisStr) : kpisStr;
    } catch (e) {
      logger.warn({
        event: 'bindings.parse_error',
        cid: correlationId,
        field: 'kpis',
        index: i,
        error: e instanceof Error ? e.message : String(e)
      });
      metrics = {};
    }

    results.push({
      id: `result-${i}`,
      transform,
      score: score !== undefined ? score : 0,
      metrics
    });
  }

  logger.info({
    event: 'bindings.outputs_mapped',
    cid: correlationId,
    results_count: results.length
  });

  return {
    results,
    artifacts: [], // Artifacts handling can be added later
    metadata: {
      definition: def,
      version: ver,
      units: {
        length: 'm',
        angle: 'deg'
      },
      generated_at: new Date().toISOString(),
      engine: {
        name: 'rhino.compute',
        mode: 'batch'
      },
      cache_hit: false,
      warnings: ghOutput.warnings || []
    }
  };
}

