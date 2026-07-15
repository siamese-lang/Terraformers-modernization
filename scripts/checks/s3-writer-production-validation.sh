#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/s3-writer-production-validation"
PORT="${PORT:-18080}"
PROJECT_ID="${PROJECT_ID:-s3-writer-validation-$(date -u +%Y%m%d%H%M%S)}"
S3_UPLOAD_PREFIX="${S3_UPLOAD_PREFIX:-terraformers-modernization-validation}"
CLEANUP_S3_OBJECT="${CLEANUP_S3_OBJECT:-true}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-2}}"

: "${S3_UPLOAD_BUCKET:?S3_UPLOAD_BUCKET is required}"

mkdir -p "${ARTIFACT_DIR}"
APP_LOG="${ARTIFACT_DIR}/backend.log"
UPLOAD_RESPONSE_JSON="${ARTIFACT_DIR}/upload-response.json"
HEAD_OBJECT_JSON="${ARTIFACT_DIR}/s3-head-object.json"
EVIDENCE_MD="${ARTIFACT_DIR}/s3-writer-production-validation.md"
PAYLOAD_FILE="${ARTIFACT_DIR}/validation-architecture.png"
APP_PID=""
SOURCE_BUCKET=""
SOURCE_KEY=""

cleanup() {
  if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" >/dev/null 2>&1; then
    kill "${APP_PID}" >/dev/null 2>&1 || true
    wait "${APP_PID}" >/dev/null 2>&1 || true
  fi

  if [[ "${CLEANUP_S3_OBJECT}" == "true" && -n "${SOURCE_BUCKET}" && -n "${SOURCE_KEY}" ]]; then
    aws s3 rm "s3://${SOURCE_BUCKET}/${SOURCE_KEY}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

printf 'terraformers s3 writer validation %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${PAYLOAD_FILE}"

cd "${BACKEND_DIR}"
echo "[s3-writer] packaging backend"
mvn -q -DskipTests package

echo "[s3-writer] starting backend on port ${PORT} with S3 writer enabled only"
SERVER_PORT="${PORT}" \
SPRING_PROFILES_ACTIVE="local" \
AWS_REGION="${AWS_REGION}" \
AWS_DEFAULT_REGION="${AWS_REGION}" \
TERRAFORMERS_UPLOAD_SOURCE_BUCKET="${S3_UPLOAD_BUCKET}" \
TERRAFORMERS_UPLOAD_SOURCE_PREFIX="${S3_UPLOAD_PREFIX}" \
TERRAFORMERS_STORAGE_S3_READER_ENABLED="false" \
TERRAFORMERS_STORAGE_S3_WRITER_ENABLED="true" \
TERRAFORMERS_ANALYSIS_BEDROCK_PROVIDER_ENABLED="false" \
TERRAFORMERS_ANALYSIS_BEDROCK_EMBEDDING_ENABLED="false" \
TERRAFORMERS_ANALYSIS_OPENSEARCH_RETRIEVER_ENABLED="false" \
TERRAFORMERS_ANALYSIS_SQS_PUBLISHER_ENABLED="false" \
java -jar target/terraformers-backend-modernization-0.1.0-SNAPSHOT.jar > "${APP_LOG}" 2>&1 &
APP_PID="$!"

for attempt in {1..60}; do
  if curl -fsS "http://127.0.0.1:${PORT}/actuator/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${APP_PID}" >/dev/null 2>&1; then
    echo "Backend process exited before becoming healthy. Log follows:" >&2
    cat "${APP_LOG}" >&2
    exit 1
  fi
  sleep 2
  if [[ "${attempt}" == "60" ]]; then
    echo "Backend did not become healthy within timeout. Log follows:" >&2
    cat "${APP_LOG}" >&2
    exit 1
  fi
done

echo "[s3-writer] uploading validation object through /api/upload"
curl -fsS \
  -X POST "http://127.0.0.1:${PORT}/api/upload" \
  -F "projectId=${PROJECT_ID}" \
  -F "file=@${PAYLOAD_FILE};type=image/png;filename=validation-architecture.png" \
  -o "${UPLOAD_RESPONSE_JSON}"

SOURCE_BUCKET="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sourceBucket"])' "${UPLOAD_RESPONSE_JSON}")"
SOURCE_KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sourceKey"])' "${UPLOAD_RESPONSE_JSON}")"
STORAGE_PROVIDER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("storageProvider", ""))' "${UPLOAD_RESPONSE_JSON}")"
BINARY_PERSISTED="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("binaryPersisted", "")).lower())' "${UPLOAD_RESPONSE_JSON}")"
STORAGE_ETAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("storageETag") or "")' "${UPLOAD_RESPONSE_JSON}")"

if [[ "${SOURCE_BUCKET}" != "${S3_UPLOAD_BUCKET}" ]]; then
  echo "Expected sourceBucket=${S3_UPLOAD_BUCKET}, got ${SOURCE_BUCKET}" >&2
  cat "${UPLOAD_RESPONSE_JSON}" >&2
  exit 1
fi

if [[ "${STORAGE_PROVIDER}" != "s3" ]]; then
  echo "Expected storageProvider=s3, got ${STORAGE_PROVIDER}" >&2
  cat "${UPLOAD_RESPONSE_JSON}" >&2
  exit 1
fi

if [[ "${BINARY_PERSISTED}" != "true" ]]; then
  echo "Expected binaryPersisted=true, got ${BINARY_PERSISTED}" >&2
  cat "${UPLOAD_RESPONSE_JSON}" >&2
  exit 1
fi

if [[ -z "${STORAGE_ETAG}" ]]; then
  echo "Expected non-empty storageETag" >&2
  cat "${UPLOAD_RESPONSE_JSON}" >&2
  exit 1
fi

echo "[s3-writer] confirming object exists through s3api head-object"
aws s3api head-object \
  --bucket "${SOURCE_BUCKET}" \
  --key "${SOURCE_KEY}" \
  --region "${AWS_REGION}" \
  > "${HEAD_OBJECT_JSON}"

HEAD_LENGTH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ContentLength"])' "${HEAD_OBJECT_JSON}")"
HEAD_CONTENT_TYPE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("ContentType", ""))' "${HEAD_OBJECT_JSON}")"

if [[ "${HEAD_CONTENT_TYPE}" != "image/png" ]]; then
  echo "Expected S3 ContentType=image/png, got ${HEAD_CONTENT_TYPE}" >&2
  cat "${HEAD_OBJECT_JSON}" >&2
  exit 1
fi

cat > "${EVIDENCE_MD}" <<EOF
# S3 Writer Production Validation

- validatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- awsRegion: ${AWS_REGION}
- uploadBucket: ${SOURCE_BUCKET}
- uploadPrefix: ${S3_UPLOAD_PREFIX}
- projectId: ${PROJECT_ID}
- sourceKey: ${SOURCE_KEY}
- storageProvider: ${STORAGE_PROVIDER}
- binaryPersisted: ${BINARY_PERSISTED}
- storageETag: ${STORAGE_ETAG}
- headObjectContentLength: ${HEAD_LENGTH}
- headObjectContentType: ${HEAD_CONTENT_TYPE}
- cleanupRequested: ${CLEANUP_S3_OBJECT}

## Boundary

Only the S3 writer adapter was enabled for this validation. S3 reader, Bedrock provider, OpenSearch retriever, and SQS publisher remained disabled.
EOF

cat "${EVIDENCE_MD}"
echo "[s3-writer] production validation completed"
