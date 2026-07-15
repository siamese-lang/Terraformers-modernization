import axios from 'axios';
import { fetchAuthSession } from 'aws-amplify/auth';

const envApiBaseUrl = process.env.REACT_APP_API_BASE_URL?.trim();
const API_BASE_URL = envApiBaseUrl || '';

if (!envApiBaseUrl && process.env.NODE_ENV === 'development') {
  console.info('[api] REACT_APP_API_BASE_URL is not set. Using relative /api paths through CRA proxy.');
}

if (!envApiBaseUrl && process.env.NODE_ENV === 'production') {
  console.warn('[api] REACT_APP_API_BASE_URL is not set. Production requests will use relative paths.');
}

const AUTH_REQUIRED_PATH_PREFIXES = ['/api/'];
const AUTH_OPTIONAL_PATHS = [
  '/api/login',
  '/api/register',
  '/api/upload',
  '/api/analysis/jobs',
  '/api/projects',
  '/api/public-projects',
  '/api/project-tree',
  '/api/project-tree/',
  '/api/getProjectInfrastructureImage/',
  '/api/getProjectComments/',
  '/api/addProjectComment',
];

export const isAuthRequiredRequest = (config = {}) => {
  const method = String(config.method || 'get').toLowerCase();
  const rawUrl = config.url || '';
  const path = rawUrl.startsWith('http') ? new URL(rawUrl).pathname : rawUrl;

  if (!AUTH_REQUIRED_PATH_PREFIXES.some((prefix) => path.startsWith(prefix))) {
    return false;
  }

  if (AUTH_OPTIONAL_PATHS.some((allowedPath) => path.startsWith(allowedPath))) {
    return false;
  }

  return method !== 'options';
};

const api = axios.create({
  baseURL: API_BASE_URL,
});

const getToken = async (tokenType) => {
  try {
    const session = await fetchAuthSession();
    if (tokenType === 'access') {
      return session.tokens?.accessToken?.toString() || null;
    }
    if (tokenType === 'id') {
      return session.tokens?.idToken?.toString() || null;
    }
  } catch (sessionError) {
    console.error('[api] Failed to fetch auth session. Check Cognito configuration and sign-in state.', {
      name: sessionError?.name,
      message: sessionError?.message,
    });
  }
  return null;
};

api.interceptors.request.use(async (config) => {
  const tokenType = config.tokenType || 'access';
  const token = await getToken(tokenType);

  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
    return config;
  }

  if (isAuthRequiredRequest(config)) {
    console.warn('[api] Missing auth token for authenticated API request.', {
      method: String(config.method || 'get').toUpperCase(),
      url: config.url,
    });
    if (typeof window !== 'undefined' && window.location.pathname !== '/login') {
      window.location.assign('/login');
    }
  }

  return config;
});

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    if (!error.response) {
      console.error('[api] Network/CORS/proxy error (no response).', {
        message: error?.message,
        url: originalRequest?.url,
      });
      return Promise.reject(error);
    }

    if (error.response.status === 401 && originalRequest && !originalRequest._retry) {
      originalRequest._retry = true;
      const tokenType = originalRequest.tokenType || 'access';
      const token = await getToken(tokenType);

      if (token) {
        originalRequest.headers.Authorization = `Bearer ${token}`;
        return api(originalRequest);
      }
    }

    return Promise.reject(error);
  }
);

export default api;
