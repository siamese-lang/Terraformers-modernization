import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import MyProjectsPage from './MyProjectsPage';
import api from '../utils/api';

jest.mock('../utils/api', () => ({
  get: jest.fn(),
  delete: jest.fn(),
}));

beforeEach(() => {
  jest.clearAllMocks();
  window.confirm = jest.fn(() => true);
  api.get.mockResolvedValueOnce({ data: [{ projectId: 42, displayName: 'Delete me', analysisStatus: 'SUCCEEDED' }] })
    .mockResolvedValueOnce({ data: [] });
  api.delete.mockResolvedValue({});
});

test('confirms deletion and refreshes the route-based project list', async () => {
  render(<MemoryRouter><MyProjectsPage /></MemoryRouter>);
  await screen.findByText('Delete me');
  expect(screen.getByRole('link', { name: '상세 보기' })).toHaveAttribute('href', '/projects/42');

  await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

  await waitFor(() => expect(api.delete).toHaveBeenCalledWith('/api/projects/42'));
  await waitFor(() => expect(screen.getByText('아직 프로젝트가 없습니다.')).toBeInTheDocument());
});
