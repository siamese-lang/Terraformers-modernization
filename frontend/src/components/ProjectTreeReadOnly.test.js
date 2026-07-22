import { render, screen, waitFor } from '@testing-library/react';
import ProjectTreeReadOnly from './ProjectTreeReadOnly';
import api from '../utils/api';

jest.mock('../utils/api', () => ({ get: jest.fn() }));

beforeEach(() => {
  global.URL.createObjectURL = jest.fn(() => 'blob:image');
  global.URL.revokeObjectURL = jest.fn();
  api.get.mockImplementation((url) => {
    if (url === '/api/project-tree/1') return Promise.resolve({ data: { projectId: 1, tree: [] } });
    if (url.endsWith('/source-image')) return Promise.resolve({ data: new Blob(['image']) });
    return Promise.resolve({ data: { content: '' } });
  });
});

test('uses the containment wrapper for the source image', async () => {
  const { container } = render(<ProjectTreeReadOnly selectedProjectId="1" />);
  await waitFor(() => expect(container.querySelector('.project-source-image-wrapper')).toBeInTheDocument());
  expect(screen.getByAltText('Persisted architecture')).toHaveClass('project-source-image');
});
