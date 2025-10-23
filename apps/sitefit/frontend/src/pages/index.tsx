import { useState, useEffect } from 'react';
import { runJob, pollStatus, getResult } from '../lib/api';
import type { RunJobPayload, JobStatusResponse } from '../lib/api';

export default function Home() {
  const [jobId, setJobId] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Form state
  const [crs, setCrs] = useState('EPSG:5514');
  const [seed, setSeed] = useState('42');

  async function handleRun() {
    setLoading(true);
    setError(null);
    setResult(null);
    setJobId(null);
    setStatus(null);

    try {
      const payload: RunJobPayload = {
        app_id: 'sitefit',
        definition: 'sitefit',
        version: '1.0.0',
        inputs: {
          crs,
          parcel: {
            coordinates: [
              [0, 0],
              [20, 0],
              [20, 30],
              [0, 30],
              [0, 0]
            ]
          },
          house: {
            coordinates: [
              [0, 0],
              [10, 0],
              [10, 8],
              [0, 8],
              [0, 0]
            ]
          },
          seed: parseInt(seed, 10)
        }
      };

      const response = await runJob(payload);
      setJobId(response.job_id);
      setStatus(response.status);
      
      // If already succeeded (sync mode in Stage 1), fetch result immediately
      if (response.status === 'succeeded') {
        const resultData = await getResult(response.job_id);
        setResult(resultData);
        setLoading(false);
      }
    } catch (err: any) {
      setError(err.message);
      setLoading(false);
    }
  }

  // Poll for status when job is running
  useEffect(() => {
    if (!jobId || status === 'succeeded' || status === 'failed') {
      return;
    }

    const interval = setInterval(async () => {
      try {
        const statusData = await pollStatus(jobId);
        setStatus(statusData.status);

        if (statusData.status === 'succeeded') {
          const resultData = await getResult(jobId);
          setResult(resultData);
          setLoading(false);
          clearInterval(interval);
        } else if (statusData.status === 'failed') {
          setError('Job failed');
          setLoading(false);
          clearInterval(interval);
        }
      } catch (err: any) {
        setError(err.message);
        setLoading(false);
        clearInterval(interval);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [jobId, status]);

  return (
    <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '48px 24px' }}>
      <header style={{ marginBottom: '48px' }}>
        <h1 style={{ fontSize: '32px', fontWeight: 'bold', marginBottom: '8px' }}>
          Kuduso SiteFit
        </h1>
        <p style={{ color: '#666' }}>
          Stage 1: Mocked Compute Loop
        </p>
      </header>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
        {/* Input Form */}
        <div>
          <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '16px' }}>
            Input Parameters
          </h2>
          
          <div style={{ 
            border: '1px solid #e5e7eb', 
            borderRadius: '8px', 
            padding: '24px',
            backgroundColor: '#f9fafb'
          }}>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'block', marginBottom: '8px', fontWeight: '500' }}>
                CRS (Coordinate Reference System)
              </label>
              <input
                type="text"
                value={crs}
                onChange={(e) => setCrs(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  border: '1px solid #d1d5db',
                  borderRadius: '4px'
                }}
                placeholder="EPSG:5514"
              />
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label style={{ display: 'block', marginBottom: '8px', fontWeight: '500' }}>
                Random Seed
              </label>
              <input
                type="number"
                value={seed}
                onChange={(e) => setSeed(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  border: '1px solid #d1d5db',
                  borderRadius: '4px'
                }}
                placeholder="42"
              />
            </div>

            <div style={{ 
              marginBottom: '24px',
              padding: '12px',
              backgroundColor: '#fff',
              borderRadius: '4px',
              fontSize: '14px'
            }}>
              <p style={{ marginBottom: '8px', color: '#6b7280' }}>
                <strong>Parcel:</strong> 20m × 30m rectangle
              </p>
              <p style={{ color: '#6b7280' }}>
                <strong>House:</strong> 10m × 8m rectangle
              </p>
            </div>

            <button
              onClick={handleRun}
              disabled={loading}
              style={{
                width: '100%',
                padding: '12px 24px',
                backgroundColor: loading ? '#9ca3af' : '#3b82f6',
                color: 'white',
                border: 'none',
                borderRadius: '6px',
                fontSize: '16px',
                fontWeight: '500',
                cursor: loading ? 'not-allowed' : 'pointer',
                transition: 'background-color 0.2s'
              }}
            >
              {loading ? 'Running...' : 'Run Placement'}
            </button>
          </div>
        </div>

        {/* Results */}
        <div>
          <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '16px' }}>
            Results
          </h2>

          <div style={{ 
            border: '1px solid #e5e7eb', 
            borderRadius: '8px', 
            padding: '24px',
            minHeight: '400px'
          }}>
            {/* Status */}
            {jobId && (
              <div style={{ marginBottom: '16px' }}>
                <p style={{ fontSize: '14px', color: '#6b7280', marginBottom: '4px' }}>
                  Job ID
                </p>
                <p style={{ fontSize: '12px', fontFamily: 'monospace', color: '#374151' }}>
                  {jobId}
                </p>
              </div>
            )}

            {status && (
              <div style={{ marginBottom: '16px' }}>
                <p style={{ fontSize: '14px', color: '#6b7280', marginBottom: '4px' }}>
                  Status
                </p>
                <span style={{
                  display: 'inline-block',
                  padding: '4px 12px',
                  borderRadius: '12px',
                  fontSize: '14px',
                  fontWeight: '500',
                  backgroundColor: 
                    status === 'succeeded' ? '#d1fae5' :
                    status === 'failed' ? '#fee2e2' :
                    '#fef3c7',
                  color:
                    status === 'succeeded' ? '#065f46' :
                    status === 'failed' ? '#991b1b' :
                    '#92400e'
                }}>
                  {status}
                </span>
              </div>
            )}

            {/* Error */}
            {error && (
              <div style={{ 
                padding: '12px', 
                backgroundColor: '#fee2e2', 
                border: '1px solid #fecaca',
                borderRadius: '6px',
                marginBottom: '16px'
              }}>
                <p style={{ color: '#991b1b', fontSize: '14px' }}>
                  <strong>Error:</strong> {error}
                </p>
              </div>
            )}

            {/* Result */}
            {result && (
              <div>
                <h3 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '12px' }}>
                  Placement Result
                </h3>
                
                {result.results && result.results.length > 0 && (
                  <div style={{ marginBottom: '16px' }}>
                    {result.results.map((r: any, idx: number) => (
                      <div 
                        key={r.id || idx}
                        style={{
                          padding: '16px',
                          backgroundColor: '#f3f4f6',
                          borderRadius: '6px',
                          marginBottom: '12px'
                        }}
                      >
                        <p style={{ fontSize: '14px', marginBottom: '8px' }}>
                          <strong>Score:</strong> {r.score?.toFixed(1)}
                        </p>
                        
                        {r.transform?.rotation && (
                          <p style={{ fontSize: '14px', marginBottom: '8px' }}>
                            <strong>Rotation:</strong> {r.transform.rotation.value}° 
                            ({r.transform.rotation.axis}-axis)
                          </p>
                        )}
                        
                        {r.transform?.translation && (
                          <p style={{ fontSize: '14px', marginBottom: '8px' }}>
                            <strong>Translation:</strong> ({r.transform.translation.x}, {r.transform.translation.y})m
                          </p>
                        )}

                        {r.metrics && (
                          <div style={{ marginTop: '12px', fontSize: '13px' }}>
                            <strong style={{ display: 'block', marginBottom: '4px' }}>
                              Metrics:
                            </strong>
                            <pre style={{ 
                              backgroundColor: '#fff',
                              padding: '8px',
                              borderRadius: '4px',
                              overflow: 'auto',
                              fontSize: '12px'
                            }}>
                              {JSON.stringify(r.metrics, null, 2)}
                            </pre>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}

                <details style={{ marginTop: '16px' }}>
                  <summary style={{ cursor: 'pointer', fontSize: '14px', fontWeight: '500' }}>
                    View Full JSON
                  </summary>
                  <pre style={{ 
                    marginTop: '12px',
                    padding: '12px', 
                    backgroundColor: '#f9fafb',
                    border: '1px solid #e5e7eb',
                    borderRadius: '6px',
                    overflow: 'auto',
                    fontSize: '12px',
                    maxHeight: '400px'
                  }}>
                    {JSON.stringify(result, null, 2)}
                  </pre>
                </details>
              </div>
            )}

            {/* Idle state */}
            {!loading && !result && !error && (
              <p style={{ color: '#9ca3af', textAlign: 'center', marginTop: '60px' }}>
                Click "Run Placement" to start
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
