#!/usr/bin/env python3
"""Scaffold a new DevTools template directory from the repository contract.

This script creates a contract-compliant template skeleton under `templates/<slug>/`
so contributors can quickly prototype new Coder template ideas without missing
required files.

Example:
    python scripts/scaffold_template.py \
      --name "Node AI Workspace" \
      --slug node-ai-workspace \
      --description "Node + MCP dev workspace for AI tooling" \
      --owner "Rocket City Defense Solutions LLC" \
      --runtime-language node \
      --runtime-version 20 \
      --base-image mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm \
      --tag coder --tag node --tag ai --tag mcp
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_RELATIVE_FILES = [
    "manifest.json",
    "README.md",
    "coder/main.tf",
    "workspace/Dockerfile",
    "workspace/bootstrap.sh",
    "mcp/servers.example.json",
    ".env.example",
]

SLUG_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scaffold a new DevTools template.")
    parser.add_argument("--name", required=True, help="Human-friendly template name")
    parser.add_argument("--slug", required=True, help="Directory/ID slug (kebab-case)")
    parser.add_argument("--description", required=True, help="Template description")
    parser.add_argument(
        "--owner",
        default="Rocket City Defense Solutions LLC",
        help="Template owner in manifest.json",
    )
    parser.add_argument(
        "--runtime-language",
        default="python",
        help="Runtime language in manifest.json (python, node, go, etc.)",
    )
    parser.add_argument(
        "--runtime-version",
        default="3.12",
        help="Runtime version in manifest.json (pythonVersion/nodeVersion/etc.)",
    )
    parser.add_argument(
        "--base-image",
        default="mcr.microsoft.com/devcontainers/python:1-3.12-bookworm",
        help="Container base image",
    )
    parser.add_argument(
        "--tag",
        action="append",
        dest="tags",
        default=["coder", "workspace", "mcp"],
        help="Repeatable tag option (can be passed multiple times)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing files in an existing template directory",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned files only; do not write anything",
    )
    return parser.parse_args()


def validate_slug(slug: str) -> None:
    if not SLUG_PATTERN.match(slug):
        raise ValueError(
            "Invalid --slug. Use lowercase kebab-case, e.g. 'node-ai-workspace'."
        )


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            result.append(item)
            seen.add(item)
    return result


def runtime_block(language: str, version: str, base_image: str) -> dict[str, str]:
    key_name = "version"
    if language.lower() == "python":
        key_name = "pythonVersion"
    elif language.lower() in {"node", "nodejs", "javascript", "typescript"}:
        key_name = "nodeVersion"

    return {
        "language": language,
        key_name: version,
        "baseImage": base_image,
    }


def render_manifest(args: argparse.Namespace) -> str:
    manifest = {
        "name": args.name,
        "slug": args.slug,
        "description": args.description,
        "owner": args.owner,
        "version": "0.1.0",
        "runtime": runtime_block(args.runtime_language, args.runtime_version, args.base_image),
        "mcp": {
            "mode": "preconfigured-examples",
            "configPath": "mcp/servers.example.json",
            "notes": "Example-only MCP definitions. Operators must review and adapt to their environment.",
        },
        "tags": dedupe_preserve_order(args.tags),
    }
    return json.dumps(manifest, indent=2) + "\n"


def render_readme(args: argparse.Namespace) -> str:
    return f"""# {args.name}

This template was scaffolded from the DevTools contract and is intended as a starting point for Coder workspace customization.

## What it includes

- a starter Coder-oriented Terraform configuration
- a workspace image and bootstrap script
- example MCP server configuration
- an environment variable contract with placeholders only

## Required operator variables

See `.env.example` and update the values for your environment.

## Layout

- `coder/` — Coder-facing assets
- `workspace/` — image and bootstrap assets
- `mcp/` — MCP example configuration

## Next steps

