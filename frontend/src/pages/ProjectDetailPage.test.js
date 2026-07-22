import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ProjectDetailPage from './ProjectDetailPage';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ get: jest.fn(), patch: jest.fn(), delete: jest.fn() }));
const renderPage = () => render(<MemoryRouter initialEntries={['/projects/7']}><Routes><Route path="/projects/:projectId" element={<ProjectDetailPage />} /></Routes></MemoryRouter>);

beforeEach(() => { jest.useFakeTimers(); jest.clearAllMocks(); jest.spyOn(window, 'confirm').mockReturnValue(true); global.URL.createObjectURL = jest.fn(() => 'blob:source'); global.URL.revokeObjectURL = jest.fn(); });
afterEach(() => { window.confirm.mockRestore(); jest.useRealTimers(); });

test('polls metadata only until success, then loads each job-linked artifact once', async () => {
  let metadataCalls = 0;
  api.get.mockImplementation((url) => {
    if (url === '/api/projects/7') { metadataCalls += 1; return Promise.resolve({ data: { displayName: 'Diagram', analysisStatus: metadataCalls === 1 ? 'PENDING' : 'SUCCEEDED', sourceFileId: 10, resultFileId: metadataCalls === 1 ? null : 20 } }); }
    if (url.endsWith('source-image')) return Promise.resolve({ data: new Blob(['image']) });
    return Promise.resolve({ data: { content: 'resource "aws_s3_bucket" "x" {}' } });
  });
  renderPage();
  await screen.findByText(/대기 중/);
  expect(api.get).toHaveBeenCalledWith('/api/projects/7/source-image', { responseType: 'blob' });
  jest.advanceTimersByTime(2000);
  await waitFor(() => expect(screen.getByText(/aws_s3_bucket/)).toBeInTheDocument());
  expect(api.get.mock.calls.filter(([url]) => url === '/api/projects/7/source-image')).toHaveLength(1);
  expect(api.get.mock.calls.filter(([url]) => url === '/api/projects/7/terraform/main.tf')).toHaveLength(1);
});

test('shows failure without requesting Terraform and cleans object URLs on unmount', async () => {
  api.get.mockResolvedValueOnce({ data: { displayName: 'Diagram', analysisStatus: 'FAILED', sourceFileId: 10, resultFileId: null, failureReason: 'Bedrock request failed' } })
    .mockResolvedValueOnce({ data: new Blob(['image']) });
  const { unmount } = renderPage();
  await screen.findByText('Bedrock request failed');
  expect(api.get).not.toHaveBeenCalledWith('/api/projects/7/terraform/main.tf');
  unmount();
  expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:source');
});

test('shows running guidance and Bedrock waiting message after 30 seconds without fake progress', async () => {
  api.get.mockResolvedValue({ data: { displayName: 'Diagram', analysisStatus: 'RUNNING', sourceFileId: null, resultFileId: null } });
  renderPage();
  await screen.findByText('AI가 아키텍처를 분석하고 있습니다.');
  expect(screen.getByText('이미지 복잡도에 따라 1~3분 정도 걸릴 수 있습니다.')).toBeInTheDocument();
  expect(screen.getByText('다른 페이지로 이동해도 분석은 계속되며 내 프로젝트에서 다시 확인할 수 있습니다.')).toBeInTheDocument();
  expect(screen.queryByText('Bedrock 모델의 응답을 기다리고 있습니다.')).not.toBeInTheDocument();
  jest.advanceTimersByTime(30000);
  expect(await screen.findByText('Bedrock 모델의 응답을 기다리고 있습니다.')).toBeInTheDocument();
  expect(screen.queryByText(/%/)).not.toBeInTheDocument();
});

test('shows safe failure reason and link to start a new analysis', async () => {
  api.get.mockResolvedValue({ data: { displayName: 'Diagram', analysisStatus: 'FAILED', sourceFileId: null, resultFileId: null, failureReason: 'AI 모델의 응답 시간이 초과되었습니다. 잠시 후 새 분석을 시작해 주세요.' } });
  renderPage();
  expect(await screen.findByText('AI 모델의 응답 시간이 초과되었습니다. 잠시 후 새 분석을 시작해 주세요.')).toBeInTheDocument();
  expect(screen.getByRole('link', { name: '새 분석 시작' })).toHaveAttribute('href', '/generate');
});

