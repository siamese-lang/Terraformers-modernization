#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FRONTEND_DIR="${REPO_ROOT}/frontend"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

require_command node
require_command npm

if [ ! -f "${FRONTEND_DIR}/package.json" ]; then
  echo "frontend/package.json not found" >&2
  exit 1
fi

cd "${FRONTEND_DIR}"

if [ -f package-lock.json ]; then
  echo "[frontend] installing dependencies with npm ci"
  npm ci
else
  echo "[frontend] installing dependencies with npm install"
  npm install
fi

echo "[frontend] building browser smoke baseline"
npm run build

echo "[frontend] local verification completed"
