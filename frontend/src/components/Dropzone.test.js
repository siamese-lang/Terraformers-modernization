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
