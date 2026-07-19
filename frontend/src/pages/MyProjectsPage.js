import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import api from '../utils/api';

function MyProjectsPage() {
  const [projects, setProjects] = useState([]);
  const [refreshToken, setRefreshToken] = useState(0);
  const [error, setError] = useState('');
  const [deletingId, setDeletingId] = useState(null);

  const refresh = useCallback(async () => {
    const response = await api.get('/api/projects');
    setProjects(response.data || []);
  }, []);

  useEffect(() => { refresh().catch((err) => setError(err.message)); }, [refresh, refreshToken]);

  const deleteProject = async (project) => {
    if (!window.confirm(`Delete project "${project.displayName}"? Stored objects will remain for retention cleanup.`)) return;
    setDeletingId(project.projectId);
    setError('');
    try {
      await api.delete(`/api/projects/${encodeURIComponent(project.projectId)}`);
      setRefreshToken((value) => value + 1);
    } catch (err) {
      setError(err?.response?.data || err.message || '프로젝트 삭제에 실패했습니다.');
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <section className="page-stack">
      <header className="page-header"><div><p className="eyebrow">My projects</p><h1>내 프로젝트</h1><p>생성한 프로젝트의 이미지, 분석 상태와 Terraform 파일을 확인하고 삭제할 수 있습니다.</p></div></header>
      {error && <p role="alert" className="error">{error}</p>}
      <section className="project-list-panel">
        <h2>Owned projects</h2>
        {projects.length === 0 ? <p>아직 프로젝트가 없습니다.</p> : projects.map((project) => (
          <article key={project.projectId} className="project-list-item">
            <Link to={`/projects/${project.projectId}`}>{project.displayName || `Project ${project.projectId}`}</Link>
            <Link to={`/projects/${project.projectId}`}>상세 보기</Link>
            <span>{project.analysisStatus || 'NO_ANALYSIS'}</span>
            <button type="button" className="danger-button" disabled={deletingId === project.projectId} onClick={() => deleteProject(project)}>{deletingId === project.projectId ? '삭제 중...' : 'Delete'}</button>
          </article>
        ))}
      </section>
    </section>
  );
}

export default MyProjectsPage;
