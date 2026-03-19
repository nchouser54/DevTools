# Product Context

## Overview

`DevTools` is a repository of reusable Coder workspace templates, reference MCP configuration, and supporting tooling. The product is intentionally template-first: instead of starting with an abstract framework, it starts with a real workspace that platform teams can inspect, adapt, and operationalize.

## Core Features

- Reference Coder workspace templates with documented structure
- MCP configuration packaged alongside the workspace assets that need it
- Validation tooling to enforce a minimum contract across templates
- Operator documentation for import, configuration, and troubleshooting
- A memory-bank-driven project context to keep architecture and execution aligned

## Initial Product Slice

The first product slice is a Python AI/developer workspace intended for Coder-backed environments. It should be suitable for tasks such as agent development, automation scripting, documentation work, and general Python-based engineering workflows.

## Technical Direction

- Repository documentation in Markdown
- Template metadata in JSON for lightweight validation
- Workspace bootstrap and image assets stored with each template
- Minimal Python-based validation script using the standard library
- Template-specific environment variables provided via example files, not real secrets

## Non-Goals for MVP

- No full-scale template platform/CLI yet (only lightweight scaffold helper script)
- No attempt to support every language immediately
- No custom MCP server implementation until shared needs are proven
