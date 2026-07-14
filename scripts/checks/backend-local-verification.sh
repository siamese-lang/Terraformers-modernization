#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
RUN_DOCKER_BUILD="${RUN_DOCKER_BUILD:-false}"

cd "${BACKEND_DIR}"

echo "[backend] running Maven clean tests"
mvn -q clean test

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
