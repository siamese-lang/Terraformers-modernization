import { useEffect, useRef, useState } from 'react';
import {
  NavLink,
  Outlet,
  useNavigate,
} from 'react-router-dom';
import { useAuthSession } from '../auth/AuthSessionContext';

const navigationItems = [
  {
    to: '/generate',
    label: '새 코드 생성',
    description: '아키텍처 이미지 분석',
  },
  {
    to: '/projects',
    label: '내 프로젝트',
    description: '프로젝트와 Terraform 파일',
  },
  {
    to: '/community',
    label: '공개 프로젝트',
    description: '공개 코드와 댓글',
  },
];

function userDisplayName(user) {
  if (user?.nickname) {
    return user.nickname;
  }
  if (user?.email) {
    return user.email.split('@')[0];
  }
  return user?.username || '사용자';
}

function AppShell() {
  const { status, user, error, logout } = useAuthSession();
  const [accountOpen, setAccountOpen] = useState(false);
  const [logoutError, setLogoutError] = useState('');
  const accountRef = useRef(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!accountOpen) {
      return undefined;
    }

    const closeOnOutsideClick = (event) => {
      if (!accountRef.current?.contains(event.target)) {
        setAccountOpen(false);
      }
    };

    const closeOnEscape = (event) => {
      if (event.key === 'Escape') {
        setAccountOpen(false);
      }
    };

    document.addEventListener('mousedown', closeOnOutsideClick);
    document.addEventListener('keydown', closeOnEscape);

    return () => {
      document.removeEventListener('mousedown', closeOnOutsideClick);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [accountOpen]);

  const handleLogout = async () => {
    setLogoutError('');

    try {
      await logout();
      setAccountOpen(false);
      navigate('/community', { replace: true });
    } catch (signOutError) {
      setLogoutError(signOutError?.message || '로그아웃하지 못했습니다.');
    }
  };

  const displayName = userDisplayName(user);
  const initial = displayName.slice(0, 1).toUpperCase() || 'U';

  return (
    <div className="app-shell">
      <aside className="app-sidebar">
        <div className="app-brand">
          <div className="app-brand-mark" aria-hidden="true">T</div>
          <div>
            <strong>Terraformers</strong>
            <span>Architecture to Terraform</span>
          </div>
        </div>

        <nav className="app-navigation" aria-label="주요 메뉴">
          {navigationItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (
                isActive ? 'app-navigation-link active' : 'app-navigation-link'
              )}
            >
              <strong>{item.label}</strong>
              <span>{item.description}</span>
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-account" ref={accountRef}>
          {status === 'checking' && (
            <p className="sidebar-account-status">사용자 확인 중</p>
          )}

          {status === 'guest' && (
            <NavLink className="sidebar-login-link" to="/login">
              로그인
            </NavLink>
          )}

          {status === 'authenticated' && user && (
            <>
              <button
                type="button"
                className="sidebar-account-button"
                aria-haspopup="menu"
                aria-expanded={accountOpen}
                onClick={() => setAccountOpen((open) => !open)}
              >
                <span className="sidebar-account-avatar" aria-hidden="true">
                  {initial}
                </span>
                <span className="sidebar-account-summary">
                  <strong>{displayName}</strong>
                  <span>{user.email || user.username}</span>
                </span>
                <span aria-hidden="true">⌄</span>
              </button>

              {accountOpen && (
                <div className="sidebar-account-menu" role="menu">
                  <div className="sidebar-account-identity">
                    <strong>{displayName}</strong>
                    <span>{user.email || user.username}</span>
                  </div>
                  <button
                    type="button"
                    role="menuitem"
                    className="sidebar-logout-button"
                    onClick={handleLogout}
                  >
                    로그아웃
                  </button>
                  {(logoutError || error) && (
                    <p className="sidebar-account-error">
                      {logoutError || error}
                    </p>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      </aside>

      <main className="app-main">
        <Outlet />
      </main>
    </div>
  );
}

export default AppShell;
