#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PROJECT_ID="${PROJECT_ID:-project-smoke}"
SOURCE_BUCKET="${SOURCE_BUCKET:-example-bucket}"
SOURCE_KEY="${SOURCE_KEY:-uploads/architecture-diagram.png}"
CORRELATION_ID="${CORRELATION_ID:-smoke-$(date +%Y%m%d%H%M%S)}"
EXPECT_STATUS="${EXPECT_STATUS:-SUCCEEDED}"
EXPECT_RESULT_KEY="${EXPECT_RESULT_KEY:-true}"
EXPECT_RESULT_PREVIEW="${EXPECT_RESULT_PREVIEW:-true}"

payload=$(cat <<JSON
{
  "projectId": "${PROJECT_ID}",
  "sourceBucket": "${SOURCE_BUCKET}",
  "sourceKey": "${SOURCE_KEY}",
  "correlationId": "${CORRELATION_ID}"
}
JSON
)

create_response_file=$(mktemp)
get_response_file=$(mktemp)
trap 'rm -f "${create_response_file}" "${get_response_file}"' EXIT

status=$(curl -sS -o "${create_response_file}" -w "%{http_code}" \
  -H 'Content-Type: application/json' \
  -d "${payload}" \
  "${BASE_URL}/api/analysis/jobs")

cat "${create_response_file}"
echo

if [[ "${status}" != "201" ]]; then
  echo "Expected HTTP 201 but got ${status}" >&2
  exit 1
fi

job_id=$(python3 - <<'PY' "${create_response_file}"
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    print(json.load(f).get('id', ''))
PY
)

if [[ -z "${job_id}" ]]; then
  echo "Failed to extract job id from response" >&2
  exit 1
fi

echo "created analysis job: ${job_id}"

get_status=$(curl -sS -o "${get_response_file}" -w "%{http_code}" \
  "${BASE_URL}/api/analysis/jobs/${job_id}")

cat "${get_response_file}"
echo

if [[ "${get_status}" != "200" ]]; then
  echo "Expected HTTP 200 for GET but got ${get_status}" >&2
  exit 1
fi

python3 - <<'PY' "${get_response_file}" "${EXPECT_STATUS}" "${EXPECT_RESULT_KEY}" "${EXPECT_RESULT_PREVIEW}"
import json
import sys

path, expected_status, expect_key, expect_preview = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    body = json.load(f)

errors = []
actual_status = body.get('status')
if actual_status != expected_status:
    errors.append(f"status expected {expected_status} but got {actual_status}")

if expect_key.lower() == 'true' and not body.get('resultObjectKey'):
    errors.append('resultObjectKey is empty')

if expect_preview.lower() == 'true' and not body.get('resultPreview'):
    errors.append('resultPreview is empty')

if body.get('status') == 'FAILED' and not body.get('failureReason'):
    errors.append('FAILED status must include failureReason')

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)

print('analysis job smoke assertions passed')
print(f"status={body.get('status')}")
print(f"provider={body.get('provider')}")
print(f"resultObjectKey={body.get('resultObjectKey')}")
PY
