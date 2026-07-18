import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from './App';
import { fetchUserAttributes, getCurrentUser, signOut } from 'aws-amplify/auth';

jest.mock('aws-amplify/auth', () => ({
  fetchUserAttributes: jest.fn(),
  getCurrentUser: jest.fn(),
  signOut: jest.fn(),
}));

jest.mock('./components/EntryPage', () => function EntryPage() {
  return <h1>Login page</h1>;
});

jest.mock('./components/ConfirmSignUpPage', () => function ConfirmSignUpPage() {
  return <h1>Confirm sign up</h1>;
});

jest.mock('./pages/GeneratePage', () => function GeneratePage() {
  return <h1>Generate page state</h1>;
});

jest.mock('./pages/MyProjectsPage', () => function MyProjectsPage() {
  return <h1>Private projects state</h1>;
});

jest.mock('./pages/CommunityPage', () => function CommunityPage() {
  return <h1>Community page</h1>;
});

const unauthenticated = () => {
  getCurrentUser.mockRejectedValue({ name: 'UserUnAuthenticatedException' });
};

const authenticated = (attributes = {}) => {
  getCurrentUser.mockResolvedValue({ userId: 'user-1', username: 'testuser' });
  fetchUserAttributes.mockResolvedValue(attributes);
};

const renderAt = (path) => {
  window.history.pushState({}, '', path);
  return render(<App />);
};

describe('routed frontend auth contracts', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.history.pushState({}, '', '/');
  });

  test('guest / redirects to /community and can use community', async () => {
    unauthenticated();
    renderAt('/');

    expect(await screen.findByRole('heading', { name: 'Community page' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/community');
  });

  test('guest private routes redirect to /login', async () => {
    unauthenticated();
    const { unmount } = renderAt('/generate');
    expect(await screen.findByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/login');
    unmount();

    unauthenticated();
    renderAt('/projects');
    expect(await screen.findByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/login');
  });

  test('authenticated / redirects to /generate', async () => {
    authenticated({ email: 'dev@example.com' });
    renderAt('/');

    expect(await screen.findByRole('heading', { name: 'Generate page state' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/generate');
  });

  test('sidebar links point to canonical routes and only current route is active', async () => {
    authenticated({ email: 'dev@example.com' });
    renderAt('/community');

    const generate = await screen.findByRole('link', { name: /새 코드 생성/ });
    const projects = screen.getByRole('link', { name: /내 프로젝트/ });
    const community = screen.getByRole('link', { name: /공개 프로젝트/ });

    expect(generate).toHaveAttribute('href', '/generate');
    expect(projects).toHaveAttribute('href', '/projects');
    expect(community).toHaveAttribute('href', '/community');
    expect(community).toHaveClass('active');
    expect(generate).not.toHaveClass('active');
    expect(projects).not.toHaveClass('active');
  });

  test('account menu prefers nickname, then email local part, then username', async () => {
    authenticated({ nickname: '테라포머', email: 'dev@example.com' });
    const { unmount } = renderAt('/community');
    expect(await screen.findByText('테라포머')).toBeInTheDocument();
    unmount();

    authenticated({ email: 'engineer@example.com' });
    const second = renderAt('/community');
    expect(await screen.findByText('engineer')).toBeInTheDocument();
    second.unmount();

    authenticated({});
    renderAt('/community');
    await waitFor(() => expect(screen.getAllByText('testuser').length).toBeGreaterThan(0));
  });

  test('logout calls Amplify signOut, moves to community, and clears private route access', async () => {
    authenticated({ email: 'dev@example.com' });
    signOut.mockResolvedValue(undefined);
    const view = renderAt('/generate');

    expect(await screen.findByRole('heading', { name: 'Generate page state' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /dev/ }));
    await userEvent.click(screen.getByRole('menuitem', { name: '로그아웃' }));

    await waitFor(() => expect(signOut).toHaveBeenCalledTimes(1));
    expect(await screen.findByRole('heading', { name: 'Community page' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/community');

    await userEvent.click(screen.getByRole('link', { name: /새 코드 생성/ }));
    expect(await screen.findByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Generate page state' })).not.toBeInTheDocument();

    view.unmount();
    unauthenticated();
    renderAt('/projects');
    expect(await screen.findByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Private projects state' })).not.toBeInTheDocument();
  });

  test('auth expiration event turns the session into guest and private route moves to login', async () => {
    authenticated({ email: 'dev@example.com' });
    renderAt('/generate');
    expect(await screen.findByRole('heading', { name: 'Generate page state' })).toBeInTheDocument();

    window.dispatchEvent(new Event('terraformers:auth-expired'));

    expect(await screen.findByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/login');
  });
});
