import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import Dropzone from '../components/Dropzone';

function GeneratePage() {
  const navigate = useNavigate();
  const [error, setError] = useState('');
  return (
    <section className="page-stack">
      <header className="page-header"><p className="eyebrow">Generate</p><h1>새 Terraform 코드 생성</h1><p>프로젝트 이름과 아키텍처 이미지 한 장으로 분석을 시작합니다.</p></header>
      {error && <p role="alert" className="error">{error}</p>}
      <Dropzone onUploaded={(projectId) => navigate(`/projects/${projectId}`)} onError={setError} />
    </section>
  );
}

export default GeneratePage;
