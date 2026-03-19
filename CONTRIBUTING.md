# Contributing

## Philosophy

This repository grows by establishing clear, reusable template patterns. Prefer improving the shared contract and documentation before adding one-off complexity.

## When adding a template

1. Create a new directory under `templates/`.
2. Follow the required structure from `docs/template-contract.md`.
3. Add template-specific documentation.
4. Document every operator-provided environment variable.
5. Run the validation script before submitting changes.

## Review checklist

- Does the template include every required file?
- Are all variables documented and non-secret?
- Is the MCP configuration example realistic and environment-safe?
- Does the template README explain how an operator should adapt it?
- Would a second contributor be able to extend this template without tribal knowledge?
