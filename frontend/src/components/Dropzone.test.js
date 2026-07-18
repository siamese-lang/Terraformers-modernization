import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Dropzone from './Dropzone';
import api from '../utils/api';
import { eventBus } from '../utils/eventBus';

jest.mock('../utils/api', () => ({
  get: jest.fn(),
  post: jest.fn(),
}));

const createObjectURL = jest.fn()
  .mockReturnValueOnce('blob:local-preview')
  .mockReturnValue('blob:persisted-image');
const revokeObjectURL = jest.fn();

beforeEach(() => {
  jest.clearAllMocks();
  createObjectURL.mockReset();
  createObjectURL.mockReturnValueOnce('blob:local-preview').mockReturnValue('blob:persisted-image');
  global.URL.createObjectURL = createObjectURL;
  global.URL.revokeObjectURL = revokeObjectURL;
  window.URL.createObjectURL = createObjectURL;
  window.URL.revokeObjectURL = revokeObjectURL;
  api.get.mockImplementation((url) => {
    if (url === '/api/projects') {
      return Promise.resolve({ data: [{ projectId: 7, displayName: 'Existing project' }] });
    }
    if (url === '/api/projects/7/source-image') {
      return Promise.resolve({ data: new Blob(['persisted'], { type: 'image/png' }) });
    }
    if (url === '/api/projects/7/terraform/main.tf') {
      return Promise.resolve({ data: { content: 'resource "aws_s3_bucket" "accepted" {}' } });
    }
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });
  api.post.mockResolvedValue({
    data: {
      analysisJobId: 'job-1',
      projectId: 7,
      sourceFileId: 10,
      status: 'SUCCEEDED',
      analysisSummary: 'Actual model summary',
      detectedComponents: ['S3'],
      detectedRelationships: ['client uploads to S3'],
      warnings: ['bucket name inferred'],
    },
  });
});

test('existing-project upload sends projectId and emits persisted source image blob', async () => {
  const imageEvents = [];
  const onImage = (event) => imageEvents.push(event);
  eventBus.on('bedrock:image', onImage);

  render(<Dropzone closeModal={jest.fn()} setDataMain={jest.fn()} />);
  await userEvent.click(screen.getByLabelText(/Add an image to an existing owned project/i));
  await screen.findByText('Existing project');
  await userEvent.selectOptions(screen.getByRole('combobox'), '7');

  const file = new File(['image-bytes'], 'diagram.png', { type: 'image/png' });
  await userEvent.upload(screen.getByLabelText(/PNG\/JPEG/i), file);
  const uploadButton = screen.getByRole('button', { name: /업로드 분석 요청/ });
  await waitFor(() => expect(uploadButton).not.toBeDisabled());
  await userEvent.click(uploadButton);

  await waitFor(() => expect(api.post).toHaveBeenCalled());
  const formData = api.post.mock.calls[0][1];
  expect(formData.get('projectId')).toBe('7');
  expect(formData.get('projectName')).toBeNull();
  await waitFor(() => expect(api.get).toHaveBeenCalledWith('/api/projects/7/source-image', { responseType: 'blob' }));
  expect(imageEvents[0]).toMatchObject({ projectId: 7, imageUrl: 'blob:persisted-image' });
  expect(revokeObjectURL).not.toHaveBeenCalledWith('blob:persisted-image');

  eventBus.off('bedrock:image', onImage);
});

test('polling timeout emits pending event without fetching final artifacts or success result', async () => {
  const pendingEvents = [];
  const resultEvents = [];
  const imageEvents = [];
  const closeModal = jest.fn();
  const onPending = (event) => pendingEvents.push(event);
  const onResult = (event) => resultEvents.push(event);
  const onImage = (event) => imageEvents.push(event);
  eventBus.on('bedrock:pending', onPending);
  eventBus.on('bedrock:result', onResult);
  eventBus.on('bedrock:image', onImage);
  api.post.mockResolvedValueOnce({
    data: {
      analysisJobId: 'job-timeout',
      projectId: 9,
      sourceFileId: 12,
      status: 'PENDING',
    },
  });
  api.get.mockImplementation((url) => {
    if (url === '/api/projects') {
      return Promise.resolve({ data: [] });
    }
    if (url === '/api/analysis/jobs/job-timeout') {
      return Promise.resolve({ data: { id: 'job-timeout', projectId: 9, status: 'RUNNING' } });
    }
    return Promise.reject(new Error(`unexpected GET ${url}`));
  });

  render(<Dropzone closeModal={closeModal} setDataMain={jest.fn()} pollingOptions={{ attempts: 1, delayMs: 0 }} />);
  await userEvent.type(screen.getByLabelText(/Project name/i), 'Timeout Project');
  const file = new File(['image-bytes'], 'timeout.png', { type: 'image/png' });
  await userEvent.upload(screen.getByLabelText(/PNG\/JPEG/i), file);
  const uploadButton = screen.getByRole('button', { name: /업로드 분석 요청/ });
  await waitFor(() => expect(uploadButton).not.toBeDisabled());
  await userEvent.click(uploadButton);

  await waitFor(() => expect(pendingEvents).toHaveLength(1));
  expect(pendingEvents[0]).toMatchObject({ projectId: 9, jobId: 'job-timeout', status: 'RUNNING' });
  expect(resultEvents).toHaveLength(0);
  expect(imageEvents).toHaveLength(0);
  expect(api.get).not.toHaveBeenCalledWith('/api/projects/9/source-image', { responseType: 'blob' });
  expect(api.get).not.toHaveBeenCalledWith('/api/projects/9/terraform/main.tf');
  expect(closeModal).toHaveBeenCalled();

  eventBus.off('bedrock:pending', onPending);
  eventBus.off('bedrock:result', onResult);
  eventBus.off('bedrock:image', onImage);
});
