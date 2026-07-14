import React, { useState } from 'react';
import { confirmSignUp } from 'aws-amplify/auth';
import { useNavigate } from 'react-router-dom';

function ConfirmSignUpPage() {
  const [confirmationCode, setConfirmationCode] = useState('');
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (event) => {
    event.preventDefault();
    setLoading(true);
    setError('');

    try {
      await confirmSignUp({
        username: email,
        confirmationCode,
      });
      navigate('/login');
    } catch (confirmError) {
      console.error('[auth] Cognito confirmation failed.', {
        name: confirmError?.name,
        message: confirmError?.message,
      });
      setError(`Error confirming account: ${confirmError.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <section id="entry-page">
      <form onSubmit={handleSubmit}>
        <h2>Confirm Your Account</h2>
        <fieldset>
          <legend>Email Confirmation</legend>
          <label htmlFor="email">Email</label>
          <input
            type="email"
            id="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
          <label htmlFor="confirmationCode">Confirmation Code</label>
          <input
            type="text"
            id="confirmationCode"
            value={confirmationCode}
            onChange={(event) => setConfirmationCode(event.target.value)}
            required
          />
        </fieldset>
        <button type="submit" disabled={loading}>{loading ? 'Confirming...' : 'Confirm'}</button>
        <button type="button" onClick={() => navigate('/login')} disabled={loading}>Back to login</button>
        {error && <p className="error">{error}</p>}
      </form>
    </section>
  );
}

export default ConfirmSignUpPage;
