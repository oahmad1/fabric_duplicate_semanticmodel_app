# Contributing

## Local development

```powershell
python -m unittest discover -s tests
```

## Guidelines

- Keep scanner behavior read-only.
- Do not commit real tenant metadata or customer model exports.
- Add tests for scoring changes.
- Update docs when schema, notebook behavior, or report guidance changes.
- Keep end-user instructions no-code wherever possible.

