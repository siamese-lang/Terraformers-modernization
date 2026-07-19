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
