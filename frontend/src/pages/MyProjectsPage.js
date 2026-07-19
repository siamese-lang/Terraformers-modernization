import { useCallback, useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import api from '../utils/api';
import OwnedProjectThumbnail from '../components/OwnedProjectThumbnail';
import ProjectDeleteButton from '../components/ProjectDeleteButton';

const statusLabels = { PENDING: '대기 중', RUNNING: '분석 중', SUCCEEDED: '완료', FAILED: '실패' };
const visibilityLabels = { PUBLIC: '공개', PRIVATE: '비공개' };

function MyProjectsPage() {
  const [projects, setProjects] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const location = useLocation();
  const navigate = useNavigate();
  const [successMessage, setSuccessMessage] = useState(() => location.state?.message || '');

  const refresh = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await api.get('/api/projects');
      setProjects(response.data || []);
    } catch (requestError) {
      setError('프로젝트 목록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  useEffect(() => {
    if (!location.state?.message) return;
    if (successMessage !== location.state.message) {
      setSuccessMessage(location.state.message);
      return;
    }
    navigate(location.pathname, { replace: true, state: null });
  }, [location.pathname, location.state, navigate, successMessage]);

  const deleteProject = (projectId) => setProjects((current) => current.filter((project) => project.projectId !== projectId));

  return (
    <section className="page-stack">
      <header className="page-header"><div><p className="eyebrow">My projects</p><h1>내 프로젝트</h1><p>생성한 프로젝트의 이미지, 분석 상태와 Terraform 파일을 확인하고 관리할 수 있습니다.</p></div><div className="project-page-actions"><span className="project-count">{projects.length}개 프로젝트</span><Link className="primary-link" to="/generate">새 프로젝트 만들기</Link><button type="button" className="secondary-button" onClick={refresh} disabled={loading}>목록 새로고침</button></div></header>
      {successMessage && <p role="status" className="success-message">{successMessage}</p>}
      {error && <p role="alert" className="error">{error}</p>}
      {loading ? <p>프로젝트를 불러오는 중입니다.</p> : projects.length === 0 ? <section className="empty-projects"><p>아직 생성한 프로젝트가 없습니다.</p><Link className="primary-link" to="/generate">새 프로젝트 만들기</Link></section> : <section className="project-card-grid" aria-label="내 프로젝트 목록">
        {projects.map((project) => {
          const name = project.displayName || project.projectName || `Project ${project.projectId}`;
          const status = project.analysisStatus || 'NO_ANALYSIS';
          const visibility = project.visibility || 'PRIVATE';
          return <article key={project.projectId} className="project-card">
            <Link className="project-card-link" to={`/projects/${project.projectId}`} aria-label={`${name} 프로젝트 상세 보기`}><OwnedProjectThumbnail projectId={project.projectId} projectName={name} sourceFileId={project.sourceFileId} /><h2 className="project-card-title">{name}</h2></Link>
            <div className="project-card-meta"><span className={`project-status-badge status-${status.toLowerCase()}`}>{statusLabels[status] || '분석 없음'}</span><span className="project-visibility-badge">{visibilityLabels[visibility] || '비공개'}</span>{(project.originalFilename || project.sourceFileName) && <p>{project.originalFilename || project.sourceFileName}</p>}</div>
            <div className="project-card-actions"><Link className="secondary-button" to={`/projects/${project.projectId}`}>상세 보기</Link><ProjectDeleteButton projectId={project.projectId} projectName={name} onDeleted={() => deleteProject(project.projectId)} onError={setError} /></div>
          </article>;
        })}
      </section>}
    </section>
  );
}

export default MyProjectsPage;
