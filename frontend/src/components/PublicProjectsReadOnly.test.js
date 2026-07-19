import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import PublicProjectsReadOnly from './PublicProjectsReadOnly';
import api from '../utils/api';

jest.mock('../utils/api', () => ({
  get: jest.fn(),
  post: jest.fn(),
}));

const publicProjects = [
  { projectId: 101, projectName: 'Public numeric' },
  { id: '202', name: 'Public string' },
];

beforeEach(() => {
  jest.clearAllMocks();
  api.get.mockImplementation((url) => {
    if (url === '/api/public-projects') {
      return Promise.resolve({ data: publicProjects });
    }
    return Promise.resolve({ data: [{ id: 'c1', projectId: '101', content: 'hello' }] });
  });
  api.post.mockResolvedValue({ data: {} });
});

test('does not call comments API without a verified public project selection', async () => {
  render(<PublicProjectsReadOnly selectedProjectId="private-999" onSelectProject={jest.fn()} />);

  expect(await screen.findByText('Public numeric')).toBeInTheDocument();
  await waitFor(() => expect(api.get).toHaveBeenCalledWith('/api/public-projects'));
  expect(api.get).not.toHaveBeenCalledWith(expect.stringContaining('/api/getProjectComments/'));
  expect(screen.getByText('댓글을 보려면 공개 프로젝트를 선택하세요.')).toBeInTheDocument();
});

test('normalizes numeric and string ids before loading and writing comments', async () => {
  render(<PublicProjectsReadOnly selectedProjectId="101" onSelectProject={jest.fn()} />);

  expect(await screen.findByText('Public numeric')).toBeInTheDocument();
  await waitFor(() => expect(api.get).toHaveBeenCalledWith('/api/getProjectComments/101'));

  await userEvent.type(screen.getByPlaceholderText('로그인 사용자로 PUBLIC 프로젝트에 남길 댓글'), 'new comment');
  await userEvent.click(screen.getByRole('button', { name: 'add comment' }));

  await waitFor(() => expect(api.post).toHaveBeenCalledWith('/api/addProjectComment', {
    projectId: '101',
    content: 'new comment',
  }));
});

test('select handler delegates selection without duplicating comment requests', async () => {
  const onSelectProject = jest.fn();
  render(<PublicProjectsReadOnly selectedProjectId="" onSelectProject={onSelectProject} />);

  await userEvent.click(await screen.findByRole('button', { name: /Public string/ }));

  expect(onSelectProject).toHaveBeenCalledWith(publicProjects[1]);
  expect(api.get.mock.calls.filter(([url]) => url.startsWith('/api/getProjectComments/'))).toHaveLength(0);
});

test('renders a lazy thumbnail and author display name without storage metadata', async () => {
  api.get.mockImplementation((url) => {
    if (url === '/api/public-projects') {
      return Promise.resolve({ data: [{ projectId: 303, projectName: 'Image project', imageUrl: '/api/projects/303/source-image', originalFilename: 'diagram.png' }] });
    }
    return Promise.resolve({ data: [{ id: 'c2', projectId: '303', content: 'hello', authorDisplayName: '별명', userEmail: 'hidden@example.com' }] });
  });
  render(<PublicProjectsReadOnly selectedProjectId="303" onSelectProject={jest.fn()} />);

  const image = await screen.findByAltText('Image project 미리보기');
  expect(image).toHaveAttribute('loading', 'lazy');
  expect(await screen.findByText('별명')).toBeInTheDocument();
  expect(screen.queryByText(/metadata-only|s3:\/\//i)).not.toBeInTheDocument();
});

test('shows the thumbnail placeholder after an image load error', async () => {
  api.get.mockImplementation((url) => Promise.resolve({
    data: url === '/api/public-projects'
      ? [{ projectId: 404, projectName: 'Broken image', imageUrl: '/broken.png' }]
      : [],
  }));
  render(<PublicProjectsReadOnly selectedProjectId="" onSelectProject={jest.fn()} />);
  const image = await screen.findByAltText('Broken image 미리보기');
  await userEvent.click(image); // ensure the element remains interactive inside the card
  image.dispatchEvent(new Event('error'));
  expect(screen.getByText('미리보기 없음')).toBeVisible();
});
