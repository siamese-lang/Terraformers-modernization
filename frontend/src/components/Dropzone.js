import { useCallback, useMemo, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import api from '../utils/api';
import { eventBus } from '../utils/eventBus';

const maxFileSize = 524288000;

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

  return error?.message || 'Upload analysis request failed.';
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

function resolveJobId(uploadResponse) {
  return uploadResponse.analysisJobId || uploadResponse.id;
}

function normalizeUploadResponse(uploadResponse) {
  return {
    id: resolveJobId(uploadResponse),
    projectId: uploadResponse.projectId,
    sourceFileId: uploadResponse.sourceFileId,
    sourceBucket: uploadResponse.sourceBucket,
    sourceKey: uploadResponse.sourceKey,
    status: uploadResponse.status,
    analysisMode: uploadResponse.analysisMode,
    provider: uploadResponse.provider,
    resultObjectKey: uploadResponse.resultObjectKey,
    resultPreview: uploadResponse.resultPreview,
    failureReason: uploadResponse.failureReason,
  };
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
    const formData = new FormData();
    formData.append('file', file);

    setIsUploading(true);
    eventBus.emit('bedrock:start');
    eventBus.emit('bedrock:logs', [
      `Selected image: ${file.name}`,
      'Uploading as the signed-in Cognito user: POST /api/upload',
      'The backend creates an owned numeric project, persists source file metadata, and starts an analysis job.',
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
      const response = await api.post('/api/upload', formData, {
        tokenType: 'id',
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      const created = normalizeUploadResponse(response.data);
      eventBus.emit('bedrock:logs', [
        `Project created or selected: ${created.projectId}`,
        `Source file registered: ${created.sourceFileId}`,
        `Analysis job created: ${created.id}`,
        `Source reference: s3://${created.sourceBucket}/${created.sourceKey}`,
      ]);

      const completed = created.status === 'SUCCEEDED' || created.status === 'FAILED'
        ? created
        : await waitForJob(created.id);

      if (completed?.status === 'FAILED') {
        throw new Error(completed.failureReason || 'Analysis job failed.');
      }

      eventBus.emit('bedrock:result', {
        projectId: completed?.projectId || created.projectId,
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
        로그인한 사용자 소유의 프로젝트와 파일 메타데이터를 생성한 뒤 <code>POST /api/upload</code>로 분석 작업을 시작합니다.
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
          {isUploading ? '업로드 분석 요청 중...' : '업로드 분석 요청'}
        </button>
        <button type="button" className="secondary-button" onClick={closeModal}>닫기</button>
      </div>
    </section>
  );
}

export default Dropzone;
