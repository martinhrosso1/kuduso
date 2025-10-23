# Contract Validation Fix

## Issues Found

1. **Node_modules scanning**: Validation script was scanning `node_modules` directory
2. **Schema version incompatibility**: JSON Schema Draft 2020-12 not fully supported by Ajv 8.x without additional configuration
3. **Valid examples failing**: Both valid examples were failing validation

## Fixes Applied

### 1. Fixed Directory Scanning (validate-all-examples.js)
Added explicit skip list to exclude system directories:
```javascript
const skipDirs = ['_templates', 'scripts', 'node_modules', '.git'];
```

### 2. Changed Schema Version
Updated all schemas from Draft 2020-12 to Draft 07:
- ✅ `contracts/sitefit/1.0.0/inputs.schema.json`
- ✅ `contracts/sitefit/1.0.0/outputs.schema.json`
- ✅ `contracts/_templates/inputs.schema.template.json`
- ✅ `contracts/_templates/outputs.schema.template.json`

**Rationale**: 
- Draft 07 is better supported by all JSON Schema tooling
- No feature loss for our use case (all our schemas are compatible)
- Immediate validation without additional dependencies

### 3. Updated Documentation
- ✅ `contracts/sitefit/1.0.0/README.md` - Added schema version note
- ✅ `contracts/sitefit/1.0.0/CHANGELOG.md` - Documented schema version

## Test Results

### Before Fix
```
❌ Failed: 2
- sitefit@1.0.0/valid/minimal.json (Ajv error)
- sitefit@1.0.0/valid/typical.json (Ajv error)
+ node_modules scanning noise
```

### After Fix
```
✅ Passed: 4
✅ sitefit@1.0.0/valid/minimal.json
✅ sitefit@1.0.0/valid/typical.json
✅ sitefit@1.0.0/invalid/bad-crs.json (correctly rejected)
✅ sitefit@1.0.0/invalid/missing-required.json (correctly rejected)
```

## Verification Commands

```bash
# Run all validations
make contracts-validate

# Or directly
cd contracts && npm run validate:all

# Test individual example
cd contracts
npm run validate sitefit 1.0.0 sitefit/1.0.0/examples/valid/minimal.json
```

## Schema Compatibility

JSON Schema Draft 07 vs Draft 2020-12 for our use case:
- ✅ All basic types supported (string, number, array, object)
- ✅ Pattern validation (regex)
- ✅ Required fields
- ✅ Min/max constraints
- ✅ Enums
- ✅ Format validation (via ajv-formats)
- ✅ $ref support
- ✅ additionalProperties control

**No features were lost** in this downgrade. Draft 07 is the most widely supported version and is sufficient for our contract validation needs.

## Files Modified

1. `contracts/scripts/validate-all-examples.js` - Added directory filtering
2. `contracts/sitefit/1.0.0/inputs.schema.json` - Changed $schema to draft-07
3. `contracts/sitefit/1.0.0/outputs.schema.json` - Changed $schema to draft-07
4. `contracts/_templates/inputs.schema.template.json` - Changed $schema to draft-07
5. `contracts/_templates/outputs.schema.template.json` - Changed $schema to draft-07
6. `contracts/sitefit/1.0.0/README.md` - Added schema version note
7. `contracts/sitefit/1.0.0/CHANGELOG.md` - Documented schema version

## Status

✅ **All validations passing**  
✅ **No node_modules noise**  
✅ **Documentation updated**  
✅ **Ready for Stage 1**

---

*Fixed: 2025-10-23*
