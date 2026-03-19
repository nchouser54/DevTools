#!/usr/bin/env python3
"""Validate DevTools template structure."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED_TEMPLATE_FILES = [
    "manifest.json",
    "README.md",
    "coder/main.tf",
    "workspace/Dockerfile",
    "workspace/bootstrap.sh",
    "mcp/servers.example.json",
    ".env.example",
]

REQUIRED_MANIFEST_FIELDS = [
    "name",
    "slug",
    "description",
    "owner",
    "version",
    "runtime",
    "mcp",
    "tags",
]


def is_template_candidate(path: Path) -> bool:
    """Return True only for visible template directories.

    This skips hidden/macOS sidecar artifacts (e.g., ._foo) that can appear on
    external drives and should not be treated as real templates.
    """
    return path.is_dir() and not path.name.startswith(".")


def validate_template(template_dir: Path) -> list[str]:
    errors: list[str] = []

    for relative_path in REQUIRED_TEMPLATE_FILES:
        if not (template_dir / relative_path).exists():
            errors.append(f"missing required file: {relative_path}")

    manifest_path = template_dir / "manifest.json"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"invalid manifest.json: {exc}")
        else:
            for field in REQUIRED_MANIFEST_FIELDS:
                if field not in manifest:
                    errors.append(f"manifest missing field: {field}")

            slug = manifest.get("slug")
            if isinstance(slug, str) and slug and slug != template_dir.name:
                errors.append(
                    f"manifest slug '{slug}' does not match directory name '{template_dir.name}'"
                )

            for field in ["name", "slug", "description", "owner", "version"]:
                value = manifest.get(field)
                if value is not None and (not isinstance(value, str) or not value.strip()):
                    errors.append(f"manifest field '{field}' must be a non-empty string")

            tags = manifest.get("tags")
            if tags is not None and not isinstance(tags, list):
                errors.append("manifest field 'tags' must be a list")
            elif isinstance(tags, list):
                if not tags:
                    errors.append("manifest field 'tags' must not be empty")
                elif not all(isinstance(tag, str) and tag.strip() for tag in tags):
                    errors.append("manifest field 'tags' must contain non-empty strings")

    return errors


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    templates_dir = repo_root / "templates"

    if not templates_dir.exists():
        print("No templates directory found.")
        return 1

    template_dirs = sorted(path for path in templates_dir.iterdir() if is_template_candidate(path))
    if not template_dirs:
        print("No templates found.")
        return 1

    has_errors = False
    for template_dir in template_dirs:
        errors = validate_template(template_dir)
        if errors:
            has_errors = True
            print(f"[FAIL] {template_dir.name}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"[OK]   {template_dir.name}")

    return 1 if has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
