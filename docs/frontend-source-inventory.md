# Original Frontend Source Inventory

## 1. Purpose

This document records the source inventory for selectively importing the original Terraformers frontend from the previous private repository.

The goal is not to create a new frontend or a separate demo page. The goal is to preserve the original team-project service flow where it is valid, while adapting backend contracts only where implementation is justified.

Source repository inspected through the GitHub connector:

```text
siamese-lang/rdb-refactor
app/Terraformers-main/frontend
```

Target repository:

```text
siamese-lang/Terraformers-modernization
```

## 2. Confirmed application shape

The original frontend is a Create React App application. The package manifest uses React 18, React Router, AWS Amplify, Axios, Cloudscape, Monaco Editor, react-dropzone, react-arborist, SweetAlert2, and related UI/runtime libraries.

Confirmed routes:

```text
/                -> AiChat
/login           -> EntryPage
/confirm-sign-up -> ConfirmSignUpPage
/home            -> AppLayoutPreview
```

The route map shows that the chat-style main screen is the primary entry point, while login and confirmation are separate routes.

## 3. Source groups

### 3.1 Required build files

Candidate import:

```text
app/Terraformers-main/frontend/package.json
app/Terraformers-main/frontend/public/*
app/Terraformers-main/frontend/src/index.js
app/Terraformers-main/frontend/src/App.js
app/Terraformers-main/frontend/src/index.css
app/Terraformers-main/frontend/src/styles/*
```

Exclude:

```text
node_modules/
build/
.env*
aws-exports.js
aws-exports*.js unless verified as fake test-only content
old frontend deployment workflows
old private repository history
```

### 3.2 Auth and routing

Candidate import:

```text
src/App.js
src/components/EntryPage.js
src/components/ConfirmSignUpPage.js
src/utils/api.js
```

Observed behavior:

- `EntryPage` uses Amplify `signUp`, `signIn`, `signOut`, `resetPassword`, and `fetchAuthSession`.
- Sign-up redirects to `/confirm-sign-up`.
- Sign-in navigates to `/` after an access token is present.
- `ConfirmSignUpPage` confirms the account by email and confirmation code.

Required stabilization:

- Verify actual route after confirmation. The current code navigates to `/logIn`, but the route map uses `/login`.
- Replace hard failure behavior with clear local/demo-auth mode if Cognito is not yet configured.
- Do not commit real Cognito values.

### 3.3 API wrapper

Candidate import:

```text
src/utils/api.js
```

Observed behavior:

- resolves `REACT_APP_API_BASE_URL`, with development fallback to `http://localhost:8080`;
- obtains tokens through Amplify `fetchAuthSession`;
- attaches `Authorization: Bearer <token>` when available;
- redirects to `/login` when authenticated API calls lack a token;
- treats selected public endpoints as auth-optional.

Required stabilization:

- Keep the wrapper, but align optional/auth-required paths with the modernization backend.
- Do not expose token values in logs or screenshots.
- Use `.env.example` rather than committed environment-specific configuration.

### 3.4 Upload and analysis flow

Candidate import:

```text
src/components/AiChat.js
src/components/Dropzone.js
src/components/Modal.js
src/utils/eventBus.js
src/utils/chatSupport.js
src/assets/imageupload.svg
src/assets/terraformers.png
src/assets/user.png
src/assets/code.png
```

Observed behavior:

- `Dropzone` accepts PNG/JPEG files.
- Upload calls `POST /api/upload` with multipart form data.
- The response is expected to include image/project metadata.
- If a queue URL is returned, the frontend polls `GET /api/bedrock/logs?queueUrl=...&projectId=...`.
- `AiChat` listens for Bedrock result events and renders Terraform code in Monaco Editor.
- Text-only chat is already treated as unsupported through `buildUnsupportedTextChatMessage`.

Decision:

- Do not remove the upload UI.
- Replace legacy queue URL browser polling with analysis-job status/result polling, or implement a compatibility backend endpoint that hides queue URL details from the browser.
- Keep text-only chat unsupported; do not add a fake `/api/chat` endpoint.

### 3.5 Project tree and editor flow

