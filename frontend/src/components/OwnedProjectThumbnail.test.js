import { render, screen, waitFor } from '@testing-library/react';
import OwnedProjectThumbnail from './OwnedProjectThumbnail';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ get: jest.fn() }));

beforeEach(() => { jest.clearAllMocks(); global.URL.createObjectURL = jest.fn(() => 'blob:thumbnail'); global.URL.revokeObjectURL = jest.fn(); });

test('loads an authenticated blob thumbnail and releases its object URL', async () => {
  api.get.mockResolvedValue({ data: new Blob(['image']) });
  const { unmount } = render(<OwnedProjectThumbnail projectId="7" projectName="Diagram" sourceFileId="11" />);
  expect(await screen.findByAltText('Diagram 원본 아키텍처 이미지')).toHaveAttribute('src', 'blob:thumbnail');
  expect(api.get).toHaveBeenCalledWith('/api/projects/7/source-image', { responseType: 'blob' });
  unmount();
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:thumbnail');
});

test('uses a placeholder without a source file or when the image request fails', async () => {
  const { rerender } = render(<OwnedProjectThumbnail projectId="7" projectName="Diagram" sourceFileId={null} />);
  expect(screen.getByText('미리보기 없음')).toBeInTheDocument();
  expect(api.get).not.toHaveBeenCalled();
  api.get.mockRejectedValue(new Error('not found'));
  rerender(<OwnedProjectThumbnail projectId="7" projectName="Diagram" sourceFileId="11" />);
  await waitFor(() => expect(screen.getByText('미리보기 없음')).toBeInTheDocument());
});
