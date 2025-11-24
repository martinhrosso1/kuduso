
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
    type: string;
    description: string;
  }>;
  outputs: Array<{
    gh_param: string;
    output_path: string;
    type: string;
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
  const startTime = Date.now();
  
  logger.debug({ 
    event: 'bindings.map_inputs.start', 
    cid: correlationId, 
    def, 
    ver,
    input_keys: Object.keys(inputs),
    input_size: JSON.stringify(inputs).length
  });

  const bindings = loadBindings(def, ver);
  const values: GrasshopperValue[] = [];

  logger.debug({
    event: 'bindings.loaded',
    cid: correlationId,
    input_bindings_count: bindings.inputs.length,
    output_bindings_count: bindings.outputs.length
  });

  await initRhino(); // Ensure rhino3dm is loaded

  for (const binding of bindings.inputs) {
    logger.debug({
      event: 'bindings.processing_input',
      cid: correlationId,
      param: binding.gh_param,
      type: binding.type,
      jsonpath: binding.jsonpath
    });

    // Extract value from JSON using JSONPath
    const result = JSONPath({ path: binding.jsonpath, json: inputs, wrap: false });
    
    if (result === undefined) {
      logger.warn({
        event: 'bindings.missing_input',
        cid: correlationId,
        param: binding.gh_param,
        jsonpath: binding.jsonpath,
        available_keys: Object.keys(inputs)
      });
      continue;
    }

    logger.debug({
      event: 'bindings.extracted_value',
      cid: correlationId,
      param: binding.gh_param,
      value_type: typeof result,
      is_array: Array.isArray(result),
      value_length: Array.isArray(result) ? result.length : undefined
    });

    let ghValue: GrasshopperValue;

    // Type-driven conversion (using binding.type from bindings.json)
    switch (binding.type) {
      case 'geometry.curve':
        // Convert coordinate array to Rhino curve
        if (!Array.isArray(result) || !Array.isArray(result[0])) {
          throw {
            code: 422,
            message: `Invalid geometry data for ${binding.gh_param}`,
            details: [{ param: binding.gh_param, expected: 'array of coordinates' }]
          };
        }
        const curve = await coordinatesToCurve(result);
        const encoded = await encodeRhinoObject(curve);
        ghValue = createTreeValue(binding.gh_param, 'Rhino.Geometry.PolylineCurve', JSON.parse(encoded));
        break;

      case 'json_string':
        // Stringify objects to JSON
        ghValue = createTreeValue(binding.gh_param, 'System.String', JSON.stringify(result));
        break;

      case 'integer':
        ghValue = createTreeValue(binding.gh_param, 'System.Int32', result);
        break;

      case 'number':
        // Use Int32 for integers, Double for floats
        if (typeof result === 'number' && Number.isInteger(result)) {
          ghValue = createTreeValue(binding.gh_param, 'System.Int32', result);
        } else {
          ghValue = createTreeValue(binding.gh_param, 'System.Double', result);
        }
        break;

      case 'string':
        ghValue = createTreeValue(binding.gh_param, 'System.String', result);
        break;

      case 'boolean':
        ghValue = createTreeValue(binding.gh_param, 'System.Boolean', result);
        break;

      default:
        // Fallback: infer type from JavaScript value
        if (typeof result === 'number') {
          ghValue = createTreeValue(binding.gh_param, Number.isInteger(result) ? 'System.Int32' : 'System.Double', result);
        } else if (typeof result === 'string') {
          ghValue = createTreeValue(binding.gh_param, 'System.String', result);
        } else if (typeof result === 'boolean') {
          ghValue = createTreeValue(binding.gh_param, 'System.Boolean', result);
        } else {
          // Complex objects: stringify
          ghValue = createTreeValue(binding.gh_param, 'System.String', JSON.stringify(result));
        }
    }

    values.push(ghValue);
    
    logger.debug({
      event: 'bindings.mapped_input',
      cid: correlationId,
      param: binding.gh_param,
      gh_type: ghValue.InnerTree["0"][0].type,
      binding_type: binding.type,
      data_size: JSON.stringify(ghValue).length
    });
  }

  const duration = Date.now() - startTime;
  
  logger.info({
    event: 'bindings.map_inputs.complete',
    cid: correlationId,
    mapped_count: values.length,
    duration_ms: duration
  });

  return values;
}

/**
 * Set a value in an object using a JSONPath-like path
 */
