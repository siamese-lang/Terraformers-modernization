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

const PUBLIC_EXACT_PATHS = new Set([
  '/api/login',
  '/api/register',
  '/api/public-projects',
  '/api/projects/public',
]);

const PUBLIC_GET_PATTERNS = [
  /^\/api\/projects\/\d+$/,
  /^\/api\/projects\/\d+\/terraform\/main\.tf$/,
  /^\/api\/projects\/\d+\/comments$/,
  /^\/api\/projects\/\d+\/source-object$/,
  /^\/api\/project-tree\/\d+$/,
  /^\/api\/getProjectInfrastructureImage\/\d+$/,
  /^\/api\/getProjectComments\/\d+$/,
];

const isPublicRequest = (method, path) => {
  if (PUBLIC_EXACT_PATHS.has(path)) {
    return true;
  }
  return method === 'get' && PUBLIC_GET_PATTERNS.some((pattern) => pattern.test(path));
};

export const isAuthRequiredRequest = (config = {}) => {
  const method = String(config.method || 'get').toLowerCase();
  const rawUrl = config.url || '';
  const path = rawUrl.startsWith('http') ? new URL(rawUrl).pathname : rawUrl.split('?')[0];

  if (!path.startsWith('/api/') || method === 'options') {
    return false;
  }

  return !isPublicRequest(method, path);
};

const AUTH_EXPIRED_EVENT = 'terraformers:auth-expired';

export const emitAuthExpired = () => {
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new Event(AUTH_EXPIRED_EVENT));
  }
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

      emitAuthExpired();
    } else if (error.response.status === 401 && originalRequest?._retry) {
      emitAuthExpired();
    }

    return Promise.reject(error);
  }
);

export default api;
