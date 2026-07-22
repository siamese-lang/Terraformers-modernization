import { render, screen, waitFor } from '@testing-library/react';
import { AuthSessionProvider, useAuthSession } from './AuthSessionContext';
import api from '../utils/api';
import { fetchUserAttributes, getCurrentUser } from 'aws-amplify/auth';

jest.mock('aws-amplify/auth', () => ({
  fetchUserAttributes: jest.fn(), getCurrentUser: jest.fn(), signOut: jest.fn(),
}));
jest.mock('../utils/api', () => ({ patch: jest.fn() }));

function SessionState() {
  const { status } = useAuthSession();
  return <span>{status}</span>;
}

beforeEach(() => {
  jest.clearAllMocks();
  getCurrentUser.mockResolvedValue({ userId: 'user-1', username: 'user' });
  fetchUserAttributes.mockResolvedValue({ nickname: 'Terraformer' });
});

test('syncs a nonblank Cognito nickname after authentication', async () => {
  api.patch.mockResolvedValue({});
  render(<AuthSessionProvider><SessionState /></AuthSessionProvider>);
  expect(await screen.findByText('authenticated')).toBeInTheDocument();
  expect(api.patch).toHaveBeenCalledWith('/api/users/me/display-name', { displayName: 'Terraformer' });
});

test('stays authenticated when nickname synchronization fails', async () => {
  api.patch.mockRejectedValue(new Error('profile sync failed'));
  render(<AuthSessionProvider><SessionState /></AuthSessionProvider>);
  await waitFor(() => expect(api.patch).toHaveBeenCalled());
  expect(screen.getByText('authenticated')).toBeInTheDocument();
});
