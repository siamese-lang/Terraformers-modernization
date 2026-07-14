import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import AiChat from './components/AiChat';
import ConfirmSignUpPage from './components/ConfirmSignUpPage';
import EntryPage from './components/EntryPage';

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<AiChat />} />
        <Route path="/login" element={<EntryPage />} />
        <Route path="/confirm-sign-up" element={<ConfirmSignUpPage />} />
      </Routes>
    </Router>
  );
}

export default App;
