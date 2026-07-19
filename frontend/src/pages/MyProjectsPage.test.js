import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import MyProjectsPage from './MyProjectsPage';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ get: jest.fn(), delete: jest.fn() }));
const project = { projectId: 42, displayName: 'Delete me', analysisStatus: 'SUCCEEDED', visibility: 'PUBLIC', sourceFileId: null, originalFilename: 'diagram.png' };

beforeEach(() => { jest.clearAllMocks(); window.confirm = jest.fn(() => true); api.get.mockResolvedValue({ data: [project] }); api.delete.mockResolvedValue({}); });

test('renders owned projects as cards with status, visibility, and navigation actions', async () => {
  render(<MemoryRouter><MyProjectsPage /></MemoryRouter>);
  expect(await screen.findByText('Delete me')).toBeInTheDocument();
  expect(screen.getByText('완료')).toBeInTheDocument();
  expect(screen.getByText('공개')).toBeInTheDocument();
  expect(screen.getByRole('link', { name: 'Delete me 프로젝트 상세 보기' })).toHaveAttribute('href', '/projects/42');
  expect(screen.getByRole('link', { name: '새 프로젝트 만들기' })).toHaveAttribute('href', '/generate');
});

test('does not call DELETE when deletion is cancelled', async () => {
  window.confirm.mockReturnValue(false);
  render(<MemoryRouter><MyProjectsPage /></MemoryRouter>);
  await screen.findByText('Delete me');
  await userEvent.click(screen.getByRole('button', { name: 'Delete me 프로젝트 삭제' }));
  expect(api.delete).not.toHaveBeenCalled();
});

test('removes a deleted card and shows the empty state without refreshing', async () => {
  render(<MemoryRouter><MyProjectsPage /></MemoryRouter>);
  await screen.findByText('Delete me');
  await userEvent.click(screen.getByRole('button', { name: 'Delete me 프로젝트 삭제' }));
  await waitFor(() => expect(api.delete).toHaveBeenCalledWith('/api/projects/42'));
  expect(await screen.findByText('아직 생성한 프로젝트가 없습니다.')).toBeInTheDocument();
  expect(screen.getByText('0개 프로젝트')).toBeInTheDocument();
});

test('keeps the card and presents a safe error when deletion fails', async () => {
  api.delete.mockRejectedValue({ response: { data: 'internal details' } });
  render(<MemoryRouter><MyProjectsPage /></MemoryRouter>);
  await screen.findByText('Delete me');
  await userEvent.click(screen.getByRole('button', { name: 'Delete me 프로젝트 삭제' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('프로젝트 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.');
  expect(screen.getByText('Delete me')).toBeInTheDocument();
});
