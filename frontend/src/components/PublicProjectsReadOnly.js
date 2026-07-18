import { useCallback, useEffect, useState } from 'react';
import api from '../utils/api';
import '../styles/public-projects.css';

function normalizeProjectId(projectId) {
  if (projectId === null || projectId === undefined) {
    return '';
  }
  return String(projectId);
}

function projectIdOf(project) {
  return normalizeProjectId(project.projectId || project.id || '');
}

function projectNameOf(project) {
  return project.projectName || project.name || projectIdOf(project) || 'Untitled project';
}

function sourceSummary(project) {
  if (project.originalFilename) {
    return project.originalFilename;
  }
  if (project.sourceBucket && project.sourceKey) {
    return `s3://${project.sourceBucket}/${project.sourceKey}`;
  }
  return 'No source metadata yet';
}

function storageSummary(project) {
  const provider = project.sourceStorageProvider || 'metadata-only';
  const persisted = project.sourceBinaryPersisted ? 'persisted' : 'metadata only';
  return `${provider} · ${persisted}`;
}

function PublicProjectsReadOnly({ selectedProjectId, onSelectProject }) {
  const [projects, setProjects] = useState([]);
  const [comments, setComments] = useState([]);
  const [commentContent, setCommentContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isCommentsLoading, setIsCommentsLoading] = useState(false);
  const [isSubmittingComment, setIsSubmittingComment] = useState(false);
  const [error, setError] = useState('');
  const [commentError, setCommentError] = useState('');

  const loadPublicProjects = useCallback(async () => {
    setIsLoading(true);
    setError('');
    try {
      const response = await api.get('/api/public-projects');
      setProjects(Array.isArray(response.data) ? response.data : []);
    } catch (loadError) {
      setError(loadError?.message || '공개 프로젝트 목록 조회에 실패했습니다.');
      setProjects([]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const publicProjectIds = new Set(projects.map((project) => projectIdOf(project)));
  const verifiedSelectedProjectId = publicProjectIds.has(normalizeProjectId(selectedProjectId))
    ? normalizeProjectId(selectedProjectId)
    : '';

  const loadComments = useCallback(async (projectId) => {
    const normalizedProjectId = normalizeProjectId(projectId);
    if (!normalizedProjectId) {
      setComments([]);
      return;
    }

    setIsCommentsLoading(true);
    setCommentError('');
    try {
      const response = await api.get(`/api/getProjectComments/${encodeURIComponent(normalizedProjectId)}`);
      setComments(Array.isArray(response.data) ? response.data : []);
    } catch (loadError) {
      setCommentError(loadError?.response?.status === 403
        ? 'PUBLIC 프로젝트의 댓글만 조회할 수 있습니다.'
        : loadError?.message || '댓글 조회에 실패했습니다.');
      setComments([]);
    } finally {
      setIsCommentsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadPublicProjects();
  }, [loadPublicProjects]);

  useEffect(() => {
    loadComments(verifiedSelectedProjectId);
  }, [loadComments, verifiedSelectedProjectId]);

  const handleSelectProject = (project) => {
    onSelectProject(project);
  };

  const handleSubmitComment = async (event) => {
    event.preventDefault();

    if (!verifiedSelectedProjectId || !commentContent.trim()) {
      return;
    }

    setIsSubmittingComment(true);
    setCommentError('');
    try {
      await api.post('/api/addProjectComment', {
        projectId: verifiedSelectedProjectId,
        content: commentContent,
      });
      setCommentContent('');
      await loadComments(verifiedSelectedProjectId);
    } catch (submitError) {
      if (submitError?.response?.status === 401) {
        setCommentError('댓글을 작성하려면 로그인해야 합니다.');
      } else if (submitError?.response?.status === 403) {
        setCommentError('PUBLIC 프로젝트에만 댓글을 남길 수 있습니다.');
      } else {
        setCommentError(submitError?.message || '댓글 저장에 실패했습니다.');
      }
    } finally {
      setIsSubmittingComment(false);
    }
  };

  return (
    <section className="public-projects-panel" aria-label="Read-only public projects">
      <div className="panel-heading">
        <div>
          <p className="eyebrow">Public projects</p>
          <h2>Shared projects and comments</h2>
        </div>
        <button type="button" className="compact-button" onClick={loadPublicProjects} disabled={isLoading}>
          {isLoading ? 'loading' : 'refresh'}
        </button>
      </div>

      <p className="muted-copy">
        공개 프로젝트는 누구나 조회할 수 있으며, 댓글 작성자는 Cognito 로그인 사용자로 확인됩니다.
        좋아요, 공유 편집, 삭제는 아직 연결하지 않았습니다.
      </p>

      {error && <p className="public-projects-error">{error}</p>}

      {!error && projects.length === 0 && !isLoading && (
        <p className="public-projects-empty">PUBLIC 상태의 프로젝트가 아직 없습니다.</p>
      )}

      {projects.length > 0 && (
        <ul className="public-project-list">
          {projects.map((project) => {
            const projectId = projectIdOf(project);
            const isSelected = verifiedSelectedProjectId === projectId;
            return (
              <li key={projectId}>
                <button
                  type="button"
                  className={isSelected ? 'public-project-card selected' : 'public-project-card'}
                  onClick={() => handleSelectProject(project)}
                >
                  <span className="public-project-title">{projectNameOf(project)}</span>
                  <span className="public-project-meta">{project.visibility || 'PUBLIC'}</span>
                  <span className="public-project-source">{sourceSummary(project)}</span>
                  <span className="public-project-source">{storageSummary(project)}</span>
                </button>
              </li>
            );
          })}
        </ul>
      )}

      <section className="public-comments-panel" aria-label="Public project comments">
        <h3>Comments</h3>
        {!verifiedSelectedProjectId && (
          <p className="public-projects-empty">댓글을 보려면 공개 프로젝트를 선택하세요.</p>
        )}

        {verifiedSelectedProjectId && (
          <>
            {commentError && <p className="public-projects-error">{commentError}</p>}
            {isCommentsLoading && <p className="public-projects-empty">댓글을 불러오는 중입니다.</p>}
            {!isCommentsLoading && comments.length === 0 && !commentError && (
              <p className="public-projects-empty">아직 댓글이 없습니다.</p>
            )}
            {comments.length > 0 && (
              <ul className="public-comment-list">
                {comments.map((comment) => (
                  <li key={comment.id || `${comment.projectId}-${comment.createdAt}`} className="public-comment-item">
                    <div className="public-comment-meta">
                      <span>{comment.userEmail || 'authenticated user'}</span>
                      <span>{comment.createdAt ? new Date(comment.createdAt).toLocaleString() : ''}</span>
                    </div>
                    <p>{comment.content}</p>
                  </li>
                ))}
              </ul>
            )}

            <form className="public-comment-form" onSubmit={handleSubmitComment}>
              <textarea
                value={commentContent}
                onChange={(event) => setCommentContent(event.target.value)}
                placeholder="로그인 사용자로 PUBLIC 프로젝트에 남길 댓글"
              />
              <button
                type="submit"
                className="compact-button"
                disabled={isSubmittingComment || !commentContent.trim()}
              >
                {isSubmittingComment ? 'saving' : 'add comment'}
              </button>
            </form>
          </>
        )}
      </section>
    </section>
  );
}

export default PublicProjectsReadOnly;
