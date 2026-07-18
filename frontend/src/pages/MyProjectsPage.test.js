import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import MyProjectsPage from './MyProjectsPage';
import api from '../utils/api';

jest.mock('../components/ProjectTreeReadOnly', () => function ProjectTreeReadOnly({ selectedProjectId }) {
  return <div data-testid="tree">selected={selectedProjectId || ''}</div>;
});

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

test('confirms deletion, calls delete API, refreshes list, and clears selected project', async () => {
  render(<MyProjectsPage />);
  await screen.findByText('Delete me');
  await userEvent.click(screen.getByRole('button', { name: 'Delete me' }));
  expect(screen.getByTestId('tree')).toHaveTextContent('selected=42');

  await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

  await waitFor(() => expect(api.delete).toHaveBeenCalledWith('/api/projects/42'));
  await waitFor(() => expect(screen.getByText('아직 프로젝트가 없습니다.')).toBeInTheDocument());
  expect(screen.getByTestId('tree')).toHaveTextContent('selected=');
});
