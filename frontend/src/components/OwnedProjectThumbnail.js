import { useEffect, useRef, useState } from 'react';
import api from '../utils/api';

function OwnedProjectThumbnail({ projectId, projectName, sourceFileId }) {
  const [imageUrl, setImageUrl] = useState('');
  const objectUrlRef = useRef(null);

  useEffect(() => {
    let active = true;
    if (!sourceFileId) {
      setImageUrl('');
      return undefined;
    }

    api.get(`/api/projects/${encodeURIComponent(projectId)}/source-image`, { responseType: 'blob' })
      .then((response) => {
        if (!active) return;
        if (objectUrlRef.current) URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = URL.createObjectURL(response.data);
        setImageUrl(objectUrlRef.current);
      })
      .catch(() => {
        if (active) setImageUrl('');
      });

    return () => {
      active = false;
      if (objectUrlRef.current) {
        URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = null;
      }
    };
  }, [projectId, sourceFileId]);

  return (
    <div className="project-card-thumbnail">
      {imageUrl ? <img src={imageUrl} alt={`${projectName} 원본 아키텍처 이미지`} /> : <span>미리보기 없음</span>}
    </div>
  );
}

export default OwnedProjectThumbnail;
