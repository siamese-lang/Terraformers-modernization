# Frontend lockfile handling

This placeholder exists only to document the expected local workflow.

Do not commit this file as a substitute for `package-lock.json`.

After running `npm install` locally, review the generated `frontend/package-lock.json`. If the build passes and the dependency tree is acceptable for the baseline, commit the real lockfile in a later change.

The verification script uses:

- `npm ci` when `package-lock.json` exists;
- `npm install` when no lockfile exists yet.
