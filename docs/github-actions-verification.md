# GitHub Actions Verification

## 1. Purpose

Local verification should be minimized when the developer workstation is slow or low on disk space.

The repository now provides manual GitHub Actions workflows for the same baseline checks that were previously run locally.

## 2. Manual-only workflows

The workflows are intentionally `workflow_dispatch` only. They do not run on every push or pull request yet.

Reason:

- the repository is still in a baseline construction phase;
- repeated automatic red checks can make the project look broken while contracts are still being stabilized;
- local disk and CPU pressure should not block verification;
- manual runs keep validation evidence explicit.

## 3. Workflows

```text
.github/workflows/backend-local-verification.yml
.github/workflows/frontend-import-verification.yml
.github/workflows/runtime-contract-verification.yml
```

### Backend Local Verification

Runs:

```bash
bash scripts/checks/backend-local-verification.sh
```

This verifies the Maven/local backend baseline without requiring Docker image validation.

### Frontend Import Verification

Runs:

```bash
bash scripts/checks/frontend-import-verification.sh
```

This verifies the selected original frontend import and upload/analysis UI build.

### Runtime Contract Verification

Runs:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

This verifies Kubernetes base rendering and Terraform runtime-contract validation on a GitHub-hosted runner with Terraform and kubectl prepared by the workflow.

## 4. Local workstation policy

When the local environment is slow or disk constrained, prefer this pattern:

```bash
git pull --ff-only origin main
git status --short
```

Do not repeatedly run heavy local checks unless browser behavior must be inspected.

Local cleanup when needed:

```bash
rm -rf frontend/node_modules
rm -rf frontend/build
rm -rf backend/target
rm -rf ~/.npm/_cacache
```

Keep `frontend/package-lock.json` unless it is known to be stale and will be regenerated intentionally.

## 5. Next validation order

1. Run Frontend Import Verification in GitHub Actions.
2. Run Backend Local Verification in GitHub Actions.
3. Run Runtime Contract Verification in GitHub Actions.
4. Use local browser smoke only after the Actions baseline is green.

## 6. Portfolio explanation

```text
로컬 장비의 자원 제약 때문에 검증을 생략한 것이 아니라, 반복 빌드와 테스트를 GitHub Actions의 수동 실행 workflow로 옮겨 검증 기준을 유지했습니다. 백엔드, 프론트 import, Kubernetes/Terraform runtime contract를 각각 분리해 실행할 수 있게 하여, 실패 범위를 명확히 구분하고 로컬 환경 의존성을 줄였습니다.
```
