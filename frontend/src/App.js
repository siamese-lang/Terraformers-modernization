import React from 'react';
import {
  BrowserRouter as Router,
  Navigate,
  Route,
  Routes,
} from 'react-router-dom';
import AppShell from './app/AppShell';
import { AuthSessionProvider, useAuthSession } from './auth/AuthSessionContext';
import ProtectedRoute from './auth/ProtectedRoute';
import ConfirmSignUpPage from './components/ConfirmSignUpPage';
import EntryPage from './components/EntryPage';
import CommunityPage from './pages/CommunityPage';
import GeneratePage from './pages/GeneratePage';
import MyProjectsPage from './pages/MyProjectsPage';
import ProjectDetailPage from './pages/ProjectDetailPage';

function HomeRedirect() {
  const { status } = useAuthSession();

  if (status === 'checking') {
    return <div className="route-state">로그인 상태를 확인하고 있습니다.</div>;
  }

  return (
    <Navigate
      to={status === 'authenticated' ? '/generate' : '/community'}
      replace
    />
  );
}

function App() {
  return (
    <Router>
      <AuthSessionProvider>
        <Routes>
          <Route path="/login" element={<EntryPage />} />
          <Route path="/confirm-sign-up" element={<ConfirmSignUpPage />} />

          <Route element={<AppShell />}>
            <Route index element={<HomeRedirect />} />
            <Route path="/community" element={<CommunityPage />} />
            <Route
              path="/generate"
              element={(
                <ProtectedRoute>
                  <GeneratePage />
                </ProtectedRoute>
              )}
            />
            <Route
              path="/projects"
              element={(
                <ProtectedRoute>
                  <MyProjectsPage />
                </ProtectedRoute>
              )}
            />
            <Route path="/projects/:projectId" element={<ProjectDetailPage />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AuthSessionProvider>
    </Router>
  );
}

export default App;
