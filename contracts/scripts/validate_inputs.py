#!/usr/bin/env python3
"""
Validates input payloads against contract schemas using jsonschema
Usage: python validate_inputs.py <definition> <version> <payload-file>
Example: python validate_inputs.py sitefit 1.0.0 ../sitefit/1.0.0/examples/valid/minimal.json
"""

import json
import sys
from pathlib import Path
from jsonschema import validate, ValidationError, Draft202012Validator
from jsonschema.validators import validator_for


def load_json(file_path: Path) -> dict:
    """Load and parse JSON file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"❌ Error parsing JSON: {e}")
        sys.exit(1)
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        sys.exit(1)


def validate_payload(definition: str, version: str, payload_file: str) -> None:
    """Validate a payload against contract schema"""
    # Resolve paths
    contracts_dir = Path(__file__).parent.parent
    schema_path = contracts_dir / definition / version / "inputs.schema.json"
    payload_path = Path(payload_file).resolve()
    
    # Check if files exist
    if not schema_path.exists():
        print(f"❌ Schema not found: {schema_path}")
        sys.exit(1)
    
    if not payload_path.exists():
        print(f"❌ Payload file not found: {payload_path}")
        sys.exit(1)
    
    # Load schema and payload
    schema = load_json(schema_path)
    payload = load_json(payload_path)
    
    # Validate
    try:
        validator_class = validator_for(schema)
        validator_class.check_schema(schema)  # Validate schema itself
        validator = validator_class(schema)
        validator.validate(payload)
        
        print(f"✅ Validation passed: {definition}@{version}")
        print(f"   Payload: {payload_path.name}")
        sys.exit(0)
        
    except ValidationError as e:
        print(f"❌ Validation failed: {definition}@{version}")
        print(f"   Payload: {payload_path.name}")
        print(f"\nError:")
        print(f"  Path: {'.'.join(str(p) for p in e.absolute_path) or '/'}")
        print(f"  Message: {e.message}")
        if e.validator:
            print(f"  Validator: {e.validator}")
        sys.exit(1)
        
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)


def main():
    """Main entry point"""
    if len(sys.argv) < 4:
        print("Usage: python validate_inputs.py <definition> <version> <payload-file>")
        print("Example: python validate_inputs.py sitefit 1.0.0 examples/valid/minimal.json")
        sys.exit(1)
    
    definition = sys.argv[1]
    version = sys.argv[2]
    payload_file = sys.argv[3]
    
    validate_payload(definition, version, payload_file)


if __name__ == "__main__":
    main()
