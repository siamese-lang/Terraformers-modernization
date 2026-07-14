import axios from 'axios';

const configuredBaseUrl = process.env.REACT_APP_API_BASE_URL?.trim();

const api = axios.create({
  baseURL: configuredBaseUrl || '',
  headers: {
    Accept: 'application/json',
  },
});

export async function createAnalysisJob({ projectId, sourceBucket, sourceKey }) {
  const correlationId = `browser-smoke-${Date.now()}`;
  const response = await api.post('/api/analysis/jobs', {
    projectId,
    sourceBucket,
    sourceKey,
    correlationId,
  });
  return response.data;
}

export async function getAnalysisJob(id) {
  const response = await api.get(`/api/analysis/jobs/${encodeURIComponent(id)}`);
  return response.data;
}

export default api;
