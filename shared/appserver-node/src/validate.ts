import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ajv = new Ajv({ allErrors: true });
addFormats(ajv);

const CONTRACTS_DIR = process.env.CONTRACTS_DIR || path.join(__dirname, '../../../contracts');

interface ValidationError {
  code: number;
  message: string;
  details: any[];
}

function loadSchema(def: string, ver: string, type: 'inputs' | 'outputs'): any {
  const schemaPath = path.join(CONTRACTS_DIR, def, ver, `${type}.schema.json`);
  
  if (!fs.existsSync(schemaPath)) {
    throw {
      code: 404,
      message: `Contract not found: ${def}@${ver}`,
      details: [{ path: schemaPath, type }]
    } as ValidationError;
  }

  try {
    return JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  } catch (error: any) {
    throw {
      code: 500,
      message: `Failed to load ${type} schema`,
      details: [{ error: error.message }]
    } as ValidationError;
  }
}

export function validateInputs(def: string, ver: string, body: any): any {
  const schema = loadSchema(def, ver, 'inputs');
  const validate = ajv.compile(schema);

  if (!validate(body)) {
    throw {
      code: 400,
      message: 'Input validation failed',
      details: validate.errors || []
    } as ValidationError;
  }

  return body;
}

export function validateOutputs(def: string, ver: string, body: any): any {
  const schema = loadSchema(def, ver, 'outputs');
  const validate = ajv.compile(schema);

  if (!validate(body)) {
    throw {
      code: 500,
      message: 'Output validation failed - mock result violated contract',
      details: validate.errors || []
    } as ValidationError;
  }

  return body;
}
