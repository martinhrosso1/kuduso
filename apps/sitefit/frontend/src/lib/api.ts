/**
 * API client for Kuduso backend
 */

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8081';

export interface RunJobPayload {
  app_id: string;
  definition: string;
  version: string;
  inputs: any;
}

export interface RunJobResponse {
  job_id: string;
  status: string;
  correlation_id: string;
}

export interface JobStatusResponse {
  job_id: string;
  status: 'running' | 'succeeded' | 'failed';
  has_result: boolean;
  created_at?: string;
  correlation_id?: string;
}

export async function runJob(payload: RunJobPayload): Promise<RunJobResponse> {
  const res = await fetch(`${API_BASE_URL}/jobs/run`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`Failed to run job: ${error}`);
  }

  return res.json();
}

export async function pollStatus(jobId: string): Promise<JobStatusResponse> {
  const res = await fetch(`${API_BASE_URL}/jobs/status/${jobId}`);

  if (!res.ok) {
    throw new Error(`Failed to get status: ${res.statusText}`);
  }

  return res.json();
}

export async function getResult(jobId: string): Promise<any> {
  const res = await fetch(`${API_BASE_URL}/jobs/result/${jobId}`);

  if (!res.ok) {
    throw new Error(`Failed to get result: ${res.statusText}`);
  }

  return res.json();
}
