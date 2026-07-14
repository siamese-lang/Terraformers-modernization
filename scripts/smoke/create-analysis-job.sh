#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PROJECT_ID="${PROJECT_ID:-project-smoke}"
SOURCE_BUCKET="${SOURCE_BUCKET:-example-bucket}"
SOURCE_KEY="${SOURCE_KEY:-uploads/architecture-diagram.png}"
CORRELATION_ID="${CORRELATION_ID:-smoke-$(date +%Y%m%d%H%M%S)}"

payload=$(cat <<JSON
{
  "projectId": "${PROJECT_ID}",
  "sourceBucket": "${SOURCE_BUCKET}",
  "sourceKey": "${SOURCE_KEY}",
  "correlationId": "${CORRELATION_ID}"
}
JSON
)

response_file=$(mktemp)
status=$(curl -sS -o "${response_file}" -w "%{http_code}" \
  -H 'Content-Type: application/json' \
  -d "${payload}" \
  "${BASE_URL}/api/analysis/jobs")

cat "${response_file}"
echo

if [[ "${status}" != "201" ]]; then
  echo "Expected HTTP 201 but got ${status}" >&2
  exit 1
fi

job_id=$(python3 - <<'PY' "${response_file}"
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

curl -sS "${BASE_URL}/api/analysis/jobs/${job_id}"
echo
