import { useState } from 'react';
import api from '../utils/api';

function ProjectDeleteButton({ projectId, projectName, onDeleted, onError, className = 'danger-button' }) {
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState('');

  const remove = async () => {
    if (isDeleting) return;
    if (!window.confirm(`"${projectName}" 프로젝트를 삭제하시겠습니까?\n프로젝트가 내 프로젝트와 공개 화면에서 제거되며,\n더 이상 결과에 접근할 수 없습니다.\n이 작업은 되돌릴 수 없습니다.`)) return;

    setError('');
    onError?.('');
    setIsDeleting(true);
    try {
      await api.delete(`/api/projects/${encodeURIComponent(projectId)}`);
      onDeleted?.();
    } catch (requestError) {
      const message = '프로젝트 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.';
      setError(message);
      onError?.(message, requestError);
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <>
      <button type="button" className={className} disabled={isDeleting} onClick={remove} aria-label={`${projectName} 프로젝트 삭제`}>
        {isDeleting ? '삭제 중...' : '프로젝트 삭제'}
      </button>
      {error && !onError && <p role="alert" className="error">{error}</p>}
    </>
  );
}

export default ProjectDeleteButton;