Candidate import:

```text
src/components/ProjectTree.js
src/utils/visibility.js
project/tree/editor-related assets
```

Observed behavior:

The tree UI expects these endpoint groups:

```text
GET  /api/project-tree
GET  /api/project-tree/{projectId}
POST /api/projects/{projectId}/files
POST /api/createFolder
PUT  /api/rename-node
DELETE /api/deleteNode
GET  /api/terraform-code/{fileId}
POST /api/update-terraform-code/{fileId}
POST /api/updateProjectVisible
POST /api/terraform/run/{projectId}
GET  /api/terraform/logs?queueUrl=...&projectId=...
POST /api/terraform/destroy/{projectId}
GET  /api/terraform/tfstate/{projectId}
```

Decision:

- Project tree, visibility, and stored Terraform draft read/update are valid product flows.
- Terraform run/destroy/tfstate are deferred until real execution/state integration exists.
- Run/destroy buttons must not be left as active controls unless backed by real contracts.

### 3.6 Public projects and comments

Candidate import:

```text
src/components/AiChat.js
src/components/ProjectTree.js
public-project/comment UI sections
```

Observed behavior:

Expected endpoints:

```text
GET  /api/public-projects
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
GET  /api/getProjectInfrastructureImage/{projectId}
```

Decision:

- Keep as backend contract candidates.
- Implement after project metadata and visibility are modeled.
- Do not remove only because the current backend lacks these endpoints.

### 3.7 Board/AppLayout path

Candidate status:

```text
src/components/AppLayoutPreview.js
src/components/BoardContainer.js
src/api/board.js
```

Observed behavior:

- AppLayoutPreview uses a Cloudscape layout and board item navigation.
- `src/api/board.js` calls `/api/board` with cookie-based credentials.

Decision:

- Treat this as secondary or legacy UI unless it is needed for the final Terraformers flow.
- Do not import it in the first pass unless required by routing/build.
- Prefer AiChat/upload/project-tree flow as the main product path.

### 3.8 Settings and runtime configuration

Candidate status:

The original settings screen accepts browser-entered AWS credentials through:

```text
POST /api/update-aws-credentials
GET  /api/aws-credentials
```

Decision:

- Do not import this behavior as-is.
- Replace it with a runtime configuration status page later, or keep settings disabled until a safe contract exists.
- Browser-provided cloud key storage conflicts with the modernization direction of runtime-managed secrets/configuration.

### 3.9 Assets

The original frontend imports many image assets from `src/assets`.

Import policy:

- import assets needed for build only after each referencing component is selected;
- skip unused assets;
- if a binary asset is missing or not suitable for public import, replace it with a neutral placeholder and document the substitution;
- do not import screenshots or files that may contain account-specific or environment-specific information.

## 4. First import pass

Recommended first source import pass:

```text
package.json
public/index.html
src/index.js
src/App.js
src/utils/api.js
src/utils/eventBus.js
src/utils/chatSupport.js
src/utils/visibility.js
src/components/AiChat.js
src/components/Dropzone.js
src/components/Modal.js
src/components/ProjectTree.js
src/components/EntryPage.js
src/components/ConfirmSignUpPage.js
minimum styles required for build
minimum assets required by selected components
```

Do not include in first pass:

```text
AppLayoutPreview.js
BoardContainer.js
src/api/board.js
Terraform run/destroy/tfstate active behavior
AWS credential settings behavior
old deployment workflows
```

## 5. Backend contract work created by import

After first import, backend work should proceed in this order:

1. Project metadata model.
2. Upload compatibility endpoint or frontend upload-to-analysis adaptation.
3. Analysis job status/result polling bridge.
4. Project tree read endpoint.
5. Stored Terraform draft read/update endpoint.
6. Public project list and visibility update.
7. Public project comments.

Deferred:

- Terraform run/destroy/tfstate;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- browser-provided cloud key storage.

## 6. Local import rule

The user does not need to clone `rdb-refactor` locally. Source inspection and selective import should be performed through the GitHub connector, and the user should only keep the current `Terraformers-modernization` working copy locally.
