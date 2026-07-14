# Backend Project Tree Contract

## 1. Purpose

The project tree contract prepares the backend for the original Terraformers `ProjectTree.js` flow without reintroducing unsupported Terraform execution, deletion, rename, or browser cloud-key behavior.

This pass is read-only.

## 2. Source frontend expectation

The original frontend tree used `react-arborist` and expected nodes with fields such as:

```text
id
name
type
projectId
parentId
children
apiPath
```

It also mixed many active controls into the same component, including Terraform run/destroy, visibility toggle, folder/file create, rename, and delete. Those controls remain deferred until backend contracts are explicitly implemented.

## 3. Endpoints

### List project root trees

```text
GET /api/project-tree
```

Returns a list of root project nodes.

### Get one project tree

```text
GET /api/project-tree/{projectId}
```

Returns:

```text
project metadata
+ tree root
  + source folder
    + uploaded image reference node
  + terraform folder
    + main.tf latest result node
```

Missing project returns `404`.

## 4. Current node shape

```json
{
  "id": "aws:terraform:main.tf",
  "name": "main.tf",
  "type": "file",
  "projectId": "aws",
  "parentId": "aws:terraform",
  "isLeaf": true,
  "apiPath": "/api/analysis/jobs/{jobId}",
  "resultObjectKey": "analysis-results/aws/.../main.tf",
  "children": []
}
```

## 5. Current tree structure

```text
project
├── source
│   └── <original image filename>
└── terraform
    └── main.tf
```

The source node is metadata-only in this pass. Real binary read/download remains future work.

The `main.tf` node points to the latest analysis job API path for now. A dedicated Terraform draft read/update API remains future work.

## 6. Verification

Covered by `ProjectTreeControllerTest`:

```text
POST /api/upload
  -> project metadata upserted
  -> GET /api/project-tree/{projectId}
  -> project root returned
  -> source folder and uploaded image node returned
  -> terraform folder and main.tf result node returned
  -> missing project returns 404
```

Run through GitHub Actions:

```text
Backend Local Verification
```

## 7. Portfolio explanation

```text
기존 Terraformers의 프로젝트 트리 화면을 그대로 복원하기 전에, 백엔드에서 프로젝트 단위 파일 구조를 읽기 전용 계약으로 먼저 정의했습니다. 업로드된 이미지 메타데이터와 최신 Terraform 초안 결과를 source/terraform 폴더 구조로 반환하여, 프론트가 프로젝트별 산출물을 탐색할 수 있는 기반을 만들었습니다. 단, Terraform 실행·삭제·파일 생성·이름 변경은 아직 실제 운영 계약이 없으므로 제외했습니다.
```
