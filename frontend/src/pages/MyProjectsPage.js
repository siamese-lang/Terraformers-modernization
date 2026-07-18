import ProjectTreeReadOnly from '../components/ProjectTreeReadOnly';

function MyProjectsPage() {
  return (
    <section className="page-stack">
      <header className="page-header">
        <div>
          <p className="eyebrow">My projects</p>
          <h1>내 프로젝트</h1>
          <p>생성한 프로젝트의 이미지, 분석 상태와 Terraform 파일을 확인합니다.</p>
        </div>
      </header>

      <ProjectTreeReadOnly />
    </section>
  );
}

export default MyProjectsPage;
