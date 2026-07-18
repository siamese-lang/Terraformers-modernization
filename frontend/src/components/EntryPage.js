import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { signUp, signIn, resetPassword, fetchAuthSession } from 'aws-amplify/auth';
import { useAuthSession } from '../auth/AuthSessionContext';
import '../styles/login.css';

function EntryPage() {
  const [currentView, setCurrentView] = useState('logIn');
  const [formData, setFormData] = useState({ nickname: '', email: '', username: '', password: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const navigate = useNavigate();
  const { refresh } = useAuthSession();

  const changeView = (view) => {
    setCurrentView(view);
    setError('');
  };

  const handleInputChange = (event) => {
    setFormData({ ...formData, [event.target.id]: event.target.value });
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError('');

    try {
      if (currentView === 'signUp') {
        await signUp({
          username: formData.email,
          password: formData.password,
          options: {
            userAttributes: {
              email: formData.email,
              nickname: formData.nickname,
            },
          },
        });
        navigate('/confirm-sign-up');
      } else if (currentView === 'logIn') {
        await signIn({
          username: formData.username,
          password: formData.password,
        });
        const session = await fetchAuthSession();
        const token = session.tokens ? session.tokens.accessToken : null;
        if (token !== null) {
          await refresh();
          navigate('/generate', { replace: true });
        } else {
          setError('Operation failed: missing access token after sign-in. Please check Cognito app client configuration.');
        }
      } else if (currentView === 'PWReset') {
        await resetPassword({ username: formData.email });
        changeView('logIn');
      }
    } catch (authError) {
      console.error('[auth] Cognito sign-up/sign-in failed. Check browser auth configuration.', {
        name: authError?.name,
        message: authError?.message,
      });
      setError(`Operation failed: ${authError.message}`);
    } finally {
      setLoading(false);
    }
  };

  const renderView = () => {
    switch (currentView) {
      case 'signUp':
        return (
          <form onSubmit={handleSubmit}>
            <h2>Sign Up</h2>
            <fieldset>
              <legend>Create Account</legend>
              <label htmlFor="nickname">Nickname</label>
              <input type="text" id="nickname" value={formData.nickname} onChange={handleInputChange} required />
              <label htmlFor="email">Email</label>
              <input type="email" id="email" value={formData.email} onChange={handleInputChange} required />
              <label htmlFor="password">Password</label>
              <input type="password" id="password" value={formData.password} onChange={handleInputChange} required />
            </fieldset>
            <button type="submit" disabled={loading}>{loading ? 'Submitting...' : 'Submit'}</button>
            <button type="button" onClick={() => changeView('logIn')} disabled={loading}>Have an account?</button>
            {error && <p className="error">{error}</p>}
          </form>
        );
      case 'logIn':
        return (
          <form onSubmit={handleSubmit}>
            <h2>Welcome Back</h2>
            <fieldset>
              <legend>Log In</legend>
              <label htmlFor="username">Email</label>
              <input type="text" id="username" value={formData.username} onChange={handleInputChange} required />
              <label htmlFor="password">Password</label>
              <input type="password" id="password" value={formData.password} onChange={handleInputChange} required />
              <button type="button" className="link-button" onClick={() => changeView('PWReset')}>Forgot Password?</button>
            </fieldset>
            <button type="submit" disabled={loading}>{loading ? 'Logging in...' : 'Login'}</button>
            <button type="button" onClick={() => changeView('signUp')} disabled={loading}>Create an Account</button>
            {error && <p className="error">{error}</p>}
          </form>
        );
      case 'PWReset':
        return (
          <form onSubmit={handleSubmit}>
            <h2>Reset Password</h2>
            <fieldset>
              <legend>Password Reset</legend>
              <p>A reset link will be sent to your inbox.</p>
              <label htmlFor="email">Email</label>
              <input type="email" id="email" value={formData.email} onChange={handleInputChange} required />
            </fieldset>
            <button type="submit" disabled={loading}>{loading ? 'Sending...' : 'Send Reset Link'}</button>
            <button type="button" onClick={() => changeView('logIn')} disabled={loading}>Go Back</button>
            {error && <p className="error">{error}</p>}
          </form>
        );
      default:
        return null;
    }
  };

  return <section id="entry-page">{renderView()}</section>;
}

export default EntryPage;
