#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATION_DIR="${MIGRATION_DIR:-${REPO_ROOT}/backend/src/main/resources/db/migration}"

if [[ ! -d "${MIGRATION_DIR}" ]]; then
  echo "[flyway] migration directory not found: ${MIGRATION_DIR}" >&2
  exit 1
fi

shopt -s nullglob
migration_files=("${MIGRATION_DIR}"/V*__*.sql)

if (( ${#migration_files[@]} == 0 )); then
  echo "[flyway] no versioned migration files found in ${MIGRATION_DIR}" >&2
  exit 1
fi

declare -A version_to_file=()
failed=0

for migration_file in "${migration_files[@]}"; do
  filename="$(basename "${migration_file}")"

  if [[ ! "${filename}" =~ ^V([0-9]+([._][0-9]+)*)__([A-Za-z0-9_]+)\.sql$ ]]; then
    echo "[flyway] invalid migration filename: ${filename}" >&2
    failed=1
    continue
  fi

  version="${BASH_REMATCH[1]}"
  normalized_version="${version//_/.}"

  if [[ -n "${version_to_file[${normalized_version}]:-}" ]]; then
    echo "[flyway] duplicate version ${normalized_version}:" >&2
    echo "  - ${version_to_file[${normalized_version}]}" >&2
    echo "  - ${filename}" >&2
    failed=1
    continue
  fi

  version_to_file["${normalized_version}"]="${filename}"
done

if (( failed != 0 )); then
  exit 1
fi

printf '[flyway] verified %d unique versioned migrations\n' "${#migration_files[@]}"
printf '%s\n' "${migration_files[@]#${REPO_ROOT}/}" | sort
