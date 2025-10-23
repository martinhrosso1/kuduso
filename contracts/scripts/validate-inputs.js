#!/usr/bin/env node
/**
 * Validates input payloads against contract schemas
 * Usage: node validate-inputs.js <definition> <version> <payload-file>
 * Example: node validate-inputs.js sitefit 1.0.0 ../sitefit/1.0.0/examples/valid/minimal.json
 */

const fs = require('fs');
const path = require('path');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');

// Parse command line arguments
const args = process.argv.slice(2);
if (args.length < 3) {
  console.error('Usage: node validate-inputs.js <definition> <version> <payload-file>');
  console.error('Example: node validate-inputs.js sitefit 1.0.0 examples/valid/minimal.json');
  process.exit(1);
}

const [definition, version, payloadFile] = args;

// Resolve paths
const contractsDir = path.resolve(__dirname, '..');
const schemaPath = path.join(contractsDir, definition, version, 'inputs.schema.json');
const payloadPath = path.resolve(payloadFile);

// Check if schema exists
if (!fs.existsSync(schemaPath)) {
  console.error(`❌ Schema not found: ${schemaPath}`);
  process.exit(1);
}

// Check if payload exists
if (!fs.existsSync(payloadPath)) {
  console.error(`❌ Payload file not found: ${payloadPath}`);
  process.exit(1);
}

// Load schema and payload
let schema, payload;
try {
  schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  payload = JSON.parse(fs.readFileSync(payloadPath, 'utf8'));
} catch (error) {
  console.error(`❌ Error parsing JSON: ${error.message}`);
  process.exit(1);
}

// Validate
const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);

const validate = ajv.compile(schema);
const valid = validate(payload);

if (valid) {
  console.log(`✅ Validation passed: ${definition}@${version}`);
  console.log(`   Payload: ${path.basename(payloadPath)}`);
  process.exit(0);
} else {
  console.error(`❌ Validation failed: ${definition}@${version}`);
  console.error(`   Payload: ${path.basename(payloadPath)}`);
  console.error('\nErrors:');
  validate.errors.forEach((error, index) => {
    console.error(`  ${index + 1}. ${error.instancePath || '/'}: ${error.message}`);
    if (error.params) {
      console.error(`     Params: ${JSON.stringify(error.params)}`);
    }
  });
  process.exit(1);
}
