# Web Package

This package contains operational/internal web endpoints for the public backend baseline.

Current endpoint:

```text
GET /internal/runtime/required-config
```

This endpoint returns required runtime key names and boolean presence only.

It must not return:

- DB password
- access token
- secret value
- account-specific private value

In a real deployment, internal endpoints should be protected by ingress, network, authentication, or operational access controls.
