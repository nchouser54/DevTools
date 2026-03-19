# System Patterns

## Architectural Patterns

- **Template bundle pattern**: every template owns its metadata, workspace assets, MCP examples, and documentation in a single directory.
- **Docs beside implementation**: repository-level docs explain shared contracts; template-level docs explain concrete usage.
- **Golden-path first**: new automation should emerge from repeated patterns found in the reference template, not precede them.

## Design Patterns

- **Contract over convention drift**: required files are explicitly documented and validated.
- **Examples instead of secrets**: templates include `.example` or placeholder files so operators can inject real values safely.
- **Layered assets**: Coder configuration, workspace image assets, and MCP definitions live in separate subdirectories to reduce coupling.

## Common Idioms

- Use `manifest.json` as the canonical metadata entry point for a template.
- Keep each template self-describing through a local `README.md`.
- Favor standard-library scripts until repo complexity justifies a richer toolchain.
