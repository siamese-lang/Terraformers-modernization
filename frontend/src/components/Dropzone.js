import { useCallback, useMemo, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import api from '../utils/api';
import { eventBus } from '../utils/eventBus';

const maxFileSize = 524288000;
const defaultBucket = process.env.REACT_APP_ANALYSIS_SOURCE_BUCKET || 'example-bucket';
const defaultSourceKey = process.env.REACT_APP_ANALYSIS_SOURCE_KEY || 'uploads/architecture-diagram.png';
const defaultProjectId = process.env.REACT_APP_ANALYSIS_PROJECT_ID || 'project-browser-smoke';

const baseStyle = {
  flex: 1,
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  padding: '28px',
  borderWidth: 2,
  borderRadius: 12,
  borderColor: '#475569',
  borderStyle: 'dashed',
  backgroundColor: '#0f172a',
  color: '#cbd5e1',
  outline: 'none',
  transition: 'border .24s ease-in-out, background .24s ease-in-out',
  cursor: 'pointer',
};

const focusedStyle = { borderColor: '#38bdf8' };
const acceptStyle = { borderColor: '#34d399', backgroundColor: '#052e2b' };
const rejectStyle = { borderColor: '#f87171', backgroundColor: '#3b1111' };

function buildErrorMessage(error) {
  const status = error?.response?.status;
  const data = error?.response?.data;

  if (typeof data === 'string' && data.trim()) {
    return status ? `Request failed with status code ${status}: ${data}` : data;
  }

  if (data && typeof data === 'object') {
    return status
      ? `Request failed with status code ${status}: ${JSON.stringify(data)}`
      : JSON.stringify(data);
  }

  return error?.message || 'Analysis job request failed.';
}

async function waitForJob(jobId) {
  let latest = null;

  for (let attempt = 0; attempt < 30; attempt += 1) {
    const response = await api.get(`/api/analysis/jobs/${encodeURIComponent(jobId)}`);
    latest = response.data;

    if (latest.status === 'SUCCEEDED' || latest.status === 'FAILED') {
      return latest;
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return latest;
}

function Dropzone({ closeModal, setDataMain }) {
  const [files, setFiles] = useState([]);
  const [isUploading, setIsUploading] = useState(false);

  const onDrop = useCallback((acceptedFiles) => {
    setFiles(acceptedFiles.map((file) => Object.assign(file, {
      preview: URL.createObjectURL(file),
    })));
  }, []);

  const { getRootProps, getInputProps, isFocused, isDragAccept, isDragReject } = useDropzone({
    accept: {
      'image/png': ['.png'],
      'image/jpeg': ['.jpg', '.jpeg'],
    },
    maxSize: maxFileSize,
    multiple: false,
    onDrop,
  });

  const style = useMemo(() => ({
    ...baseStyle,
    ...(isFocused ? focusedStyle : {}),
    ...(isDragAccept ? acceptStyle : {}),
    ...(isDragReject ? rejectStyle : {}),
  }), [isFocused, isDragAccept, isDragReject]);

  const handleUpload = async () => {
    if (files.length === 0 || isUploading) {
      return;
    }

    const file = files[0];
    const projectId = defaultProjectId;
    const sourceKey = defaultSourceKey;

    setIsUploading(true);
    eventBus.emit('bedrock:start');
    eventBus.emit('bedrock:logs', [
      `Selected image: ${file.name}`,
      `Creating analysis job for projectId=${projectId}`,
      `Using smoke source reference: s3://${defaultBucket}/${sourceKey}`,
      'Binary object upload is not implemented in this pass; this uses the validated backend smoke reference.',
    ]);

    setDataMain((previous) => [
      ...previous,
      {
        key: `image-${Date.now()}`,
        type: 'user_image',
        text: `<img src="${file.preview}" alt="uploaded architecture" class="chat-upload-preview" />`,
        isUser: true,
      },
      {
        key: `pending-${Date.now()}`,
        type: 'terraform_result',
        explanation: 'AI가 답변을 생성 중입니다...',
        terraformCode: '',
        isUser: false,
      },
    ]);

    try {
      const response = await api.post('/api/analysis/jobs', {
        projectId,
        sourceBucket: defaultBucket,
        sourceKey,
        correlationId: `browser-upload-${Date.now()}`,
      });

      const created = response.data;
      eventBus.emit('bedrock:logs', [`Analysis job created: ${created.id}`]);

      const completed = created.status === 'SUCCEEDED' || created.status === 'FAILED'
        ? created
        : await waitForJob(created.id);

      if (completed?.status === 'FAILED') {
        throw new Error(completed.failureReason || 'Analysis job failed.');
      }

      eventBus.emit('bedrock:result', {
        projectId: completed?.projectId || projectId,
        terraformCode: completed?.resultPreview || '',
        explanation: `분석 작업이 완료되었습니다. provider=${completed?.provider || '-'}, resultObjectKey=${completed?.resultObjectKey || '-'}`,
      });
      eventBus.emit('bedrock:complete');
      closeModal();
    } catch (error) {
      eventBus.emit('bedrock:error', buildErrorMessage(error));
    } finally {
      setIsUploading(false);
    }
  };

  return (
    <section className="dropzone-panel">
      <h2>Upload architecture image</h2>
      <p className="muted-copy">
        원본 Terraformers의 이미지 업로드 흐름을 현재 백엔드의 analysis job 계약에 연결합니다.
        이 단계에서는 실제 바이너리 업로드 대신 검증된 smoke source reference를 사용합니다.
      </p>
      <div {...getRootProps({ style })}>
        <input {...getInputProps()} />
        <p>PNG/JPEG 아키텍처 이미지를 드래그하거나 클릭해 선택하세요.</p>
      </div>

      {files.length > 0 && (
        <aside className="dropzone-preview-list">
          {files.map((file) => (
            <div className="dropzone-preview" key={file.name}>
              <img src={file.preview} alt={file.name} onLoad={() => URL.revokeObjectURL(file.preview)} />
              <span>{file.name}</span>
            </div>
          ))}
        </aside>
      )}

      <div className="modal-actions">
        <button type="button" className="primary-button" disabled={files.length === 0 || isUploading} onClick={handleUpload}>
          {isUploading ? '분석 작업 생성 중...' : '분석 작업 생성'}
        </button>
        <button type="button" className="secondary-button" onClick={closeModal}>닫기</button>
      </div>
    </section>
  );
}

export default Dropzone;
