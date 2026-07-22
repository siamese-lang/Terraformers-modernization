import { useState } from 'react';
import ProjectTreeReadOnly from '../components/ProjectTreeReadOnly';
import PublicProjectsReadOnly from '../components/PublicProjectsReadOnly';

function projectIdOf(project) {
  return project?.projectId || project?.id || '';
}

function CommunityPage() {
  const [selectedProjectId, setSelectedProjectId] = useState('');

  const handleSelectProject = (project) => {
    setSelectedProjectId(projectIdOf(project));
  };

  return (
    <section className="page-stack">
      <header className="page-header">
        <div>
          <p className="eyebrow">Community</p>
          <h1>공개 프로젝트</h1>
          <p>공개된 아키텍처와 Terraform 초안을 확인하고 댓글을 남길 수 있습니다.</p>
        </div>
      </header>

      <PublicProjectsReadOnly
        selectedProjectId={selectedProjectId}
        onSelectProject={handleSelectProject}
      />

      {selectedProjectId && (
        <section className="community-project-detail">
          <ProjectTreeReadOnly selectedProjectId={selectedProjectId} />
        </section>
      )}
    </section>
  );
}

export default CommunityPage;
