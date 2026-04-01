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
        "--profile",
        choices=["standard", "govcloud"],
        default="standard",
        help="Scaffold profile. 'govcloud' adds opinionated AWS GovCloud import defaults.",
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
    tags = dedupe_preserve_order(args.tags)
    if args.profile == "govcloud":
        tags = dedupe_preserve_order(tags + ["aws", "govcloud", "aws-us-gov"])

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
        "tags": tags,
    }

    if args.profile == "govcloud":
        manifest["inputProfile"] = {
            "mode": "minimal-first",
            "minimalRequired": ["AWS_REGION", "WORKSPACE_OWNER"],
            "autoDerived": ["WORKSPACE_NAME"],
            "advancedOptional": [
                "DEFAULT_KUBE_NAMESPACE",
                "AUTO_CONFIGURE_KUBECONFIG",
                "ENABLE_HELM",
                "HELM_VERSION",
                "ENABLE_XRDP",
                "XRDP_PORT",
                "ENABLE_MCP_GITHUB",
                "MCP_GITHUB_TOKEN",
                "HTTPS_PROXY",
                "HTTP_PROXY",
                "NO_PROXY",
            ],
        }
        manifest["platform"] = {
            "target": "aws-govcloud",
            "partition": "aws-us-gov",
            "notes": "Starter template profile for easy GovCloud import and operator customization.",
        }

    return json.dumps(manifest, indent=2) + "\n"


def render_readme(args: argparse.Namespace) -> str:
    govcloud_section = ""
    if args.profile == "govcloud":
        govcloud_section = """
## GovCloud starter defaults

- `AWS_REGION` default is `us-gov-west-1`
- environment placeholders include proxy + optional helm/xrdp toggles
- manifest includes an `inputProfile` with GovCloud-friendly variable contract
- includes placeholder IAM and MCP variables for secure operator wiring
"""

    return f"""# {args.name}

This template was scaffolded from the DevTools contract and is intended as a starting point for Coder workspace customization.

## What it includes

- a starter Coder-oriented Terraform configuration
- a workspace image and bootstrap script
- example MCP server configuration
- an environment variable contract with placeholders only

## Required operator variables

See `.env.example` and update the values for your environment.
{govcloud_section}

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

        if args.profile == "govcloud":
                return f"""terraform {{
    required_version = ">= 1.5.0"
}}

variable "workspace_name" {{
    type        = string
    description = "Workspace name shown in Coder."
    default     = "{args.slug}"
}}

variable "workspace_owner" {{
    type        = string
    description = "Workspace owner or team."
    default     = "platform-team"
}}

variable "aws_region" {{
    type        = string
    description = "AWS GovCloud region for this workspace."
    default     = "us-gov-west-1"
}}

variable "default_kube_namespace" {{
    type        = string
    description = "Default Kubernetes namespace for operator helper commands."
    default     = "default"
}}

variable "auto_configure_kubeconfig" {{
    type        = bool
    description = "Enable automatic kubeconfig helper flow for EKS-oriented templates."
    default     = true
}}

variable "enable_helm" {{
    type        = bool
    description = "Optional Helm tooling toggle for workspace bootstrap."
    default     = false
}}

variable "helm_version" {{
    type        = string
    description = "Helm version to install when enable_helm is true."
    default     = "v3.16.2"
}}

variable "enable_xrdp" {{
    type        = bool
    description = "Optional Linux XRDP desktop toggle for EC2-style templates."
    default     = false
}}

variable "xrdp_port" {{
    type        = number
    description = "XRDP listen port when enable_xrdp is true."
    default     = 3389
}}

locals {{
    template_name = var.workspace_name
    template_slug = "{template_var_name}"
    template_tags = [{tags}]
}}

output "template_summary" {{
    value = {{
        name            = local.template_name
        slug            = local.template_slug
        owner           = var.workspace_owner
        aws_region      = var.aws_region
        tags            = local.template_tags
        kube_namespace  = var.default_kube_namespace
        auto_kubeconfig = var.auto_configure_kubeconfig
        helm = {{
            enabled = var.enable_helm
            version = var.helm_version
        }}
        xrdp = {{
            enabled = var.enable_xrdp
            port    = var.xrdp_port
        }}
    }}
    description = "GovCloud starter metadata for adapting this template to a target Coder environment."
}}
"""

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

ENABLE_HELM="${ENABLE_HELM:-false}"
HELM_VERSION="${HELM_VERSION:-v3.16.2}"

if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        jq \
        unzip
    rm -rf /var/lib/apt/lists/*
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache git curl ca-certificates jq unzip
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git curl ca-certificates jq unzip
    dnf clean all
elif command -v yum >/dev/null 2>&1; then
    yum install -y git curl ca-certificates jq unzip
    yum clean all
fi

if [[ "$ENABLE_HELM" == "true" ]]; then
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) HELM_ARCH="amd64" ;;
        aarch64|arm64) HELM_ARCH="arm64" ;;
        *) HELM_ARCH="amd64" ;;
    esac

    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" -o /tmp/helm.tgz
    tar -xzf /tmp/helm.tgz -C /tmp
    mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
    rm -rf /tmp/helm.tgz "/tmp/linux-${HELM_ARCH}"
fi

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
    if args.profile == "govcloud":
        return f"""# {args.slug} GovCloud environment placeholders
# Do not commit real credentials.

WORKSPACE_NAME={args.slug}
WORKSPACE_OWNER=platform-team
AWS_REGION=us-gov-west-1
DEFAULT_KUBE_NAMESPACE=default
AUTO_CONFIGURE_KUBECONFIG=true

# Optional tool toggles
ENABLE_HELM=false
HELM_VERSION=v3.16.2
ENABLE_XRDP=false
XRDP_PORT=3389

# Network (optional)
HTTPS_PROXY=
HTTP_PROXY=
NO_PROXY=169.254.169.254,localhost,127.0.0.1

# MCP placeholders
MCP_ALLOWED_ROOT=/workspace
ENABLE_MCP_GITHUB=false
MCP_GITHUB_TOKEN=replace-me
"""

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
