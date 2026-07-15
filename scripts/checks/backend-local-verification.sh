#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
RUN_DOCKER_BUILD="${RUN_DOCKER_BUILD:-false}"
MAVEN_TEST_LOG="${BACKEND_DIR}/target/backend-local-verification-maven.log"

cd "${BACKEND_DIR}"

print_surefire_reports() {
  local reports_dir="${BACKEND_DIR}/target/surefire-reports"

  if [[ ! -d "${reports_dir}" ]]; then
    echo "[backend] surefire reports directory not found: ${reports_dir}" >&2
    return
  fi

  echo "[backend] printing surefire failure reports" >&2
  find "${reports_dir}" -maxdepth 1 -type f \( -name '*.txt' -o -name '*.dump' -o -name '*.dumpstream' \) -print0 \
    | sort -z \
    | while IFS= read -r -d '' report; do
        echo "===== ${report#${BACKEND_DIR}/} =====" >&2
        cat "${report}" >&2
        echo >&2
      done
}

print_maven_tail() {
  if [[ -f "${MAVEN_TEST_LOG}" ]]; then
    echo "[backend] Maven output tail" >&2
    tail -n 160 "${MAVEN_TEST_LOG}" >&2
  fi
}

run_maven_tests() {
  mkdir -p "$(dirname "${MAVEN_TEST_LOG}")"
  mvn -q -e clean test >"${MAVEN_TEST_LOG}" 2>&1
}

echo "[backend] running Maven clean tests"
if ! run_maven_tests; then
  print_maven_tail
  print_surefire_reports
  exit 1
fi

echo "[backend] packaging application without re-running tests"
mvn -q -DskipTests package

if [[ "${RUN_DOCKER_BUILD}" == "true" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker build requested, but docker command was not found." >&2
    exit 1
  fi

  echo "[backend] building Docker image"
  docker build -t terraformers-backend:local .
else
  echo "[backend] skipping Docker image build"
  echo "[backend] set RUN_DOCKER_BUILD=true to include docker build validation"
fi

echo "[backend] local verification completed"
