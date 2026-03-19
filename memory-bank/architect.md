# DevTools: System Architecture

## Overview

`DevTools` is organized as a repository of versioned template assets plus the documentation and validation logic required to keep those assets coherent.

The architecture is deliberately simple:

1. **Templates are the product surface**
2. **Docs describe how templates are operated and extended**
3. **Scripts enforce structural quality**
4. **Memory-bank files capture intent, context, and decisions**

## Top-Level Components

### 1. Template layer

Located in `templates/`, each template contains everything needed to understand and reuse a workspace pattern:

- template metadata
- Coder-facing configuration files
- workspace image or bootstrap assets
- MCP configuration examples
- environment variable placeholders
- template-specific documentation

### 2. Documentation layer

Located in `docs/`, this layer explains:

- the overall repository architecture
- the template contract contributors must follow
- how to import and operate specific templates

### 3. Validation layer

Located in `scripts/`, this layer enforces baseline consistency without imposing heavy dependencies. The initial validator checks for required files and metadata fields so the repo can grow without structural drift.

### 4. Project memory layer

Located in `memory-bank/`, this layer stores durable context for planning and implementation. It records why the repository is shaped the way it is, what decisions were made, and what comes next.

## Architectural Decisions

1. **Template-first strategy**
   - The repository leads with usable artifacts rather than abstractions.
   - Rationale: a concrete template is easier to validate and evolve than a framework designed in a vacuum.

2. **Single golden template first**
   - The Python AI workspace is the first canonical example.
   - Rationale: one strong pattern creates a reusable baseline for future templates.

3. **MCP integration via configuration before custom code**
   - The MVP packages MCP definitions and documented setup flows rather than implementing new MCP servers.
   - Rationale: this reduces complexity while still delivering useful integration value.

4. **Standard-library validation tooling**
   - The first validator should avoid external dependencies.
   - Rationale: contributors should be able to run checks in minimal environments.
