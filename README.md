# DevTools

`DevTools` is a template-first toolkit for building opinionated developer workspaces with **Coder** and **MCP** support.

The initial focus is to help platform and DevOps teams standardize a high-quality Python AI/developer environment that can be imported into Coder, bootstrapped consistently, and shipped with preconfigured MCP integrations.

## Why this repo exists

Most engineering platform teams hit the same friction points when they try to standardize developer environments:

- workspace images drift over time
- AI tooling is bolted on inconsistently
- MCP configuration is duplicated across projects
- operational docs live in people’s heads instead of the repo

This repository aims to solve that by packaging reusable workspace templates, validation scripts, and operator documentation in one place.

## MVP scope

The first milestone for this repository includes:

- a **Python AI workspace** template for Coder
- **preconfigured MCP server definitions** suitable for workspace use
- a documented **template contract** for future templates
- lightweight **validation tooling** to keep templates consistent
- architecture and operator documentation for contributors and platform owners

Out of scope for the MVP:

- custom in-repo MCP servers
- a full opinionated scaffolding platform
- multi-language template parity on day one

## Repository layout

- `templates/` — importable and reference templates
- `docs/` — architecture, template contract, and operator guides
- `scripts/` — validation and helper utilities
- `memory-bank/` — living project context, decisions, and progress tracking

## Current reference template

The first reference implementation lives at `templates/python-ai-workspace/`.

It is designed to establish the golden path for future templates by defining:

- required template metadata
- Coder-facing configuration assets
- workspace image/build assets
- MCP configuration examples
- environment variable placeholders

## Implementation principles

- **template-first delivery** — ship a usable reference template before automating everything around it
- **operator-friendly defaults** — prefer low-friction, auditable integrations
- **no embedded secrets** — templates must document variables, not hard-code them
- **docs as product surface** — setup and troubleshooting guidance are part of the deliverable
- **incremental tooling** — add automation only after patterns stabilize

## Near-term roadmap

1. Finalize the Python AI workspace template contract
2. Validate the template structure with repository tooling
3. Add import and operational docs for Coder administrators
4. Smoke test the reference template end to end
5. Use the same pattern for a second template, likely Node/TypeScript

## Accelerators for new template ideas

This repository now includes lightweight accelerators for quickly creating and evaluating new template concepts:

- `scripts/scaffold_template.py` — generates a contract-compliant template skeleton under `templates/<slug>/`
- `docs/template-idea-backlog.md` — curated backlog of candidate Coder templates to build next
- `docs/coder-task-templates.md` — reusable implementation/checklist task templates for contributors

## Getting started

Start with these docs:

- `docs/architecture.md`
- `docs/template-contract.md`
- `docs/templates/python-ai-workspace.md`

Then run the validation script once templates are present:

- `scripts/validate_templates.py`

To scaffold a brand new template quickly:

- `scripts/scaffold_template.py --name <NAME> --slug <SLUG> --description <DESC>`

This repository now ships multiple reference templates (Python AI workspace + EKS-focused templates) and validation tooling to keep future templates aligned.
