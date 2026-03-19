#!/usr/bin/env python3
"""
Bedrock chatbot service with embedded GitHub/Jira/Confluence actions.

This service keeps connector setup "inside Coder" by using the same template
inputs/secrets already provided at workspace creation time.

Endpoints:
    GET  /health
    GET  /capabilities
    POST /chat
    POST /action
"""
from __future__ import annotations

import base64
import os
from http import HTTPStatus
from typing import Any

import boto3
from atlassian import Confluence, Jira
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request
from github import Github

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "replace-with-govcloud-sonnet-4.5-model-id")
PORT = int(os.environ.get("PORT", "8080"))


def _flag(name: str) -> bool:
    return os.environ.get(name, "false").lower() == "true"


def _require_write_enabled() -> tuple[bool, str | None]:
    if _flag("ALLOW_CONNECTOR_WRITES"):
        return True, None
    return False, "Write actions are disabled. Set ALLOW_CONNECTOR_WRITES=true to enable."


def _env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def _active_connectors() -> list[str]:
    active: list[str] = []
    for connector in ("GITHUB", "JIRA", "CONFLUENCE"):
        if _flag(f"MCP_ENABLE_{connector}"):
            active.append(connector.lower())
    return active


def _connector_targets() -> list[str]:
    targets: list[str] = []
    if _flag("MCP_ENABLE_GITHUB"):
        targets.append(
            f"github={os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/"
            f"{os.environ.get('GITHUB_REPOSITORY', 'owner/repo')}@{os.environ.get('GITHUB_BRANCH', 'main')}"
        )
    if _flag("MCP_ENABLE_JIRA"):
        targets.append(
            f"jira={os.environ.get('JIRA_SERVER_URL', 'https://your-org.atlassian.net')}"
            f"#{os.environ.get('JIRA_PROJECT_KEY', 'TEAM')}"
        )
    if _flag("MCP_ENABLE_CONFLUENCE"):
        targets.append(
            f"confluence={os.environ.get('CONFLUENCE_SERVER_URL', 'https://your-org.atlassian.net/wiki')}"
            f"#{os.environ.get('CONFLUENCE_SPACE_KEY', 'ENG')}"
        )
    return targets


def _build_system_prompt() -> str:
    parts = [
        "You are a helpful assistant. Answer concisely and accurately.",
        "If the user asks to perform connector actions (GitHub/Jira/Confluence),"
        " instruct them to call POST /action with a supported action.",
    ]

    if _flag("MCP_ENABLE_GITHUB"):
        parts.append("GitHub connector is enabled.")
    if _flag("MCP_ENABLE_JIRA"):
        parts.append("Jira connector is enabled.")
    if _flag("MCP_ENABLE_CONFLUENCE"):
        parts.append("Confluence connector is enabled.")
    if _flag("ALLOW_CONNECTOR_WRITES"):
        parts.append("Write actions are enabled.")
    else:
        parts.append("Write actions are disabled.")

    return " ".join(parts)


def _github_client() -> Github:
    token = _env_first("GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_PAT")
    return Github(base_url=os.environ.get("GITHUB_SERVER_URL", "https://github.com"), login_or_token=token)


def _jira_client() -> Jira:
    return Jira(
        url=os.environ.get("JIRA_SERVER_URL", "https://your-org.atlassian.net"),
        username=_env_first("JIRA_USER_EMAIL", "JIRA_USERNAME"),
        password=_env_first("JIRA_API_TOKEN", "JIRA_PAT"),
    )


def _confluence_client() -> Confluence:
    return Confluence(
        url=os.environ.get("CONFLUENCE_SERVER_URL", "https://your-org.atlassian.net/wiki"),
        username=_env_first("CONFLUENCE_USER_EMAIL", "CONFLUENCE_USERNAME"),
        password=_env_first("CONFLUENCE_API_TOKEN", "CONFLUENCE_PAT"),
    )


def _require_enabled(connector: str) -> tuple[bool, str | None]:
    if _flag(f"MCP_ENABLE_{connector.upper()}"):
        return True, None
    return False, f"{connector} connector is disabled. Enable MCP_ENABLE_{connector.upper()} first."