function setValueByPath(obj: any, path: string, value: any): void {
  // Handle array paths like $.results[*].transform
  const arrayMatch = path.match(/^\$\.(\w+)\[\*\]\.(\w+)$/);
  
  if (arrayMatch) {
    const [, arrayKey, itemKey] = arrayMatch;
    if (!obj[arrayKey]) {
      obj[arrayKey] = [];
    }
    // For array paths, value is an array of items
    if (Array.isArray(value)) {
      for (let i = 0; i < value.length; i++) {
        if (!obj[arrayKey][i]) {
          obj[arrayKey][i] = {};
        }
        obj[arrayKey][i][itemKey] = value[i];
      }
    }
    return;
  }

  // Handle simple paths like $.result
  const simpleMatch = path.match(/^\$\.(\w+)$/);
  if (simpleMatch) {
    const [, key] = simpleMatch;
    // For simple paths, if value is an array with one item, unwrap it
    if (Array.isArray(value) && value.length === 1) {
      obj[key] = value[0];
    } else {
      obj[key] = value;
    }
    return;
  }

  // Fallback: direct assignment
  logger.warn({
    event: 'bindings.path_fallback',
    path,
    message: 'Unsupported path format, using direct assignment'
  });
  obj[path] = value;
}

/**
 * Map Grasshopper output Data Trees back to JSON (contract-agnostic)
 */
export function mapDataTreeToOutputs(
  ghOutput: any,
  def: string,
  ver: string,
  correlationId: string
): any {
  const startTime = Date.now();
  
  logger.debug({ 
    event: 'bindings.map_outputs.start', 
    cid: correlationId, 
    def, 
    ver,
    gh_output_params: ghOutput.values?.map((v: any) => v.ParamName) || []
  });

  const bindings = loadBindings(def, ver);
  
  logger.debug({
    event: 'bindings.output_bindings_loaded',
    cid: correlationId,
    expected_params: bindings.outputs.map(o => o.gh_param),
    output_paths: bindings.outputs.map(o => o.output_path)
  });
  
  // Extract output values by parameter name
  const outputMap: { [key: string]: any[] } = {};
  
  for (const value of ghOutput.values) {
    const paramName = value.ParamName;
    const branch = value.InnerTree["0"] || [];
    
    logger.debug({
      event: 'bindings.extracting_gh_output',
      cid: correlationId,
      param: paramName,
      branch_size: branch.length,
      item_types: branch.map((item: any) => item.type).slice(0, 3) // Log first 3 types
    });
    
    // Extract data from each item in the branch
    const extractedData = branch.map((item: any) => item.data);
    outputMap[paramName] = extractedData;
  }

  // Dynamically build output object using bindings
  const result: any = {};
  
  for (const outputBinding of bindings.outputs) {
    const ghData = outputMap[outputBinding.gh_param] || [];
    
    logger.debug({
      event: 'bindings.processing_output',
      cid: correlationId,
      param: outputBinding.gh_param,
      type: outputBinding.type,
      output_path: outputBinding.output_path,
      data_count: ghData.length,
      sample_data: ghData.slice(0, 2) // Log first 2 items
    });
    
    // Type-driven conversion
    let processedData: any[];
    
    switch (outputBinding.type) {
      case 'json_string':
        // Parse JSON strings
        processedData = ghData.map((item, index) => {
          if (typeof item === 'string') {
            try {
              const parsed = JSON.parse(item);
              logger.debug({
                event: 'bindings.json_parsed',
                cid: correlationId,
                param: outputBinding.gh_param,
                index,
                parsed_keys: typeof parsed === 'object' ? Object.keys(parsed) : undefined
              });
              return parsed;
            } catch (e) {
              logger.warn({
                event: 'bindings.parse_error',
                cid: correlationId,
                param: outputBinding.gh_param,
                index,
                error: e instanceof Error ? e.message : String(e),
                raw_value: item.substring(0, 100) // Log first 100 chars
              });
              return item;
            }
          }
          return item;
        });
        break;

      case 'number':
      case 'integer':
      case 'string':
      case 'boolean':
        // Use as-is
        processedData = ghData;
        logger.debug({
          event: 'bindings.primitive_type',
          cid: correlationId,
          param: outputBinding.gh_param,
          type: outputBinding.type,
          count: processedData.length
        });
        break;

      default:
        // Unknown type: use as-is
        processedData = ghData;
        logger.warn({
          event: 'bindings.unknown_type',
          cid: correlationId,
          param: outputBinding.gh_param,
          type: outputBinding.type
        });
    }

    // Map to output path using JSONPath
    logger.debug({
      event: 'bindings.mapping_to_path',
      cid: correlationId,
      param: outputBinding.gh_param,
      output_path: outputBinding.output_path,
      processed_count: processedData.length
    });
    
    setValueByPath(result, outputBinding.output_path, processedData);
  }

  const duration = Date.now() - startTime;
  
  logger.info({
    event: 'bindings.map_outputs.complete',
    cid: correlationId,
    output_keys: Object.keys(result),
    result_size: JSON.stringify(result).length,
    duration_ms: duration
  });

  return result;
}

