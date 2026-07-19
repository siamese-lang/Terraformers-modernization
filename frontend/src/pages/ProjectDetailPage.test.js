import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ProjectDetailPage from './ProjectDetailPage';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ get: jest.fn() }));
const renderPage = () => render(<MemoryRouter initialEntries={['/projects/7']}><Routes><Route path="/projects/:projectId" element={<ProjectDetailPage />} /></Routes></MemoryRouter>);

beforeEach(() => { jest.useFakeTimers(); jest.clearAllMocks(); global.URL.createObjectURL = jest.fn(() => 'blob:source'); global.URL.revokeObjectURL = jest.fn(); });
afterEach(() => jest.useRealTimers());

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