1. Customize `coder/main.tf` for your target platform.
2. Add runtime tools in `workspace/bootstrap.sh`.
3. Update `mcp/servers.example.json` with approved MCP servers.
4. Run `python scripts/validate_templates.py` from repo root.
"""


def render_coder_main_tf(args: argparse.Namespace) -> str:
    template_var_name = args.slug.replace("-", "_")
    tags = ", ".join([f'"{tag}"' for tag in dedupe_preserve_order(args.tags)])

    return f"""terraform {{
  required_version = \">= 1.5.0\"
}}

variable \"workspace_name\" {{
  type        = string
  description = \"Workspace name shown in Coder.\"
  default     = \"{args.slug}\"
}}

variable \"workspace_owner\" {{
  type        = string
  description = \"Workspace owner or team.\"
  default     = \"platform-team\"
}}

locals {{
  template_name = var.workspace_name
  template_slug = \"{template_var_name}\"
  template_tags = [{tags}]
}}

output \"template_summary\" {{
  value = {{
    name  = local.template_name
    slug  = local.template_slug
    owner = var.workspace_owner
    tags  = local.template_tags
  }}
  description = \"Starter metadata for adapting this template to a target Coder environment.\"
}}
"""


def render_dockerfile(args: argparse.Namespace) -> str:
    return f"""FROM {args.base_image}

WORKDIR /workspace
COPY bootstrap.sh /tmp/bootstrap.sh
RUN chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh && rm /tmp/bootstrap.sh
"""


def render_bootstrap_sh() -> str:
    return """#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends \
  git \
  curl \
  ca-certificates

rm -rf /var/lib/apt/lists/*

echo "Bootstrap complete. Add template-specific dependencies here."
"""


def render_servers_example() -> str:
    sample = {
        "mcpServers": {
            "filesystem": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "${MCP_ALLOWED_ROOT}"],
            }
        }
    }
    return json.dumps(sample, indent=2) + "\n"


def render_env_example(args: argparse.Namespace) -> str:
    return f"""# {args.slug} environment placeholders
# Do not commit real credentials.

WORKSPACE_NAME={args.slug}
WORKSPACE_OWNER=platform-team
MCP_ALLOWED_ROOT=/workspace
MCP_GITHUB_TOKEN=replace-me
"""


def write_file(path: Path, content: str, force: bool, dry_run: bool) -> None:
    if path.exists() and not force:
        raise FileExistsError(
            f"Refusing to overwrite existing file: {path} (use --force to overwrite)"
        )
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")

    # Make bootstrap scripts executable.
    if path.name == "bootstrap.sh":
        path.chmod(0o755)


def main() -> int:
    args = parse_args()

    try:
        validate_slug(args.slug)
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        return 1

    repo_root = Path(__file__).resolve().parent.parent
    templates_dir = repo_root / "templates"
    target_dir = templates_dir / args.slug

    plan = {
        "manifest.json": render_manifest(args),
        "README.md": render_readme(args),
        "coder/main.tf": render_coder_main_tf(args),
        "workspace/Dockerfile": render_dockerfile(args),
        "workspace/bootstrap.sh": render_bootstrap_sh(),
        "mcp/servers.example.json": render_servers_example(),
        ".env.example": render_env_example(args),
    }

    print(f"Scaffolding template: {target_dir}")
    if args.dry_run:
        print("[DRY-RUN] Planned files:")
        for rel_path in REQUIRED_RELATIVE_FILES:
            print(f"  - {rel_path}")
        return 0

    target_dir.mkdir(parents=True, exist_ok=True)

    try:
        for rel_path, content in plan.items():
            write_file(target_dir / rel_path, content, force=args.force, dry_run=args.dry_run)
    except FileExistsError as exc:
        print(f"[ERROR] {exc}")
        return 1

    print("[OK] Template scaffold created.")
    print("Next steps:")
    print(f"  1) Edit templates/{args.slug}/README.md and manifest.json")
    print("  2) Adapt coder/main.tf for your target environment")
    print("  3) Run: python scripts/validate_templates.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
