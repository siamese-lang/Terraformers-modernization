import { useEffect, useMemo, useState } from 'react';
import api from '../utils/api';

function flattenNodeCount(nodes = []) {
  return nodes.reduce((count, node) => count + 1 + flattenNodeCount(node.children || []), 0);
}

function nodeIcon(type) {
  if (type === 'project') {
    return '▣';
  }
  if (type === 'folder') {
    return '▸';
  }
  return '•';
}

function nodeSubtitle(node) {
  if (node.resultObjectKey) {
    return node.resultObjectKey;
  }
  if (node.sourceBucket && node.sourceKey) {
    return `s3://${node.sourceBucket}/${node.sourceKey}`;
  }
  if (node.apiPath) {
    return node.apiPath;
  }
  return '';
}

function ProjectTreeNode({ node, depth = 0, onFileClick }) {
  const isFile = node.type === 'file' || node.type === 'tfstate';
  const subtitle = nodeSubtitle(node);

  return (
    <li className={`project-tree-node project-tree-node-${node.type || 'unknown'}`}>
      <button
        type="button"
        className={isFile ? 'project-tree-node-button clickable' : 'project-tree-node-button'}
        style={{ paddingLeft: `${depth * 14 + 10}px` }}
        onClick={() => {
          if (isFile) {
            onFileClick(node);
          }
        }}
        disabled={!isFile}
      >
        <span className="project-tree-node-icon" aria-hidden="true">{nodeIcon(node.type)}</span>
        <span className="project-tree-node-main">
          <span className="project-tree-node-name">{node.name}</span>
          {subtitle && <span className="project-tree-node-subtitle">{subtitle}</span>}
        </span>
      </button>
      {Array.isArray(node.children) && node.children.length > 0 && (
        <ul className="project-tree-children">
          {node.children.map((child) => (
            <ProjectTreeNode key={child.id} node={child} depth={depth + 1} onFileClick={onFileClick} />
          ))}
        </ul>
      )}
    </li>
  );
}

function normalizeTreeResponse(data, selectedProjectId) {
  if (!data) {
    return { roots: [], metadata: null };
  }

  if (Array.isArray(data)) {
    return { roots: data, metadata: null };
  }

  return {
    roots: Array.isArray(data.tree) ? data.tree : [],
    metadata: {
      projectId: data.projectId || selectedProjectId,
      displayName: data.displayName,
      visibility: data.visibility,
      latestAnalysisJobId: data.latestAnalysisJobId,
      latestResultObjectKey: data.latestResultObjectKey,
      updatedAt: data.updatedAt,
    },
  };
}

function previewContentFromResponse(data) {
  if (typeof data === 'string') {
    return data;
  }
  if (typeof data?.content === 'string') {
    return data.content;
  }
  if (typeof data?.resultPreview === 'string') {
    return data.resultPreview;
  }
  return JSON.stringify(data, null, 2);
}

