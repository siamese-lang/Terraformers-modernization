import { useEffect, useRef, useState } from 'react';
import Modal from './Modal';
import Dropzone from './Dropzone';
import { eventBus } from '../utils/eventBus';
import { buildUnsupportedTextChatMessage } from '../utils/chatSupport';

const initialMessages = [
  {
    key: 'intro',
    type: 'terraform_result',
    explanation: '아키텍처 이미지를 업로드하면 분석 작업과 프로젝트를 생성하고 Terraform 초안을 표시합니다.',
    terraformCode: '',
    isUser: false,
  },
];

function ChatItem({ item }) {
  if (item.type === 'user_image') {
    return (
      <article className="chat-item chat-item-user">
        <div className="chat-bubble">
          <img src={item.imageUrl} alt={item.alt || 'uploaded architecture'} className="chat-upload-preview" />
        </div>
      </article>
    );
  }

  if (item.type === 'terraform_result') {
    return (
      <article className="chat-item chat-item-system">
        <div className="chat-avatar">T</div>
        <div className="chat-bubble">
          <p>{item.explanation}</p>
          {item.components?.length > 0 && <p><strong>Components:</strong> {item.components.join(', ')}</p>}
          {item.relationships?.length > 0 && <p><strong>Relationships:</strong> {item.relationships.join('; ')}</p>}
          {item.warnings?.length > 0 && <p><strong>Warnings:</strong> {item.warnings.join('; ')}</p>}
          {item.projectId && (
            <p className="result-project-reference">
              프로젝트 #{item.projectId}가 내 프로젝트에 저장되었습니다.
            </p>
          )}
          {item.terraformCode && (
            <pre className="terraform-code">
              <code>{item.terraformCode}</code>
            </pre>
          )}
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
        <h2>분석 로그</h2>
        <span className={isRunning ? 'status-running' : 'status-complete'}>
          {isRunning ? '진행 중' : '완료'}
        </span>
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
  const chatEndRef = useRef(null);
  const objectUrlsRef = useRef(new Set());

  useEffect(() => {
    const onStart = () => {
      setLogs([]);
      setIsRunning(true);
    };

    const onLogs = (nextLogs = []) => {
      setLogs((previous) => [...previous, ...nextLogs]);
    };

    const onImage = (image) => {
      if (image.imageUrl) {
        objectUrlsRef.current.add(image.imageUrl);
      }
      setMessages((previous) => [
        ...previous,
        {
          key: `persisted-image-${image.projectId}-${Date.now()}`,
          type: 'user_image',
          imageUrl: image.imageUrl,
          alt: image.alt || 'uploaded architecture',
          isUser: true,
        },
      ]);
    };

    const onResult = (result) => {
      setMessages((previous) => previous.map((item) => {
        if (
          item.type === 'terraform_result'
          && item.explanation === 'AI가 답변을 생성 중입니다...'
        ) {
          return {
            ...item,
            explanation: result.explanation,
            terraformCode: result.terraformCode,
            projectId: result.projectId,
            components: result.components || [],
            relationships: result.relationships || [],
            warnings: result.warnings || [],
          };
        }

        return item;
      }));
    };

    const onComplete = () => {
      setIsRunning(false);
    };

    const onError = (error) => {
      setIsRunning(false);
      setLogs((previous) => [...previous, `Error: ${error}`]);
      setMessages((previous) => previous.map((item) => {
        if (
          item.type === 'terraform_result'
          && item.explanation === 'AI가 답변을 생성 중입니다...'
        ) {
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
    eventBus.on('bedrock:image', onImage);
    eventBus.on('bedrock:result', onResult);
    eventBus.on('bedrock:complete', onComplete);
    eventBus.on('bedrock:error', onError);

    return () => {
      eventBus.off('bedrock:start', onStart);
      eventBus.off('bedrock:logs', onLogs);
      eventBus.off('bedrock:image', onImage);
      eventBus.off('bedrock:result', onResult);
      eventBus.off('bedrock:complete', onComplete);
      eventBus.off('bedrock:error', onError);
    };
  }, []);

  useEffect(() => () => {
    objectUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    objectUrlsRef.current.clear();
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

  return (
    <section className="page-stack generate-page">
      <header className="page-header">
        <div>
          <p className="eyebrow">Generate</p>
          <h1>새 Terraform 초안 만들기</h1>
          <p>아키텍처 이미지를 업로드해 구성요소와 연결 관계를 분석합니다.</p>
        </div>
        <button
          type="button"
          className="primary-button"
          onClick={() => setIsModalOpen(true)}
        >
          이미지 업로드
        </button>
      </header>

      <section className="generate-workspace">
        <section className="generate-chat-list" aria-live="polite">
          {messages.map((item) => (
            <ChatItem item={item} key={item.key} />
          ))}
          <AnalysisLogPanel logs={logs} isRunning={isRunning} />
          <div ref={chatEndRef} />
        </section>

        <section className="chat-input-row">
          <textarea
            value={inputText}
            onChange={(event) => setInputText(event.target.value)}
            placeholder="텍스트 기반 Terraform 생성은 아직 지원하지 않습니다. 이미지 업로드를 사용하세요."
          />
          <button
            type="button"
            className="secondary-button"
            onClick={sendText}
          >
            전송
          </button>
        </section>
      </section>

      <Modal
        isModalOpen={isModalOpen}
        closeModal={() => setIsModalOpen(false)}
      >
        <Dropzone
          closeModal={() => setIsModalOpen(false)}
          setDataMain={setMessages}
        />
      </Modal>
    </section>
  );
}

export default AiChat;
