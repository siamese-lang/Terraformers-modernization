# Backend Terraform Draft Contract

## 1. Purpose

The upload and analysis flow originally returned a Terraform preview directly from the analysis job response.

That is not enough for project-oriented behavior because later frontend features need a stable project file path for `main.tf`.

This pass introduces a project-scoped stored draft contract:

```text
project
  -> terraform
     -> main.tf
```

## 2. Current storage model

`ProjectEntity` now stores:

```text
terraformDraft
terraformDraftUpdatedAt
latestAnalysisJobId
latestResultObjectKey
```

When `POST /api/upload` succeeds, the analysis result preview is copied into the project draft:

```text
POST /api/upload
  -> create analysis job
  -> upsert project metadata
  -> store resultPreview as project terraformDraft
```

This is still database-backed draft storage. It does not claim S3-backed Terraform file persistence yet.

## 3. Endpoints

### Read project main.tf

```text
GET /api/projects/{projectId}/terraform/main.tf
```

Response:

```json
{
  "projectId": "aws",
  "fileName": "main.tf",
  "contentType": "text/plain; charset=utf-8",
  "content": "terraform { ... }",
  "latestAnalysisJobId": "...",
  "latestResultObjectKey": "analysis-results/.../main.tf",
  "draftUpdatedAt": "...",
  "projectUpdatedAt": "..."
}
```

### Update project main.tf

```text
PUT /api/projects/{projectId}/terraform/main.tf
Content-Type: application/json

{"content":"resource \"aws_s3_bucket\" \"example\" {}"}
```

The update changes only the stored project draft content and `terraformDraftUpdatedAt`.

It does not update S3 object content, Terraform state, or infrastructure.

## 4. Project tree integration

The `main.tf` node in `GET /api/project-tree/{projectId}` now points to:

```text
/api/projects/{projectId}/terraform/main.tf
```

The frontend read-only project tree follows this `apiPath` and displays the response `content` as Terraform preview.

## 5. Verification

Covered by `TerraformDraftControllerTest`:

```text
POST /api/upload
  -> creates initial stored Terraform draft
GET /api/projects/{projectId}/terraform/main.tf
  -> returns stored draft content
PUT /api/projects/{projectId}/terraform/main.tf
  -> updates draft content
GET again
  -> returns updated content
missing project
  -> 404
```

`ProjectTreeControllerTest` also verifies that `main.tf` nodes point to the project draft endpoint rather than directly to the analysis job endpoint.

## 6. Explicit boundaries

Not implemented in this pass:

```text
S3-backed Terraform draft object writes
Terraform apply/run
Terraform destroy
tfstate read/write
multi-file Terraform tree
version history
collaborative editing
```

These remain separate backend contracts.

## 7. Portfolio explanation

```text
분석 결과를 일회성 응답으로만 보여주지 않고, 프로젝트 기준 main.tf 초안으로 저장하도록 백엔드 계약을 확장했습니다. 업로드 직후 생성된 resultPreview를 프로젝트 draft로 보존하고, 이후 GET/PUT /api/projects/{projectId}/terraform/main.tf를 통해 조회·수정할 수 있게 했습니다. 다만 이 단계는 DB 기반 초안 저장이며, 실제 S3 객체 갱신이나 Terraform 실행·상태 관리는 후속 작업으로 분리했습니다.
```
