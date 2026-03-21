#!/usr/bin/env python3
"""
RAG-enabled Bedrock chatbot — stateless Flask service.

Retrieves grounded context from a Bedrock Knowledge Base before each Converse call,
reducing hallucination and anchoring answers to your document corpus.

Endpoints:
    GET  /          Serve web UI (index.html).
    GET  /health    Kubernetes liveness/readiness probe.
    POST /chat      Send a message; receive a grounded reply.

Request body (POST /chat):
    {"message": "your question", "history": [...optional prior turns...]}

Response body:
    {"reply": "...", "history": [...], "model": "...", "kb_id": "..."}

Usage:
    export AWS_REGION=us-gov-west-1
    export BEDROCK_MODEL_ID=replace-with-govcloud-sonnet-4.5-model-id
    export BEDROCK_KB_ID=replace-me
    export RAG_MAX_RESULTS=5
    python workspace/rag_chatbot.py
"""
import os
from http import HTTPStatus
from pathlib import Path
from typing import Any

import boto3
from botocore.exceptions import ClientError
from flask import send_file
from flask import Flask, jsonify, request

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "replace-with-govcloud-sonnet-4.5-model-id")
MODEL_PROVIDER = os.environ.get("MODEL_PROVIDER", "bedrock").strip().lower()
AZURE_OPENAI_ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT", "").strip()
AZURE_OPENAI_DEPLOYMENT = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "").strip()
AZURE_OPENAI_API_VERSION = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21").strip()
KB_ID = os.environ["BEDROCK_KB_ID"]
MAX_RESULTS = int(os.environ.get("RAG_MAX_RESULTS", "5"))
PORT = int(os.environ.get("PORT", "8080"))
SUPPORTED_PROVIDER_MODES = {"bedrock", "azure", "dual"}

SYSTEM_TEMPLATE = (
    "You are a helpful assistant. Use ONLY the provided context to answer questions. "
    "If the context does not contain enough information, say so. Do not fabricate answers.\n\n"
    "Context:\n{context}"
)

app = Flask(__name__, static_folder=Path(__file__).parent)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)


@app.get("/")
def index():
    """Serve the web UI."""
    return send_file(
        Path(__file__).parent / "index.html",
        mimetype="text/html"
    )


def _retrieve_context(query: str) -> str:
    response = kb_client.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": MAX_RESULTS}
        },
    )
    chunks = [r["content"]["text"] for r in response.get("retrievalResults", [])]
    return "\n\n---\n\n".join(chunks) if chunks else "No relevant context found."


def _connector_targets() -> list[str]:
    targets: list[str] = []
    if os.environ.get("MCP_ENABLE_GITHUB", "false").lower() == "true":
        targets.append(
            f"github={os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/"
            f"{os.environ.get('GITHUB_REPOSITORY', 'owner/repo')}@{os.environ.get('GITHUB_BRANCH', 'main')}"
        )
    if os.environ.get("MCP_ENABLE_JIRA", "false").lower() == "true":
        targets.append(
            f"jira={os.environ.get('JIRA_SERVER_URL', 'https://your-org.atlassian.net')}"
            f"#{os.environ.get('JIRA_PROJECT_KEY', 'TEAM')}"
        )
    if os.environ.get("MCP_ENABLE_CONFLUENCE", "false").lower() == "true":
        targets.append(
            f"confluence={os.environ.get('CONFLUENCE_SERVER_URL', 'https://your-org.atlassian.net/wiki')}"
            f"#{os.environ.get('CONFLUENCE_SPACE_KEY', 'ENG')}"
        )
    return targets


def _provider_mode() -> str:
    return MODEL_PROVIDER if MODEL_PROVIDER in SUPPORTED_PROVIDER_MODES else "bedrock"


def _flag(name: str) -> bool:
    return os.environ.get(name, "false").lower() == "true"


def _csv_set(raw: str) -> set[str]:
    return {item.strip().lower() for item in raw.split(",") if item and item.strip()}


def _auth_required() -> bool:
    return _flag("AUTH_REQUIRED")


def _allowed_emails() -> set[str]:
    return _csv_set(os.environ.get("AUTH_ALLOWED_EMAILS", ""))


def _trusted_email_headers() -> list[str]:
    raw = os.environ.get(
        "AUTH_TRUSTED_EMAIL_HEADERS",
        "X-Forwarded-Email,X-Auth-Request-Email,X-Forwarded-User,Remote-Email",
    )
    return [h.strip() for h in raw.split(",") if h and h.strip()]


def _request_email() -> str:
    for header in _trusted_email_headers():
        value = request.headers.get(header, "").strip()
        if value:
            return value.lower()
    return ""


def _github_repo_scope() -> str:
    scope = os.environ.get("GITHUB_REPO_SCOPE", "any").strip().lower()
    return scope if scope in {"any", "configured", "allowlist"} else "any"


def _github_allowed_repositories() -> set[str]:
    return _csv_set(os.environ.get("GITHUB_ALLOWED_REPOSITORIES", ""))


def _azure_api_key() -> str:
    return os.environ.get("AZURE_OPENAI_API_KEY", "").strip()


def _azure_configured() -> bool:
    return bool(AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT and _azure_api_key())


def _available_providers(mode: str) -> list[str]:
    allowed = ["bedrock", "azure"] if mode == "dual" else [mode]
    available: list[str] = []
    if "bedrock" in allowed and MODEL_ID:
        available.append("bedrock")
    if "azure" in allowed and _azure_configured():
        available.append("azure")
    return available


