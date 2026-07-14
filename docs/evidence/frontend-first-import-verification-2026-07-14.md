# Frontend First Import Verification - 2026-07-14

## 1. Scope

The first original frontend import pass was verified locally after pulling the latest `main` branch.

This verification covers the selected public-safe frontend foundation only:

```text
frontend/package.json
frontend/public/index.html
frontend/src/index.js
frontend/src/App.js
frontend/src/awsConfig.js
frontend/src/components/EntryPage.js
frontend/src/components/ConfirmSignUpPage.js
frontend/src/utils/api.js
frontend/src/utils/eventBus.js
frontend/src/utils/chatSupport.js
frontend/src/utils/visibility.js
frontend/src/index.css
frontend/src/styles/login.css
frontend/.env.example
scripts/checks/frontend-import-verification.sh
```

It does not claim that the full legacy UI has been imported.

## 2. Command

Run from the repository root:

```bash
bash scripts/checks/frontend-import-verification.sh
```

## 3. Reported local result

The user reported that the verification completed successfully after resolving stale local files from the previous temporary browser smoke screen.

Expected terminal completion line:

```text
[frontend] selected import verification completed
```

## 4. Meaning

This confirms that the first selected slice of the original Terraformers frontend is buildable in the local environment.

The verified scope includes:

- Create React App package/build foundation;
- original route/auth foundation;
- public-safe Cognito configuration replacement through `.env.example` and `awsConfig.js`;
- imported `EntryPage` and `ConfirmSignUpPage` auth routes;
- imported API/event/visibility/chat helper utilities.

## 5. Limitations

The following are intentionally not verified by this evidence:

- original `AiChat` import;
- original `Dropzone` import;
- upload-to-analysis browser flow;
- Monaco editor rendering;
- project tree/editor behavior;
- public projects/comments;
- real Cognito authentication;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- Terraform run/destroy/tfstate behavior.

These belong to later frontend/backend contract passes.
