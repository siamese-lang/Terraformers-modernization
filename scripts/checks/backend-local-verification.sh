#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"

cd "${BACKEND_DIR}"

echo "[backend] running Maven tests"
mvn -q test

echo "[backend] packaging application"
mvn -q -DskipTests package

echo "[backend] building Docker image"
docker build -t terraformers-backend:local .

echo "[backend] verification completed"
