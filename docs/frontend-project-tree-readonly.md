# Frontend Read-only Project Tree Import

## 1. Purpose

This pass connects the frontend to the backend project tree contract without importing the original `ProjectTree.js` wholesale.

The original component mixed tree rendering with Terraform run/destroy, rename, delete, create folder/file, tfstate access, visibility toggles, and SweetAlert flows. Importing it unchanged would activate API calls that are not implemented yet.

This pass preserves the product direction while keeping behavior honest and bounded.

## 2. Imported behavior

The frontend now shows a read-only project tree beside the chat/upload flow:

```text
image upload
  -> POST /api/upload
  -> analysis job result
  -> selected projectId
  -> GET /api/project-tree/{projectId}
  -> render source and terraform nodes
```

When no project has been selected yet, the component calls:

```text
GET /api/project-tree
```

This allows the UI to show any existing project roots after backend data exists.

## 3. Read-only node model

The component renders backend nodes with these fields when present:

```text
id
name
type
projectId
children
apiPath
sourceBucket
sourceKey
resultObjectKey
```

Current tree shape:

```text
project root
├── source
│   └── uploaded image metadata node
└── terraform
    └── main.tf latest result node
```

Clicking `main.tf` follows the node `apiPath`, which currently points to:

```text
/api/analysis/jobs/{latestAnalysisJobId}
```

The UI displays `resultPreview` as the Terraform draft preview.

## 4. Explicit exclusions

The following original `ProjectTree.js` behaviors are intentionally not active:

```text
Terraform run
Terraform destroy
tfstate polling
rename node
create file/folder
delete node
edit Terraform draft
browser cloud credential settings
```

These are backend contract work, not frontend-only cleanup work.

## 5. Verification

Run through GitHub Actions:

```text
Frontend Import Verification
Backend Local Verification
```

The frontend build verifies that the read-only tree component compiles. Backend tests verify that `GET /api/project-tree` and `GET /api/project-tree/{projectId}` return the expected project/source/terraform nodes.

## 6. Portfolio explanation

```text
원본 Terraformers의 프로젝트 트리 UI는 단순 조회뿐 아니라 Terraform 실행, 삭제, 파일 생성, 이름 변경까지 한 컴포넌트에 섞여 있었습니다. 현재 백엔드 계약이 준비되지 않은 기능을 화면에 그대로 노출하면 포트폴리오가 과장되어 보일 수 있으므로, 먼저 읽기 전용 Project Tree를 선별 이관했습니다. 업로드 후 생성된 프로젝트 메타데이터와 최신 분석 결과를 기반으로 source 노드와 main.tf 노드를 표시하고, main.tf 클릭 시 analysis job의 Terraform preview를 조회하도록 연결했습니다.
```
