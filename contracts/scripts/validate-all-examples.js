#!/usr/bin/env node
/**
 * Validates all example payloads in contracts directory
 * Usage: node validate-all-examples.js [definition] [version]
 * Example: node validate-all-examples.js sitefit 1.0.0
 * If no args provided, validates all definitions
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const contractsDir = path.resolve(__dirname, '..');
const args = process.argv.slice(2);

let results = {
  passed: [],
  failed: []
};

function findContracts() {
  if (args.length >= 2) {
    // Specific definition and version
    return [{ definition: args[0], version: args[1] }];
  }
  
  // Find all contracts
  const contracts = [];
  const definitions = fs.readdirSync(contractsDir, { withFileTypes: true })
    .filter(dirent => dirent.isDirectory() && !dirent.name.startsWith('_') && !dirent.name.startsWith('.'))
    .map(dirent => dirent.name);
  
  for (const definition of definitions) {
    const defPath = path.join(contractsDir, definition);
    const versions = fs.readdirSync(defPath, { withFileTypes: true })
      .filter(dirent => dirent.isDirectory())
      .map(dirent => dirent.name);
    
    for (const version of versions) {
      contracts.push({ definition, version });
    }
  }
  
  return contracts;
}

function validateExamples(definition, version) {
  const examplesDir = path.join(contractsDir, definition, version, 'examples');
  
  if (!fs.existsSync(examplesDir)) {
    console.log(`⚠️  No examples directory for ${definition}@${version}`);
    return;
  }
  
  // Find all JSON files recursively
  const validDir = path.join(examplesDir, 'valid');
  const invalidDir = path.join(examplesDir, 'invalid');
  
  // Validate "valid" examples (should pass)
  if (fs.existsSync(validDir)) {
    const validFiles = fs.readdirSync(validDir).filter(f => f.endsWith('.json'));
    
    for (const file of validFiles) {
      const filePath = path.join(validDir, file);
      const testName = `${definition}@${version}/valid/${file}`;
      
      try {
        execSync(`node ${path.join(__dirname, 'validate-inputs.js')} ${definition} ${version} ${filePath}`, {
          stdio: 'pipe'
        });
        results.passed.push(testName);
        console.log(`✅ ${testName}`);
      } catch (error) {
        results.failed.push({ test: testName, error: error.stderr?.toString() || error.message });
        console.error(`❌ ${testName}`);
      }
    }
  }
  
  // Validate "invalid" examples (should fail)
  if (fs.existsSync(invalidDir)) {
    const invalidFiles = fs.readdirSync(invalidDir).filter(f => f.endsWith('.json'));
    
    for (const file of invalidFiles) {
      const filePath = path.join(invalidDir, file);
      const testName = `${definition}@${version}/invalid/${file}`;
      
      try {
        execSync(`node ${path.join(__dirname, 'validate-inputs.js')} ${definition} ${version} ${filePath}`, {
          stdio: 'pipe'
        });
        // If validation passed but should have failed
        results.failed.push({ test: testName, error: 'Expected validation to fail but it passed' });
        console.error(`❌ ${testName} (should have failed)`);
      } catch (error) {
        // Expected to fail
        results.passed.push(testName);
        console.log(`✅ ${testName} (correctly rejected)`);
      }
    }
  }
}

// Main execution
console.log('🔍 Validating contract examples...\n');

const contracts = findContracts();
if (contracts.length === 0) {
  console.log('No contracts found.');
  process.exit(0);
}

for (const { definition, version } of contracts) {
  console.log(`\n📋 ${definition}@${version}`);
  validateExamples(definition, version);
}

// Summary
console.log('\n' + '='.repeat(60));
console.log('Summary:');
console.log(`✅ Passed: ${results.passed.length}`);
console.log(`❌ Failed: ${results.failed.length}`);

if (results.failed.length > 0) {
  console.log('\nFailed tests:');
  results.failed.forEach(({ test, error }) => {
    console.log(`  - ${test}`);
    if (error) {
      console.log(`    ${error.split('\n')[0]}`);
    }
  });
  process.exit(1);
}

console.log('\n✨ All contract validations passed!');
process.exit(0);