const project = (visibility) => ({ displayName: 'Diagram', visibility, analysisStatus: 'SUCCEEDED', sourceFileId: null, resultFileId: null });

test('shows a private project visibility and its publish control', async () => {
  api.get.mockResolvedValue({ data: project('PRIVATE') });

  renderPage();

  expect(await screen.findByText('공개 범위: PRIVATE')).toBeInTheDocument();
  expect(screen.getByText('소유자만 조회할 수 있습니다.')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: '공개하기' })).toBeInTheDocument();
});

test('publishes a private project and updates the displayed project from the PATCH response', async () => {
  api.get.mockResolvedValue({ data: project('PRIVATE') });
  api.patch.mockResolvedValue({ data: project('PUBLIC') });
  renderPage();

  fireEvent.click(await screen.findByRole('button', { name: '공개하기' }));

  await waitFor(() => expect(api.patch).toHaveBeenCalledWith('/api/projects/7/visibility', { visibility: 'PUBLIC' }));
  expect(window.confirm).toHaveBeenCalled();
  expect(await screen.findByText('공개 범위: PUBLIC')).toBeInTheDocument();
  expect(screen.getByText('커뮤니티에서 누구나 조회할 수 있습니다.')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: '비공개로 전환' })).toBeInTheDocument();
  expect(api.get.mock.calls.filter(([url]) => url === '/api/projects/7')).toHaveLength(1);
});

test('requests a private visibility change for a public project', async () => {
  api.get.mockResolvedValue({ data: project('PUBLIC') });
  api.patch.mockResolvedValue({ data: project('PRIVATE') });
  renderPage();

  fireEvent.click(await screen.findByRole('button', { name: '비공개로 전환' }));

  await waitFor(() => expect(api.patch).toHaveBeenCalledWith('/api/projects/7/visibility', { visibility: 'PRIVATE' }));
  expect(await screen.findByText('공개 범위: PRIVATE')).toBeInTheDocument();
});

test('disables the visibility button while the PATCH request is pending', async () => {
  api.get.mockResolvedValue({ data: project('PRIVATE') });
  let resolvePatch;
  api.patch.mockImplementation(() => new Promise((resolve) => { resolvePatch = resolve; }));
  renderPage();

  fireEvent.click(await screen.findByRole('button', { name: '공개하기' }));

  expect(screen.getByRole('button', { name: '변경 중...' })).toBeDisabled();
  resolvePatch({ data: project('PUBLIC') });
  expect(await screen.findByRole('button', { name: '비공개로 전환' })).toBeInTheDocument();
});

test('shows a visibility error and keeps the existing visibility when PATCH fails', async () => {
  api.get.mockResolvedValue({ data: project('PUBLIC') });
  api.patch.mockRejectedValue({ response: { data: '공개 범위를 변경할 권한이 없습니다.' } });
  renderPage();

  fireEvent.click(await screen.findByRole('button', { name: '비공개로 전환' }));

  expect(await screen.findByText('공개 범위 변경 실패: 공개 범위를 변경할 권한이 없습니다.')).toBeInTheDocument();
  expect(screen.getByText('공개 범위: PUBLIC')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: '비공개로 전환' })).toBeInTheDocument();
});

test('deletes from the detail danger zone and replaces the detail route', async () => {
  api.get.mockResolvedValue({ data: project('PRIVATE') });
  api.delete.mockResolvedValue({});
  render(<MemoryRouter initialEntries={['/projects/7']}><Routes><Route path="/projects/:projectId" element={<ProjectDetailPage />} /><Route path="/projects" element={<p>목록으로 이동</p>} /></Routes></MemoryRouter>);
  fireEvent.click(await screen.findByRole('button', { name: 'Diagram 프로젝트 삭제' }));
  await waitFor(() => expect(api.delete).toHaveBeenCalledWith('/api/projects/7'));
  expect(await screen.findByText('목록으로 이동')).toBeInTheDocument();
});

test('keeps detail content and separates deletion failure from visibility errors', async () => {
  api.get.mockResolvedValue({ data: project('PUBLIC') });
  api.delete.mockRejectedValue(new Error('internal details'));
  renderPage();
  fireEvent.click(await screen.findByRole('button', { name: 'Diagram 프로젝트 삭제' }));
  expect(await screen.findByText('프로젝트 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.')).toBeInTheDocument();
  expect(screen.getByText('공개 범위: PUBLIC')).toBeInTheDocument();
});
