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

install_dependencies() {
  if [ -f package-lock.json ]; then
    echo "[frontend] installing dependencies with npm ci"
    if npm ci; then
      return 0
    fi

    echo "[frontend] npm ci failed. package-lock.json may be stale after dependency changes." >&2
    echo "[frontend] falling back to npm install to refresh the local lockfile" >&2
  else
    echo "[frontend] package-lock.json not found. installing dependencies with npm install"
  fi

  npm install
}

require_command node
require_command npm

if [ ! -f "${FRONTEND_DIR}/package.json" ]; then
  echo "frontend/package.json not found" >&2
  exit 1
fi

cd "${FRONTEND_DIR}"

install_dependencies

echo "[frontend] building selected original import baseline"
npm run build

echo "[frontend] selected import verification completed"
