# Template Idea Backlog

This backlog is intentionally practical: every idea is framed as a shippable Coder template with a clear persona, core value, and first implementation slice.

## Prioritization rubric

Score each candidate 1–5 on:

- **Platform impact** — how many teams/workflows benefit
- **Reuse potential** — how much can be shared with existing templates
- **Operational risk** — security/compliance complexity (lower risk = higher score)
- **Time-to-first-value** — effort to deliver a useful `v0.1.0`

Use weighted score:

$$
\text{score} = 0.35\,I + 0.30\,R + 0.20\,O + 0.15\,T
$$

Where $I$ is impact, $R$ reuse, $O$ operational risk score, and $T$ time-to-value score.

## High-priority candidates

### 1) Node/TypeScript AI Workspace
- **Persona**: Frontend/full-stack teams building copilots and agent tooling in TS
- **Core value**: Mirrors `python-ai-workspace` in Node ecosystem
- **v0.1.0 scope**:
  - Node 20 devcontainer base
  - pnpm + npm + eslint + prettier bootstrap
  - MCP examples for filesystem + GitHub
  - Coder variables for workspace owner/name

### 2) Platform SRE Runbook Workspace
- **Persona**: SRE/platform engineers running kubectl/helm/terraform workflows
- **Core value**: Secure, repeatable operational workspace with least privilege defaults
- **v0.1.0 scope**:
  - kubectl, helm, terraform, awscli bootstrap
  - Optional read-only kubeconfig mount pattern docs
  - MCP examples limited to docs/search + filesystem

### 3) Data Analysis Workspace (Python + Jupyter)
- **Persona**: Analysts and ML engineers with notebook-heavy workflows
- **Core value**: Turnkey data environment with validated package baseline
- **v0.1.0 scope**:
  - pandas, pyarrow, jupyterlab, matplotlib
  - Notebook security notes and data mount guidance
  - MCP examples for filesystem and docs retrieval

### 4) Secure Enterprise API Builder
- **Persona**: Backend teams deploying secure services to EKS
- **Core value**: Opinionated starter for secure API workloads + deployment posture
- **v0.1.0 scope**:
  - FastAPI/Flask base service
  - PSS baseline, NetworkPolicy, HPA, PDB
  - IRSA-ready service account pattern and Helm chart

## Medium-priority candidates

### 5) Agent Evaluation Workspace
- **Persona**: AI platform teams running eval loops and regression checks
- **v0.1.0 scope**: eval dataset layout, pytest-based eval harness, metrics export stubs

### 6) Documentation Automation Workspace
- **Persona**: Tech writers / developer advocacy
- **v0.1.0 scope**: markdown lint, docs build pipeline, static site preview tooling

### 7) Incident Response Workspace
- **Persona**: on-call and security operations
- **v0.1.0 scope**: log query tools, runbook scripts, immutable shell history defaults

### 8) Internal Developer Portal Workspace
- **Persona**: platform enablement teams
- **v0.1.0 scope**: backstage/plugin development setup + policy linting tools

## Candidate tags for consistency

Use a stable, query-friendly tag style in `manifest.json`:

- always include: `coder`, `workspace`, `mcp`
- add domain tags: `python`, `node`, `sre`, `data`, `security`, `eks`, `aws`, `agent`, `docs`

## Definition of Ready (DoR)

A template idea is ready to implement when it has:

1. A one-paragraph persona + problem statement
2. A bounded `v0.1.0` scope (5–8 bullet items)
3. Required environment variables listed
4. Security assumptions documented
5. Success criteria defined (what “usable” means)

## Definition of Done (DoD)

A template is complete when:

1. It passes `scripts/validate_templates.py`
2. It includes `README.md` setup notes and no-secret guarantees
3. It has at least one smoke-test workflow documented
4. It is listed in this backlog as `implemented` with date/version
