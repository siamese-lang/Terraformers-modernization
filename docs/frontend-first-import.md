# Frontend First Import Pass

## 1. Scope

This pass imports the first public-safe slice of the original Terraformers frontend from:

```text
siamese-lang/rdb-refactor/app/Terraformers-main/frontend
```

This is not a new demo screen and it is not the full frontend import yet.

The goal of this pass is to make the original routing/auth/API foundation buildable before importing the larger `AiChat`, upload, project tree, editor, public project, and comment UI surface.

## 2. Imported now

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

## 3. Source-derived behavior

The original route map was:

```text
/                -> AiChat
/login           -> EntryPage
/confirm-sign-up -> ConfirmSignUpPage
/home            -> AppLayoutPreview
```

In this pass:

- `/login` is wired to the imported auth page;
- `/confirm-sign-up` is wired to the imported confirmation page;
- `/` temporarily documents the import boundary because `AiChat` is intentionally deferred to the next pass;
- `/home` is not imported because `AppLayoutPreview` / board UI is secondary to the Terraformers upload/project-tree flow.

## 4. Public-safe Cognito handling

The original `src/index.js` imported `src/aws-exports`, which must not be copied into the public modernization repository with real environment values.

This pass replaces that with:

```text
frontend/src/awsConfig.js
frontend/.env.example
```

Real Cognito values, if used locally later, must be placed in an uncommitted `.env.local`.

## 5. Stabilizations made during import

- The package build script uses `react-scripts build`, not shell-specific `CI=false react-scripts build`.
- `ConfirmSignUpPage` navigates to `/login`, matching the actual route map.
- `EntryPage` initializes `username` in local state to avoid uncontrolled input behavior.
- Auth failures log only error name/message, not token or account-specific values.

## 6. Not imported yet

```text
AiChat.js
Dropzone.js
Modal.js
ProjectTree.js
Monaco editor rendering
Image/assets required by selected components
Project tree/editor endpoints
Public projects/comments
Terraform run/destroy/tfstate controls
AWS credential settings behavior
AppLayoutPreview / BoardContainer / board API
```

## 7. Local verification

Run from the repository root:

```bash
bash scripts/checks/frontend-import-verification.sh
```

Expected result:

```text
[frontend] selected import verification completed
```

If this build fails, fix the import/build boundary before importing `AiChat` or `ProjectTree`.

## 8. Next pass

Next import pass should focus on:

1. `AiChat.js`;
2. `Dropzone.js`;
3. `Modal.js`;
4. upload-related assets;
5. replacing legacy `/api/bedrock/logs?queueUrl=...` browser polling with an analysis-job status/result contract.

Do not activate Terraform run/destroy/tfstate controls until real backend contracts exist.