def _action_github_get_file(params: dict[str, Any]) -> dict[str, Any]:
    ok, err = _require_enabled("github")
    if not ok:
        return {"ok": False, "error": err}

    path = (params.get("path") or "").strip()
    if not path:
        return {"ok": False, "error": "path is required"}

    repo_name = params.get("repository") or os.environ.get("GITHUB_REPOSITORY", "owner/repo")
    ref = params.get("ref") or os.environ.get("GITHUB_BRANCH", "main")

    try:
        repo = _github_client().get_repo(repo_name)
        content = repo.get_contents(path, ref=ref)
        decoded = base64.b64decode(content.content).decode("utf-8", errors="replace")
        return {
            "ok": True,
            "repository": repo_name,
            "path": path,
            "ref": ref,
            "content": decoded,
        }
    except Exception as exc:
        return {"ok": False, "error": f"github.get_file failed: {exc}"}


def _action_github_create_issue(params: dict[str, Any]) -> dict[str, Any]:
    ok, err = _require_enabled("github")
    if not ok:
        return {"ok": False, "error": err}
    ok, err = _require_write_enabled()
    if not ok:
        return {"ok": False, "error": err}

    title = (params.get("title") or "").strip()
    body = params.get("body") or ""
    if not title:
        return {"ok": False, "error": "title is required"}

    labels = params.get("labels") or []
    repo_name = params.get("repository") or os.environ.get("GITHUB_REPOSITORY", "owner/repo")

    try:
        issue = _github_client().get_repo(repo_name).create_issue(title=title, body=body, labels=labels)
        return {
            "ok": True,
            "issue_number": issue.number,
            "issue_url": issue.html_url,
            "repository": repo_name,
        }
    except Exception as exc:
        return {"ok": False, "error": f"github.create_issue failed: {exc}"}


def _action_jira_create_issue(params: dict[str, Any]) -> dict[str, Any]:
    ok, err = _require_enabled("jira")
    if not ok:
        return {"ok": False, "error": err}
    ok, err = _require_write_enabled()
    if not ok:
        return {"ok": False, "error": err}

    summary = (params.get("summary") or "").strip()
    description = params.get("description") or ""
    issue_type = params.get("issue_type") or "Task"
    project_key = params.get("project_key") or os.environ.get("JIRA_PROJECT_KEY", "TEAM")

    if not summary:
        return {"ok": False, "error": "summary is required"}

    try:
        jira = _jira_client()
        payload = {
            "project": {"key": project_key},
            "summary": summary,
            "description": description,
            "issuetype": {"name": issue_type},
        }
        issue = jira.issue_create(fields=payload)
        key = issue.get("key")
        return {
            "ok": True,
            "issue_key": key,
            "issue_url": f"{os.environ.get('JIRA_SERVER_URL', '').rstrip('/')}/browse/{key}" if key else "",
            "project_key": project_key,
        }
    except Exception as exc:
        return {"ok": False, "error": f"jira.create_issue failed: {exc}"}


def _action_confluence_create_page(params: dict[str, Any]) -> dict[str, Any]:
    ok, err = _require_enabled("confluence")
    if not ok:
        return {"ok": False, "error": err}
    ok, err = _require_write_enabled()
    if not ok:
        return {"ok": False, "error": err}

    title = (params.get("title") or "").strip()
    body = params.get("body") or ""
    space_key = params.get("space_key") or os.environ.get("CONFLUENCE_SPACE_KEY", "ENG")
    parent_id = params.get("parent_id")

    if not title:
        return {"ok": False, "error": "title is required"}

    try:
        confluence = _confluence_client()
        page = confluence.create_page(
            space=space_key,
            title=title,
            body=body,
            parent_id=parent_id,
            representation="storage",
        )
        return {
            "ok": True,
            "page_id": page.get("id"),
            "title": title,
            "space_key": space_key,
            "url": page.get("_links", {}).get("base", "") + page.get("_links", {}).get("webui", ""),
        }
    except Exception as exc:
        return {"ok": False, "error": f"confluence.create_page failed: {exc}"}


def _action_workflow_github_file_to_jira(params: dict[str, Any]) -> dict[str, Any]:
    source = _action_github_get_file(params)
    if not source.get("ok"):
        return source

    summary = params.get("summary") or f"Code review follow-up: {source['path']}"
    description = params.get("description") or (
        "Auto-created from GitHub file context."
        f"\n\nRepository: {source['repository']}"
        f"\nRef: {source['ref']}"
        f"\nPath: {source['path']}"
        "\n\n```\n"
        f"{source['content'][:12000]}"
        "\n```"
    )
    issue = _action_jira_create_issue(
        {
            "summary": summary,
            "description": description,
            "issue_type": params.get("issue_type") or "Task",
            "project_key": params.get("project_key"),
        }
    )
    return {
        "ok": issue.get("ok", False),
        "source": {"repository": source.get("repository"), "path": source.get("path"), "ref": source.get("ref")},
        "jira": issue,
    }


