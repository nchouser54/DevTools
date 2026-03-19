# DevTools Architecture

## Purpose

`DevTools` organizes reusable developer workspace templates for Coder and packages the supporting MCP configuration, validation scripts, and documentation needed to operate them safely.

## Architecture overview

The repository is composed of four layers:

1. **Templates** in `templates/`
2. **Shared documentation** in `docs/`
3. **Validation and helper scripts** in `scripts/`
4. **Project memory** in `memory-bank/`

This keeps the operational assets close to the template that uses them while preserving a single shared contract for contributors.

## Template anatomy

Each template should be self-contained and include:

- `manifest.json` for template metadata
- `README.md` for human-oriented setup and usage guidance
- `coder/` for Coder-facing assets
- `workspace/` for image and bootstrap assets
- `mcp/` for MCP example configuration
- `.env.example` for documented environment variables

## MVP decisions

- Use one high-quality Python AI workspace as the golden template.
- Prefer preconfigured MCP definitions over custom MCP server implementations.
- Validate template structure with a dependency-light script.
- Treat docs as part of the product surface, not an afterthought.

## Future evolution

Once a second or third template exists, the repository can evaluate whether it needs:

- shared bootstrap fragments
- expanded scaffolding automation beyond the current lightweight generator
- stronger schema validation
- reusable MCP packaging utilities

## Current accelerators

- `scripts/scaffold_template.py` provides a contract-compliant template skeleton generator.
- `scripts/validate_templates.py` enforces the minimum repository template contract.
- `docs/template-idea-backlog.md` and `docs/coder-task-templates.md` provide repeatable ideation and execution patterns.
