import { Navigate, useLocation } from 'react-router-dom';
import { useAuthSession } from './AuthSessionContext';

function ProtectedRoute({ children }) {
  const location = useLocation();
  const { status } = useAuthSession();

  if (status === 'checking') {
    return <div className="route-state">로그인 상태를 확인하고 있습니다.</div>;
  }

  if (status !== 'authenticated') {
    return (
      <Navigate
        to="/login"
        replace
        state={{ from: `${location.pathname}${location.search}` }}
      />
    );
  }

  return children;
}

export default ProtectedRoute;
