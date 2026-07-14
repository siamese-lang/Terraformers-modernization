import React from 'react';
import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import ConfirmSignUpPage from './components/ConfirmSignUpPage';
import EntryPage from './components/EntryPage';

function ImportBoundary() {
  return (
    <main className="import-boundary">
      <p className="eyebrow">Terraformers frontend import</p>
      <h1>Original Terraformers UI import is in progress</h1>
      <p>
        The original route map uses <code>/</code> for <code>AiChat</code>, <code>/login</code> for <code>EntryPage</code>,
        <code>/confirm-sign-up</code> for <code>ConfirmSignUpPage</code>, and <code>/home</code> for <code>AppLayoutPreview</code>.
      </p>
      <p>
        This first pass imports the original auth/routing/API foundation only. The original <code>AiChat</code>, upload,
        project tree, editor, public project, and comment flows will be imported in the next pass after their assets and
        backend contracts are classified.
      </p>
      <Link className="primary-link" to="/login">Open imported auth route</Link>
    </main>
  );
}

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<ImportBoundary />} />
        <Route path="/login" element={<EntryPage />} />
        <Route path="/confirm-sign-up" element={<ConfirmSignUpPage />} />
      </Routes>
    </Router>
  );
}

export default App;
