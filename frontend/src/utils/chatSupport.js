export const UNSUPPORTED_TEXT_CHAT_MESSAGE = '현재 텍스트 기반 Terraform 생성은 지원되지 않습니다. 이미지 업로드를 사용해 주세요.';

export const buildUnsupportedTextChatMessage = () => ({
  key: Date.now() + 1,
  type: 'terraform_result',
  explanation: UNSUPPORTED_TEXT_CHAT_MESSAGE,
  terraformCode: '',
  isUser: false,
});