def _action_workflow_jira_to_confluence(params: dict[str, Any]) -> dict[str, Any]:
    ok, err = _require_enabled("jira")
    if not ok:
        return {"ok": False, "error": err}

    issue_key = (params.get("issue_key") or "").strip()
    if not issue_key:
        return {"ok": False, "error": "issue_key is required"}

    try:
        issue = _jira_client().issue(issue_key)
    except Exception as exc:
        return {"ok": False, "error": f"jira.issue lookup failed: {exc}"}

    fields = issue.get("fields", {})
    summary = fields.get("summary", issue_key)
    description = fields.get("description") or ""

    page_title = params.get("title") or f"Jira {issue_key}: {summary}"
    page_body = params.get("body") or (
        f"<h2>Jira Issue {issue_key}</h2>"
        f"<p><strong>Summary:</strong> {summary}</p>"
        f"<p><strong>Description:</strong></p><pre>{description}</pre>"
    )

    page = _action_confluence_create_page(
        {
            "title": page_title,
            "body": page_body,
            "space_key": params.get("space_key"),
            "parent_id": params.get("parent_id"),
        }
    )

    return {
        "ok": page.get("ok", False),
        "jira_issue_key": issue_key,
        "confluence": page,
    }


ACTION_HANDLERS = {
    "github.get_file": _action_github_get_file,
    "github.create_issue": _action_github_create_issue,
    "jira.create_issue": _action_jira_create_issue,
    "confluence.create_page": _action_confluence_create_page,
    "workflow.github_file_to_jira": _action_workflow_github_file_to_jira,
    "workflow.jira_to_confluence": _action_workflow_jira_to_confluence,
}

app = Flask(__name__)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)


@app.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "model": MODEL_ID,
            "region": REGION,
            "active_connectors": _active_connectors(),
            "allow_connector_writes": _flag("ALLOW_CONNECTOR_WRITES"),
        }
    )


@app.get("/capabilities")
def capabilities():
    return jsonify(
        {
            "active_connectors": _active_connectors(),
            "targets": _connector_targets(),
            "allow_connector_writes": _flag("ALLOW_CONNECTOR_WRITES"),
            "supported_actions": sorted(ACTION_HANDLERS.keys()),
        }
    )


@app.post("/chat")
def chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    if not message:
        return jsonify({"error": "message is required"}), HTTPStatus.BAD_REQUEST

    history = list(body.get("history") or [])
    history.append({"role": "user", "content": [{"text": message}]})

    try:
        response = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": _build_system_prompt()}],
            messages=history,
        )
    except ClientError as exc:
        return jsonify({"error": f"Bedrock Converse failed: {exc}"}), HTTPStatus.BAD_GATEWAY

    reply = response["output"]["message"]["content"][0]["text"]
    history.append({"role": "assistant", "content": [{"text": reply}]})
    return jsonify({"reply": reply, "history": history, "model": MODEL_ID})


@app.post("/action")
def action():
    body = request.get_json(silent=True) or {}
    action_name = (body.get("action") or "").strip()
    params = body.get("params") or {}

    if not action_name:
        return jsonify({"ok": False, "error": "action is required"}), HTTPStatus.BAD_REQUEST

    handler = ACTION_HANDLERS.get(action_name)
    if handler is None:
        return (
            jsonify(
                {
                    "ok": False,
                    "error": f"unsupported action: {action_name}",
                    "supported_actions": sorted(ACTION_HANDLERS.keys()),
                }
            ),
            HTTPStatus.BAD_REQUEST,
        )

    result = handler(params)
    status = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
    return jsonify(result), status


if __name__ == "__main__":
    active = _active_connectors()
    print(f"Connectors chatbot starting (model={MODEL_ID}, region={REGION}, port={PORT})")
    if active:
        print(f"Active connectors: {', '.join(active)}")
        print(f"Connector targets: {', '.join(_connector_targets())}")
    else:
        print("No connectors enabled. Set MCP_ENABLE_GITHUB/JIRA/CONFLUENCE=true to activate.")
    print(f"Connector writes enabled: {_flag('ALLOW_CONNECTOR_WRITES')}")
    app.run(host="0.0.0.0", port=PORT)
