import { useCallback, useEffect, useState } from 'react';
import api from '../utils/api';
import '../styles/public-projects.css';

function projectIdOf(project) {
  return project.projectId || project.id || '';
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

function PublicProjectsReadOnly({ selectedProjectId, onSelectProject }) {
  const [projects, setProjects] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

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

  useEffect(() => {
    loadPublicProjects();
  }, [loadPublicProjects]);

  return (
    <section className="public-projects-panel" aria-label="Read-only public projects">
      <div className="panel-heading">
        <div>
          <p className="eyebrow">Public projects</p>
          <h2>Read-only shared projects</h2>
        </div>
        <button type="button" className="compact-button" onClick={loadPublicProjects} disabled={isLoading}>
          {isLoading ? 'loading' : 'refresh'}
        </button>
      </div>

      <p className="muted-copy">
        기존 Terraformers의 `/api/public-projects` 흐름을 현재 프로젝트 메타데이터 계약에 맞춘 조회 전용 목록입니다.
        댓글, 좋아요, 공유 편집은 아직 연결하지 않았습니다.
      </p>

      {error && <p className="public-projects-error">{error}</p>}

      {!error && projects.length === 0 && !isLoading && (
        <p className="public-projects-empty">PUBLIC 상태의 프로젝트가 아직 없습니다.</p>
      )}

      {projects.length > 0 && (
        <ul className="public-project-list">
          {projects.map((project) => {
            const projectId = projectIdOf(project);
            const isSelected = selectedProjectId === projectId;
            return (
              <li key={projectId}>
                <button
                  type="button"
                  className={isSelected ? 'public-project-card selected' : 'public-project-card'}
                  onClick={() => onSelectProject(project)}
                >
                  <span className="public-project-title">{projectNameOf(project)}</span>
                  <span className="public-project-meta">{project.visibility || 'PUBLIC'}</span>
                  <span className="public-project-source">{sourceSummary(project)}</span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

export default PublicProjectsReadOnly;
