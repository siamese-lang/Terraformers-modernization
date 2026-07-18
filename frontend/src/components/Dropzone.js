import { useCallback, useEffect, useMemo, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import api from '../utils/api';
import { eventBus } from '../utils/eventBus';

const maxFileSize = 10 * 1024 * 1024;
const maxFileSizeLabel = '10 MB';

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
    resultFileId: uploadResponse.resultFileId,
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
  const [fileError, setFileError] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [uploadMode, setUploadMode] = useState('new');
  const [projectName, setProjectName] = useState('');
  const [projectId, setProjectId] = useState('');
  const [projects, setProjects] = useState([]);

  useEffect(() => {
    let mounted = true;
    api.get('/api/projects').then((response) => { if (mounted) setProjects(response.data || []); }).catch(() => { if (mounted) setProjects([]); });
    return () => { mounted = false; };
  }, []);

  useEffect(() => () => {
    files.forEach((file) => { if (file.preview) URL.revokeObjectURL(file.preview); });
  }, [files]);

  const onDrop = useCallback((acceptedFiles, fileRejections) => {
    if (fileRejections.length > 0) {
      setFiles([]);
      setFileError(`파일은 PNG/JPEG 형식이며 ${maxFileSizeLabel} 이하여야 합니다.`);
      return;
    }

    setFileError('');
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
    if (uploadMode === 'new' && !projectName.trim()) { setFileError('새 프로젝트 이름을 입력하세요.'); return; }
    if (uploadMode === 'existing' && !projectId) { setFileError('기존 프로젝트를 선택하세요.'); return; }
    const formData = new FormData();
    formData.append('file', file);
    if (uploadMode === 'new') { formData.append('projectName', projectName.trim()); } else { formData.append('projectId', projectId); }

    setIsUploading(true);
    eventBus.emit('bedrock:start');
    eventBus.emit('bedrock:logs', [
      `Selected image: ${file.name}`,
      'Uploading as the signed-in Cognito user: POST /api/upload',
      uploadMode === 'new' ? `Creating new project: ${projectName.trim()}` : `Adding image to existing project: ${projectId}`,
    ]);

    setDataMain((previous) => [
      ...previous,
      {
        key: `image-${Date.now()}`,
        type: 'user_image',
        imageUrl: file.preview,
        alt: file.name,
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
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      const created = normalizeUploadResponse(response.data);
      eventBus.emit('bedrock:logs', [
        `Project ${uploadMode === 'new' ? 'created' : 'selected'}: ${created.projectId}`,
        `Source file registered: ${created.sourceFileId}`,
        `Terraform result file registered: ${created.resultFileId}`,
        `Analysis job created: ${created.id}`,
        'Source image stored privately and will be fetched through /api/projects/{projectId}/source-image',
      ]);

      const completed = created.status === 'SUCCEEDED' || created.status === 'FAILED'
        ? created
        : await waitForJob(created.id);

      if (completed?.status === 'FAILED') {
        throw new Error(completed.failureReason || 'Analysis job failed.');
      }

      const finalProjectId = completed?.projectId || created.projectId;
      let terraformCode = '';
      try {
        const draftResponse = await api.get(`/api/projects/${encodeURIComponent(finalProjectId)}/terraform/main.tf`);
        terraformCode = draftResponse.data?.content || '';
      } catch {
        terraformCode = completed?.resultPreview || '';
      }
      eventBus.emit('bedrock:result', {
        projectId: finalProjectId,
        resultFileId: completed?.resultFileId || created.resultFileId,
        terraformCode,
        explanation: completed?.analysisSummary || '분석 작업이 완료되었습니다.',
        components: completed?.detectedComponents || [],
        relationships: completed?.detectedRelationships || [],
        warnings: completed?.warnings || [],
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
        로그인한 사용자 소유의 프로젝트에 원본 이미지와 생성된 <code>main.tf</code> 아티팩트를 등록합니다.
      </p>
      <fieldset className="upload-mode-fieldset">
        <legend>Upload mode</legend>
        <label><input type="radio" name="uploadMode" value="new" checked={uploadMode === 'new'} onChange={() => setUploadMode('new')} /> Create a new project</label>
        <label><input type="radio" name="uploadMode" value="existing" checked={uploadMode === 'existing'} onChange={() => setUploadMode('existing')} /> Add an image to an existing owned project</label>
      </fieldset>
      {uploadMode === 'new' ? (
        <label className="upload-field">Project name<input value={projectName} onChange={(event) => setProjectName(event.target.value)} placeholder="Architecture project name" /></label>
      ) : (
        <label className="upload-field">Owned project<select value={projectId} onChange={(event) => setProjectId(event.target.value)}><option value="">Select a project</option>{projects.map((project) => <option key={project.projectId} value={project.projectId}>{project.name || project.displayName || `Project ${project.projectId}`}</option>)}</select></label>
      )}

      <div {...getRootProps({ style })}>
        <input {...getInputProps()} />
        <p>PNG/JPEG 아키텍처 이미지를 드래그하거나 클릭해 선택하세요.</p>
        <p>파일 크기는 최대 {maxFileSizeLabel}입니다.</p>
      </div>

      {fileError && <p role="alert" className="error">{fileError}</p>}

      {files.length > 0 && (
        <aside className="dropzone-preview-list">
          {files.map((file) => (
            <div className="dropzone-preview" key={file.name}>
              <img src={file.preview} alt={file.name} />
              <span>{file.name}</span>
            </div>
          ))}
        </aside>
      )}

      <div className="modal-actions">
        <button type="button" className="primary-button" disabled={files.length === 0 || isUploading || (uploadMode === 'new' && !projectName.trim()) || (uploadMode === 'existing' && !projectId)} onClick={handleUpload}>
          {isUploading ? '업로드 분석 요청 중...' : '업로드 분석 요청'}
        </button>
        <button type="button" className="secondary-button" onClick={closeModal}>닫기</button>
      </div>
    </section>
  );
}

export default Dropzone;
