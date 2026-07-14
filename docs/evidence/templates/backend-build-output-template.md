# Backend Build Output Template

```text
[backend] running Maven tests
<redacted output>

[backend] packaging application
<redacted output>

[backend] building Docker image
<redacted output>

[backend] verification completed
```

Redaction checklist:

- Remove account ids.
- Remove private endpoints.
- Remove tokens and passwords.
- Remove local machine-specific paths if not necessary.
