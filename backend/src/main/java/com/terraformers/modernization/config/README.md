# Config Package

This package contains public-safe runtime configuration contract code.

Current classes:

- `RuntimeContractProperties`: required runtime environment key list.
- `RuntimeConfigInspector`: checks whether required keys are present without exposing values.
- `RuntimeConfigStatus`: key presence response model.

Rules:

- Do not return secret values from operational endpoints.
- Do not hardcode real AWS account values.
- Keep key presence checks separate from credential verification.
