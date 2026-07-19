import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import {
  fetchUserAttributes,
  getCurrentUser,
  signOut,
} from 'aws-amplify/auth';
import api from '../utils/api';

const AuthSessionContext = createContext(undefined);

function normalizeUser(currentUser, attributes = {}) {
  return {
    userId: currentUser.userId,
    username: currentUser.username,
    email: attributes.email || '',
    nickname: attributes.nickname || '',
  };
}

export function AuthSessionProvider({ children }) {
  const [status, setStatus] = useState('checking');
  const [user, setUser] = useState(null);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    setStatus('checking');
    setError('');

    try {
      const currentUser = await getCurrentUser();
      const attributes = await fetchUserAttributes();

      const normalizedUser = normalizeUser(currentUser, attributes);
      setUser(normalizedUser);
      setStatus('authenticated');
      if (normalizedUser.nickname.trim()) {
        api.patch('/api/users/me/display-name', { displayName: normalizedUser.nickname }).catch(() => {
          // Profile synchronization is intentionally best-effort and must not affect login.
        });
      }
      return true;
    } catch (authError) {
      setUser(null);
      setStatus('guest');

      const expectedGuestErrors = new Set([
        'UserUnAuthenticatedException',
        'NotAuthorizedException',
      ]);

      if (!expectedGuestErrors.has(authError?.name)) {
        console.error('[auth] Failed to resolve the current Cognito user.', {
          name: authError?.name,
          message: authError?.message,
        });
        setError('로그인 상태를 확인하지 못했습니다.');
      }

      return false;
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    const handleAuthExpired = () => {
      setError('로그인 세션이 만료되었습니다. 다시 로그인해 주세요.');
      setUser(null);
      setStatus('guest');
    };

    window.addEventListener('terraformers:auth-expired', handleAuthExpired);
    return () => {
      window.removeEventListener('terraformers:auth-expired', handleAuthExpired);
    };
  }, []);

  const logout = useCallback(async () => {
    setError('');

    try {
      await signOut();
      setUser(null);
      setStatus('guest');
    } catch (signOutError) {
      console.error('[auth] Cognito sign-out failed.', {
        name: signOutError?.name,
        message: signOutError?.message,
      });
      setError('로그아웃하지 못했습니다. 다시 시도해 주세요.');
      throw signOutError;
    }
  }, []);

  const value = useMemo(() => ({
    status,
    user,
    error,
    refresh,
    logout,
    isAuthenticated: status === 'authenticated',
  }), [status, user, error, refresh, logout]);

  return (
    <AuthSessionContext.Provider value={value}>
      {children}
    </AuthSessionContext.Provider>
  );
}

export function useAuthSession() {
  const context = useContext(AuthSessionContext);

  if (!context) {
    throw new Error('useAuthSession must be used inside AuthSessionProvider.');
  }

  return context;
}
