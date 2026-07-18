import api from './api';
import { fetchAuthSession } from 'aws-amplify/auth';

jest.mock('aws-amplify/auth', () => ({
  fetchAuthSession: jest.fn(),
}));

const token = (value) => ({ toString: () => value });

test('retries a 401 only once with a refreshed token', async () => {
  fetchAuthSession
    .mockResolvedValueOnce({ tokens: { accessToken: token('initial') } })
    .mockResolvedValueOnce({ tokens: { accessToken: token('refreshed') } });
  const adapter = jest.fn();
  adapter
    .mockRejectedValueOnce({ response: { status: 401 }, config: { url: '/api/private', method: 'get', headers: {}, adapter } })
    .mockResolvedValueOnce({ data: { ok: true }, status: 200, statusText: 'OK', headers: {}, config: {} });

  await expect(api.get('/api/private', { adapter })).resolves.toMatchObject({ data: { ok: true } });

  expect(adapter).toHaveBeenCalledTimes(2);
  expect(fetchAuthSession).toHaveBeenCalledTimes(3);
});

test('emits auth expiration when token refresh fails after 401', async () => {
  const listener = jest.fn();
  window.addEventListener('terraformers:auth-expired', listener);
  fetchAuthSession
    .mockResolvedValueOnce({ tokens: { accessToken: token('initial') } })
    .mockResolvedValueOnce({ tokens: {} });
  const adapter = jest.fn();
  adapter.mockRejectedValue({
    response: { status: 401 },
    config: { url: '/api/private', method: 'get', headers: {}, adapter },
  });

  await expect(api.get('/api/private', { adapter })).rejects.toBeTruthy();

  expect(adapter).toHaveBeenCalledTimes(1);
  expect(listener).toHaveBeenCalledTimes(1);
  window.removeEventListener('terraformers:auth-expired', listener);
});

test('emits auth expiration when retry also returns 401', async () => {
  const listener = jest.fn();
  window.addEventListener('terraformers:auth-expired', listener);
  fetchAuthSession
    .mockResolvedValueOnce({ tokens: { accessToken: token('initial') } })
    .mockResolvedValueOnce({ tokens: { accessToken: token('refreshed') } });
  const adapter = jest.fn();
  adapter
    .mockRejectedValueOnce({ response: { status: 401 }, config: { url: '/api/private', method: 'get', headers: {}, adapter } })
    .mockRejectedValueOnce({ response: { status: 401 }, config: { url: '/api/private', method: 'get', headers: {}, _retry: true, adapter } });

  await expect(api.get('/api/private', { adapter })).rejects.toBeTruthy();

  expect(adapter).toHaveBeenCalledTimes(2);
  expect(listener).toHaveBeenCalledTimes(1);
  window.removeEventListener('terraformers:auth-expired', listener);
});
