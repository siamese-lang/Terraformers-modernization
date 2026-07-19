import { useCallback, useEffect, useMemo, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import api from '../utils/api';

const maxFileSize = 10 * 1024 * 1024;
const baseStyle = { display: 'flex', flexDirection: 'column', alignItems: 'center', padding: 28, border: '2px dashed #475569', borderRadius: 12, cursor: 'pointer' };

function Dropzone({ onUploaded, onError }) {
  const [files, setFiles] = useState([]);
  const [projectName, setProjectName] = useState('');
  const [uploading, setUploading] = useState(false);
  const [fileError, setFileError] = useState('');
  useEffect(() => () => files.forEach((file) => URL.revokeObjectURL(file.preview)), [files]);
  const onDrop = useCallback((accepted, rejected) => {
    if (rejected.length) { setFileError('파일은 PNG/JPEG 형식이며 10 MB 이하여야 합니다.'); return; }
    setFileError(''); setFiles(accepted.map((file) => Object.assign(file, { preview: URL.createObjectURL(file) })));
  }, []);
  const { getRootProps, getInputProps } = useDropzone({ accept: { 'image/png': ['.png'], 'image/jpeg': ['.jpg', '.jpeg'] }, maxSize: maxFileSize, multiple: false, onDrop });
  const submit = async () => {
    if (!projectName.trim()) { setFileError('프로젝트 이름을 입력하세요.'); return; }
    if (!files[0]) { setFileError('아키텍처 이미지를 선택하세요.'); return; }
    setUploading(true); onError?.('');
    try { const data = new FormData(); data.append('file', files[0]); data.append('projectName', projectName.trim()); const response = await api.post('/api/upload', data); onUploaded(response.data.projectId); }
    catch (error) { onError?.(error?.response?.data || error.message || '업로드 분석 요청에 실패했습니다.'); }
    finally { setUploading(false); }
  };
  const style = useMemo(() => baseStyle, []);
  return <section className="dropzone-panel"><label className="upload-field">프로젝트 이름<input value={projectName} onChange={(event) => setProjectName(event.target.value)} placeholder="Architecture project name" /></label><div {...getRootProps({ style })}><input {...getInputProps({ 'aria-label': 'PNG/JPEG architecture image' })} /><p>PNG/JPEG 아키텍처 이미지를 드래그하거나 클릭해 선택하세요.</p></div>{fileError && <p role="alert" className="error">{fileError}</p>}{files[0] && <div className="dropzone-preview"><img src={files[0].preview} alt={files[0].name} style={{ objectFit: 'contain', maxWidth: '100%', height: 'auto', maxHeight: 480 }} /><span>{files[0].name}</span></div>}<button type="button" className="primary-button" disabled={uploading} onClick={submit}>{uploading ? '분석 요청 중...' : '분석 시작'}</button></section>;
}
export default Dropzone;
