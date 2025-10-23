/**
 * Mock solver - returns deterministic results matching outputs.schema.json
 * This will be replaced with real Rhino.Compute calls in Stage 4
 */

interface MockSolveInputs {
  crs?: string;
  parcel?: any;
  house?: any;
  rotation?: {
    min?: number;
    max?: number;
    step?: number;
  };
  grid_step?: number;
  seed?: number;
}

export async function mockSolve(
  inputs: MockSolveInputs,
  definition: string,
  version: string
): Promise<any> {
  // Simulate minimal processing delay
  await new Promise(resolve => setTimeout(resolve, 100));

  const seed = inputs.seed ?? 1;
  const crs = inputs.crs || 'EPSG:3857';

  // Deterministic mock result based on seed
  const theta = (seed * 15) % 360;
  const dx = seed % 10;
  const dy = seed % 10;

  const result = {
    results: [
      {
        id: `result-${seed}`,
        transform: {
          rotation: {
            axis: 'z' as const,
            value: theta,
            units: 'deg' as const
          },
          translation: {
            x: dx,
            y: dy,
            z: 0,
            units: 'm' as const
          },
          scale: {
            uniform: 1
          }
        },
        score: 85.5 + (seed % 10),
        metrics: {
          area_m2: 100,
          overlap_pct: 0,
          distance_to_edge_m: 2.5,
          seed,
          mock: true
        },
        tags: ['mock', 'feasible', 'optimal']
      }
    ],
    artifacts: [], // No artifacts in mock mode
    metadata: {
      definition,
      version,
      units: {
        length: 'm',
        angle: 'deg',
        crs
      },
      seed,
      generated_at: new Date().toISOString(),
      engine: {
        name: 'mock',
        version: '0.1.0',
        mode: 'deterministic'
      },
      cache_hit: false,
      warnings: []
    }
  };

  return result;
}
