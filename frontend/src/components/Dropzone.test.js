import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Dropzone from './Dropzone';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ post: jest.fn() }));

beforeEach(() => {
  jest.clearAllMocks();
  global.URL.createObjectURL = jest.fn(() => 'blob:preview');
  global.URL.revokeObjectURL = jest.fn();
});

test('creates a new project and immediately hands its id to the detail route', async () => {
  const onUploaded = jest.fn();
  api.post.mockResolvedValue({ data: { projectId: 7, analysisJobId: 'job-1', status: 'PENDING' } });
  render(<Dropzone onUploaded={onUploaded} onError={jest.fn()} />);
  await userEvent.type(screen.getByLabelText(/프로젝트 이름/i), 'New project');
  await userEvent.upload(screen.getByLabelText(/PNG\/JPEG/i), new File(['bytes'], 'diagram.png', { type: 'image/png' }));
  await screen.findByText('diagram.png');
  await userEvent.click(screen.getByRole('button', { name: '분석 시작' }));
  await waitFor(() => expect(onUploaded).toHaveBeenCalledWith(7));
  const formData = api.post.mock.calls[0][1];
  expect(formData.get('projectName')).toBe('New project');
  expect(formData.get('projectId')).toBeNull();
});

test('does not render an existing-project selector, chat input, or client polling controls', () => {
  render(<Dropzone onUploaded={jest.fn()} onError={jest.fn()} />);
  expect(screen.queryByText(/existing owned project/i)).not.toBeInTheDocument();
  expect(screen.queryByRole('textbox', { name: /chat/i })).not.toBeInTheDocument();
  expect(screen.queryByText(/분석 로그/i)).not.toBeInTheDocument();
});

test('displays architecture-image guidance without client-side classification', () => {
  render(<Dropzone onUploaded={jest.fn()} onError={jest.fn()} />);
  expect(screen.getByText('시스템 구성요소와 연결 관계가 표시된 아키텍처 이미지를 업로드해 주세요.')).toBeInTheDocument();
});
