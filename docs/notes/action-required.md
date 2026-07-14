# Action Required

## Backend baseline verification

After the backend baseline commit, check the following GitHub Actions workflows:

- Backend Maven Verification
- Backend Image Build Verification

If either workflow fails, fix the public baseline before importing additional private backend code.

## Next import target

Do not import the full private repository history. Next import should be limited to backend code that supports the following responsibilities:

1. RDB entity/repository/service structure
2. Cognito user mapping
3. S3 object metadata split
4. SQS log polling contract
5. project/file/comment API paths that are safe to publish

Before import, inspect each file for secret values, account identifiers, hardcoded endpoints, and ownership ambiguity.