def _select_provider(requested: str | None) -> tuple[str | None, str | None]:
    mode = _provider_mode()
    allowed = {"bedrock", "azure"} if mode == "dual" else {mode}

    if requested:
        requested = requested.strip().lower()
        if requested not in {"bedrock", "azure"}:
            return None, "provider must be one of: bedrock, azure"
        if requested not in allowed:
            return None, f"provider '{requested}' not allowed when MODEL_PROVIDER={mode}"
        candidate = requested
    else:
        candidate = "bedrock" if "bedrock" in allowed else "azure"

    if candidate == "azure" and not _azure_configured():
        if mode == "dual" and MODEL_ID:
            return "bedrock", None
        return None, "azure provider selected but AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT, or AZURE_OPENAI_API_KEY is missing"

    if candidate == "bedrock" and not MODEL_ID:
        return None, "bedrock provider selected but BEDROCK_MODEL_ID is missing"

    return candidate, None


def _history_to_openai_messages(history: list[dict[str, Any]]) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = []
    for turn in history:
        role = turn.get("role")
        if role not in {"user", "assistant", "system"}:
            continue

        content = turn.get("content")
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            text_parts = [part.get("text", "") for part in content if isinstance(part, dict)]
            text = "\n".join([p for p in text_parts if p])
        else:
            text = ""

        if text:
            messages.append({"role": role, "content": text})
    return messages


def _chat_with_azure(history: list[dict[str, Any]], system_prompt: str) -> str:
    try:
        from openai import AzureOpenAI
    except ImportError as exc:
        raise RuntimeError("openai package is required for Azure provider") from exc

    client = AzureOpenAI(
        api_key=_azure_api_key(),
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_version=AZURE_OPENAI_API_VERSION,
    )
    response = client.chat.completions.create(
        model=AZURE_OPENAI_DEPLOYMENT,
        messages=[{"role": "system", "content": system_prompt}, *_history_to_openai_messages(history)],
    )
    return (response.choices[0].message.content or "").strip()


@app.before_request
def enforce_request_auth():
    if not _auth_required():
        return None

    if request.path == "/health":
        return None

    email = _request_email()
    if not email:
        return jsonify({"error": "authentication required: missing trusted identity header"}), HTTPStatus.UNAUTHORIZED

    allowed = _allowed_emails()
    if allowed and email not in allowed:
        return jsonify({"error": "forbidden: user is not allowed for this chatbot"}), HTTPStatus.FORBIDDEN

    request.environ["chatbot.request_email"] = email
    return None


@app.get("/health")
def health():
    mode = _provider_mode()
    available = _available_providers(mode)
    model_name = MODEL_ID if ("bedrock" in available) else AZURE_OPENAI_DEPLOYMENT
    return jsonify(
        {
            "status": "ok",
            "model": model_name,
            "kb_id": KB_ID,
            "region": REGION,
            "provider_mode": mode,
            "available_providers": available,
        }
    )


@app.get("/capabilities")
def capabilities():
    mode = _provider_mode()
    return jsonify(
        {
            "provider_mode": mode,
            "available_providers": _available_providers(mode),
            "kb_id": KB_ID,
            "active_connectors": [
                connector
                for connector, enabled in [
                    ("github", _flag("MCP_ENABLE_GITHUB")),
                    ("jira", _flag("MCP_ENABLE_JIRA")),
                    ("confluence", _flag("MCP_ENABLE_CONFLUENCE")),
                ]
                if enabled
            ],
            "targets": _connector_targets(),
            "github_repo_scope": _github_repo_scope(),
            "github_allowed_repositories": sorted(_github_allowed_repositories()),
            "auth_required": _auth_required(),
        }
    )


@app.post("/chat")
def chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    requested_provider = (body.get("provider") or "").strip().lower() or None
    if not message:
        return jsonify({"error": "message is required"}), HTTPStatus.BAD_REQUEST

    provider, provider_error = _select_provider(requested_provider)
    if provider_error:
        return jsonify({"error": provider_error}), HTTPStatus.BAD_REQUEST

    history = list(body.get("history") or [])

    try:
        context = _retrieve_context(message)
    except ClientError as exc:
        return jsonify({"error": f"KB retrieval failed: {exc}"}), HTTPStatus.BAD_GATEWAY

    system_prompt = SYSTEM_TEMPLATE.format(context=context)
    history.append({"role": "user", "content": [{"text": message}]})

    if provider == "azure":
        try:
            reply = _chat_with_azure(history, system_prompt)
        except Exception as exc:
            return jsonify({"error": f"Azure OpenAI chat failed: {exc}"}), HTTPStatus.BAD_GATEWAY
        model_name = AZURE_OPENAI_DEPLOYMENT
    else:
        try:
            response = bedrock.converse(
                modelId=MODEL_ID,
                system=[{"text": system_prompt}],
                messages=history,
            )
        except ClientError as exc:
            return jsonify({"error": f"Bedrock Converse failed: {exc}"}), HTTPStatus.BAD_GATEWAY

        reply = response["output"]["message"]["content"][0]["text"]
        model_name = MODEL_ID

    history.append({"role": "assistant", "content": [{"text": reply}]})
    return jsonify({"reply": reply, "history": history, "model": model_name, "kb_id": KB_ID, "provider": provider})


if __name__ == "__main__":
    targets = _connector_targets()
    print(
        "RAG chatbot starting "
        f"(provider_mode={_provider_mode()}, bedrock_model={MODEL_ID}, azure_deployment={AZURE_OPENAI_DEPLOYMENT}, "
        f"kb={KB_ID}, region={REGION}, port={PORT})"
        + (f"\nConnector targets: {', '.join(targets)}" if targets else "")
    )
    app.run(host="0.0.0.0", port=PORT)

