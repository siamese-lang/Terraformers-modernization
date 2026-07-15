import { useEffect, useRef, useState } from 'react';
import Modal from './Modal';
import Dropzone from './Dropzone';
import ProjectTreeReadOnly from './ProjectTreeReadOnly';
import PublicProjectsReadOnly from './PublicProjectsReadOnly';
import { eventBus } from '../utils/eventBus';
import { buildUnsupportedTextChatMessage } from '../utils/chatSupport';

const initialMessages = [
  {
    key: 'intro',
    type: 'terraform_result',
    explanation: '아키텍처 이미지를 업로드하면 원본 Terraformers 업로드 흐름을 거쳐 analysis job과 프로젝트 트리를 생성합니다.',
    terraformCode: '',
    isUser: false,
  },
];

function ChatItem({ item }) {
  if (item.type === 'user_image') {
    return (
      <article className="chat-item chat-item-user">
        <div className="chat-bubble" dangerouslySetInnerHTML={{ __html: item.text }} />
      </article>
    );
  }

  if (item.type === 'terraform_result') {
    return (
      <article className="chat-item chat-item-system">
        <div className="chat-avatar">T</div>
        <div className="chat-bubble">
          <p>{item.explanation}</p>
          {item.terraformCode && <pre className="terraform-code"><code>{item.terraformCode}</code></pre>}
        </div>
      </article>
    );
  }

  return (
    <article className="chat-item chat-item-user">
      <div className="chat-bubble">{item.text}</div>
    </article>
  );
}

function AnalysisLogPanel({ logs, isRunning }) {
  if (!isRunning && logs.length === 0) {
    return null;
  }

  return (
    <section className="analysis-log-panel">
      <div className="panel-heading">
        <h2>Analysis logs</h2>
        <span className={isRunning ? 'status-running' : 'status-complete'}>{isRunning ? 'running' : 'complete'}</span>
      </div>
      <pre>{logs.join('\n')}</pre>
    </section>
  );
}

function AiChat() {
  const [messages, setMessages] = useState(initialMessages);
  const [logs, setLogs] = useState([]);
  const [inputText, setInputText] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedProjectId, setSelectedProjectId] = useState('');
  const [projectTreeRefresh, setProjectTreeRefresh] = useState(0);
  const chatEndRef = useRef(null);

  useEffect(() => {
    const onStart = () => {
      setLogs([]);
      setIsRunning(true);
    };

    const onLogs = (nextLogs = []) => {
      setLogs((previous) => [...previous, ...nextLogs]);
    };

    const onResult = (result) => {
      setMessages((previous) => previous.map((item) => {
        if (item.type === 'terraform_result' && item.explanation === 'AI가 답변을 생성 중입니다...') {
          return {
            ...item,
            explanation: result.explanation,
            terraformCode: result.terraformCode,
            projectId: result.projectId,
          };
        }
        return item;
      }));

      if (result.projectId) {
        setSelectedProjectId(result.projectId);
        setProjectTreeRefresh((previous) => previous + 1);
      }
    };

    const onComplete = () => {
      setIsRunning(false);
    };

    const onError = (error) => {
      setIsRunning(false);
      setLogs((previous) => [...previous, `Error: ${error}`]);
      setMessages((previous) => previous.map((item) => {
        if (item.type === 'terraform_result' && item.explanation === 'AI가 답변을 생성 중입니다...') {
          return {
            ...item,
            explanation: `분석 작업 중 오류가 발생했습니다: ${error}`,
            terraformCode: '',
          };
        }
        return item;
      }));
    };

    eventBus.on('bedrock:start', onStart);
    eventBus.on('bedrock:logs', onLogs);
    eventBus.on('bedrock:result', onResult);
    eventBus.on('bedrock:complete', onComplete);
    eventBus.on('bedrock:error', onError);

    return () => {
      eventBus.off('bedrock:start', onStart);
      eventBus.off('bedrock:logs', onLogs);
      eventBus.off('bedrock:result', onResult);
      eventBus.off('bedrock:complete', onComplete);
      eventBus.off('bedrock:error', onError);
    };
  }, []);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, logs]);

  const sendText = () => {
    if (!inputText.trim()) {
      return;
    }

    setMessages((previous) => [
      ...previous,
      {
        key: `text-${Date.now()}`,
        text: inputText,
        isUser: true,
      },
      buildUnsupportedTextChatMessage(),
    ]);
    setInputText('');
  };

  const selectPublicProject = (project) => {
    const nextProjectId = project.projectId || project.id;
    if (!nextProjectId) {
      return;
    }
    setSelectedProjectId(nextProjectId);
    setProjectTreeRefresh((previous) => previous + 1);
  };

  return (
    <main className="terraformers-chat-shell">
      <aside className="terraformers-sidebar">
        <div className="logo-mark">T</div>
        <h1>Terraformers</h1>
        <p>Architecture image to Terraform draft</p>
        <nav className="sidebar-nav" aria-label="Frontend import status">
          <span className="active">Chat / Upload</span>
          <span className="active">Project Tree - read-only</span>
          <span className="active">Public Projects - read-only</span>
          <span className="disabled">Runtime Config - safe replacement pending</span>
        </nav>
      </aside>

      <section className="chat-main">
        <header className="chat-header">
          <div>
            <p className="eyebrow">Original frontend import pass 4</p>
            <h2>Image upload, public projects, and project tree</h2>
          </div>
          <button type="button" className="primary-button" onClick={() => setIsModalOpen(true)}>
            이미지 업로드
          </button>
        </header>

        <section className="chat-workspace">
          <section className="chat-list" aria-live="polite">
            {messages.map((item) => <ChatItem item={item} key={item.key} />)}
            <AnalysisLogPanel logs={logs} isRunning={isRunning} />
            <div ref={chatEndRef} />
          </section>

          <section className="right-inspector-column" aria-label="Project inspectors">
            <PublicProjectsReadOnly selectedProjectId={selectedProjectId} onSelectProject={selectPublicProject} />
            <ProjectTreeReadOnly selectedProjectId={selectedProjectId} refreshToken={projectTreeRefresh} />
          </section>
        </section>

        <section className="chat-input-row">
          <textarea
            value={inputText}
            onChange={(event) => setInputText(event.target.value)}
            placeholder="텍스트 기반 Terraform 생성은 아직 지원하지 않습니다. 이미지 업로드를 사용하세요."
          />
          <button type="button" className="secondary-button" onClick={sendText}>전송</button>
        </section>
      </section>

      <Modal isModalOpen={isModalOpen} closeModal={() => setIsModalOpen(false)}>
        <Dropzone closeModal={() => setIsModalOpen(false)} setDataMain={setMessages} />
      </Modal>
    </main>
  );
}

export default AiChat;
