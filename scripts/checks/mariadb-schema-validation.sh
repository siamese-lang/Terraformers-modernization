#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
LOG_FILE="${BACKEND_DIR}/target/mariadb-schema-validation.log"
REPOSITORY_SMOKE_LOG="${BACKEND_DIR}/target/mariadb-repository-smoke.log"
PORT="${SERVER_PORT:-18080}"
HEALTH_URL="http://127.0.0.1:${PORT}/actuator/health"
APP_PID=""

cleanup() {
  if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

required_env=(
  SPRING_DATASOURCE_URL
  SPRING_DATASOURCE_USERNAME
  SPRING_DATASOURCE_PASSWORD
  COGNITO_REGION
  COGNITO_USER_POOL_ID
  COGNITO_USER_POOL_CLIENT_ID
  COGNITO_JWKS_URL
  S3_BUCKET_NAME
  AI_LOG_QUEUE_URL
  TERRAFORM_LOG_QUEUE_URL
  BEDROCK_MODEL_ID
  BEDROCK_EMBEDDING_MODEL_ID
  OPENSEARCH_ENDPOINT
  INDEX_NAME
  VECTOR_FIELD_NAME
  CONTENT_FIELD_NAME
)

for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "[mariadb] required environment variable is missing: ${name}" >&2
    exit 1
  fi
done

mkdir -p "${BACKEND_DIR}/target"
cd "${BACKEND_DIR}"

echo "[mariadb] packaging backend without compiling or running tests"
mvn -q -Dmaven.test.skip=true package

jar_file="$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.original' | head -n 1)"
if [[ -z "${jar_file}" ]]; then
  echo "[mariadb] packaged application jar not found" >&2
  exit 1
fi

echo "[mariadb] starting production profile with Flyway and ddl-auto=validate"
SERVER_PORT="${PORT}" \
S3_READER_ENABLED=false \
S3_WRITER_ENABLED=false \
BEDROCK_PROVIDER_ENABLED=false \
BEDROCK_EMBEDDING_ENABLED=false \
OPENSEARCH_RETRIEVER_ENABLED=false \
ANALYSIS_SQS_PUBLISHER_ENABLED=false \
java -jar "${jar_file}" --spring.profiles.active=prod >"${LOG_FILE}" 2>&1 &
APP_PID=$!

healthy=false
for attempt in $(seq 1 60); do
  if ! kill -0 "${APP_PID}" 2>/dev/null; then
    echo "[mariadb] application exited before becoming healthy" >&2
    tail -n 200 "${LOG_FILE}" >&2 || true
    exit 1
  fi

  if curl --fail --silent --show-error "${HEALTH_URL}" >/tmp/terraformers-mariadb-health.json 2>/dev/null; then
    echo "[mariadb] application health check passed"
    cat /tmp/terraformers-mariadb-health.json
    echo
    healthy=true
    break
  fi

  sleep 2
done

if [[ "${healthy}" != "true" ]]; then
  echo "[mariadb] application did not become healthy" >&2
  tail -n 200 "${LOG_FILE}" >&2 || true
  exit 1
fi

echo "[mariadb] Flyway migration and Hibernate schema validation passed"

kill "${APP_PID}" 2>/dev/null || true
wait "${APP_PID}" 2>/dev/null || true
APP_PID=""

echo "[mariadb] running canonical repository smoke queries"
if ! mvn -q -Dtest=MariaDbRepositorySmokeTest test >"${REPOSITORY_SMOKE_LOG}" 2>&1; then
  echo "[mariadb] repository smoke queries failed" >&2
  tail -n 200 "${REPOSITORY_SMOKE_LOG}" >&2 || true
  exit 1
fi

echo "[mariadb] canonical repository smoke queries passed"