function ProjectTreeReadOnly({ selectedProjectId, refreshToken = 0 }) {
  const [treeState, setTreeState] = useState({ roots: [], metadata: null });
  const [selectedNode, setSelectedNode] = useState(null);
  const [filePreview, setFilePreview] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [sourceImageUrl, setSourceImageUrl] = useState('');
  const [terraformContent, setTerraformContent] = useState('');

  const nodeCount = useMemo(() => flattenNodeCount(treeState.roots), [treeState.roots]);

  useEffect(() => {
    let isMounted = true;

    const loadTree = async () => {
      setIsLoading(true);
      setError('');
      if (sourceImageUrl) { URL.revokeObjectURL(sourceImageUrl); setSourceImageUrl(''); }
      setTerraformContent('');
      try {
        const path = selectedProjectId
          ? `/api/project-tree/${encodeURIComponent(selectedProjectId)}`
          : '/api/project-tree';
        const response = await api.get(path);
        if (isMounted) {
          const normalized = normalizeTreeResponse(response.data, selectedProjectId);
          setTreeState(normalized);
          const pid = normalized.metadata?.projectId || selectedProjectId;
          if (pid) {
            api.get(`/api/projects/${encodeURIComponent(pid)}/source-image`, { responseType: 'blob' })
              .then((imageResponse) => { if (isMounted) setSourceImageUrl(URL.createObjectURL(imageResponse.data)); })
              .catch(() => {});
            api.get(`/api/projects/${encodeURIComponent(pid)}/terraform/main.tf`)
              .then((draftResponse) => { if (isMounted) setTerraformContent(draftResponse.data?.content || ''); })
              .catch(() => {});
          }
        }
      } catch (loadError) {
        if (isMounted) {
          setError(loadError?.response?.status === 404
            ? '프로젝트 트리를 찾을 수 없습니다.'
            : loadError?.message || '프로젝트 트리 조회에 실패했습니다.');
          setTreeState({ roots: [], metadata: null });
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    };

    loadTree();

    return () => {
      isMounted = false;
      if (sourceImageUrl) URL.revokeObjectURL(sourceImageUrl);
    };
  }, [selectedProjectId, refreshToken]);

  const handleFileClick = async (node) => {
    setSelectedNode(node);
    setFilePreview(null);

    if (!node.apiPath) {
      setFilePreview('이 노드는 아직 읽기 API가 연결되어 있지 않습니다.');
      return;
    }

    try {
      const response = await api.get(node.apiPath);
      setFilePreview(previewContentFromResponse(response.data));
    } catch (previewError) {
      setFilePreview(`파일 미리보기 조회 실패: ${previewError?.message || 'unknown error'}`);
    }
  };

  return (
    <section className="project-tree-panel" aria-label="Read-only project tree">
      <div className="panel-heading">
        <div>
          <p className="eyebrow">Project tree</p>
          <h2>Read-only project structure</h2>
        </div>
        <span className="project-tree-count">{isLoading ? 'loading' : `${nodeCount} nodes`}</span>
      </div>

      <p className="muted-copy">
        업로드된 프로젝트의 source 참조와 최신 Terraform draft를 읽기 전용 트리로 표시합니다.
        원본 이미지, 분석 결과와 전체 Terraform draft를 표시합니다. 삭제는 프로젝트 목록에서 가능합니다.
      </p>

      {treeState.metadata && (
        <dl className="project-tree-metadata">
          <div>
            <dt>Project</dt>
            <dd>{treeState.metadata.displayName || treeState.metadata.projectId}</dd>
          </div>
          <div>
            <dt>Visibility</dt>
            <dd>{treeState.metadata.visibility}</dd>
          </div>
          <div>
            <dt>Latest job</dt>
            <dd>{treeState.metadata.latestAnalysisJobId || '-'}</dd>
          </div>
        </dl>
      )}

      {sourceImageUrl && <section><h3>Original architecture image</h3><img src={sourceImageUrl} alt="Persisted architecture" className="project-source-image" /></section>}

      {error && <p className="project-tree-error">{error}</p>}

      {!error && treeState.roots.length === 0 && !isLoading && (
        <p className="project-tree-empty">아직 표시할 프로젝트가 없습니다. 이미지를 업로드하면 트리가 생성됩니다.</p>
      )}

      {treeState.roots.length > 0 && (
        <ul className="project-tree-list">
          {treeState.roots.map((root) => (
            <ProjectTreeNode key={root.id} node={root} onFileClick={handleFileClick} />
          ))}
        </ul>
      )}

      {treeState.metadata && (
        <section className="analysis-result-panel">
          <h3>Full terraform/main.tf</h3>
          {terraformContent ? <pre><code>{terraformContent}</code></pre> : <p>Terraform draft is not available yet.</p>}
        </section>
      )}

      {selectedNode && (
        <aside className="project-tree-preview">
          <h3>{selectedNode.name}</h3>
          <p>{selectedNode.apiPath || 'No preview API path'}</p>
          {filePreview && <pre>{filePreview}</pre>}
        </aside>
      )}
    </section>
  );
}

export default ProjectTreeReadOnly;
