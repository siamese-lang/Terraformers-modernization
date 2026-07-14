import { useState } from 'react';
import { createAnalysisJob, getAnalysisJob } from './api';

const initialForm = {
  projectId: 'project-browser-smoke',
  sourceBucket: 'example-bucket',
  sourceKey: 'uploads/architecture-diagram.png',
};

function formatJson(value) {
  return JSON.stringify(value, null, 2);
}

function App() {
  const [form, setForm] = useState(initialForm);
  const [job, setJob] = useState(null);
  const [status, setStatus] = useState('idle');
  const [error, setError] = useState('');

  const updateField = (event) => {
    const { name, value } = event.target;
    setForm((previous) => ({ ...previous, [name]: value }));
  };

  const submitAnalysisJob = async (event) => {
    event.preventDefault();
    setStatus('creating');
    setError('');

    try {
      const created = await createAnalysisJob(form);
      setJob(created);
      setStatus(created.status || 'created');
    } catch (requestError) {
      setStatus('failed');
      setError(requestError?.response?.data || requestError.message || 'Analysis job creation failed.');
    }
  };

  const refreshJob = async () => {
    if (!job?.id) return;
    setStatus('refreshing');
    setError('');

    try {
      const refreshed = await getAnalysisJob(job.id);
      setJob(refreshed);
      setStatus(refreshed.status || 'refreshed');
    } catch (requestError) {
      setStatus('failed');
      setError(requestError?.response?.data || requestError.message || 'Analysis job refresh failed.');
    }
  };

  return (
    <main className="app-shell">
      <section className="hero-panel">
        <p className="eyebrow">Terraformers Modernization</p>
        <h1>Backend analysis job browser smoke</h1>
        <p className="hero-copy">
          기존 Terraformers 프론트의 업로드·분석·결과 조회 흐름을 보존하기 위한 첫 번째 공개 안전 브라우저 검증 화면입니다.
          현재 단계에서는 검증된 백엔드 계약인 <code>POST /api/analysis/jobs</code>와 <code>GET /api/analysis/jobs/:id</code>만 호출합니다.
        </p>
      </section>

      <section className="grid-layout">
        <form className="card" onSubmit={submitAnalysisJob}>
          <h2>1. Create analysis job</h2>
          <label>
            Project ID
            <input name="projectId" value={form.projectId} onChange={updateField} maxLength={64} required />
          </label>
          <label>
            Source bucket
            <input name="sourceBucket" value={form.sourceBucket} onChange={updateField} maxLength={255} required />
          </label>
          <label>
            Source key
            <input name="sourceKey" value={form.sourceKey} onChange={updateField} maxLength={1024} required />
          </label>
          <button type="submit" disabled={status === 'creating'}>
            {status === 'creating' ? 'Creating...' : 'Create analysis job'}
          </button>
        </form>

        <section className="card">
          <h2>2. Job status</h2>
          <div className={`status-pill status-${String(status).toLowerCase()}`}>{status}</div>
          <button type="button" onClick={refreshJob} disabled={!job?.id || status === 'refreshing'}>
            {status === 'refreshing' ? 'Refreshing...' : 'Refresh job'}
          </button>
          {error && <pre className="error-box">{String(error)}</pre>}
        </section>
      </section>

      {job && (
        <section className="result-grid">
          <article className="card result-card">
            <h2>3. Result preview</h2>
            <dl>
              <div>
                <dt>Status</dt>
                <dd>{job.status}</dd>
              </div>
              <div>
                <dt>Provider</dt>
                <dd>{job.provider || '-'}</dd>
              </div>
              <div>
                <dt>Result object key</dt>
                <dd className="mono-text">{job.resultObjectKey || '-'}</dd>
              </div>
            </dl>
            <pre className="code-preview">{job.resultPreview || '// no result preview yet'}</pre>
          </article>

          <article className="card result-card">
            <h2>Raw response</h2>
            <pre className="json-preview">{formatJson(job)}</pre>
          </article>
        </section>
      )}

      <section className="card contract-card">
        <h2>Deferred UI contracts</h2>
        <p>
          Dashboard, project tree, public projects, comments, Terraform draft editing, and settings are not removed from the product direction.
          They are backend contract work items and should be restored only when their API boundaries are implemented or explicitly deferred.
        </p>
      </section>
    </main>
  );
}

export default App;
