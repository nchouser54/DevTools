#!/usr/bin/env python3
"""
RAG-enabled Bedrock chatbot — stateless Flask service.

Retrieves grounded context from a Bedrock Knowledge Base before each Converse call,
reducing hallucination and anchoring answers to your document corpus.

Endpoints:
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

import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "replace-with-govcloud-sonnet-4.5-model-id")
KB_ID = os.environ["BEDROCK_KB_ID"]
MAX_RESULTS = int(os.environ.get("RAG_MAX_RESULTS", "5"))
PORT = int(os.environ.get("PORT", "8080"))

SYSTEM_TEMPLATE = (
    "You are a helpful assistant. Use ONLY the provided context to answer questions. "
    "If the context does not contain enough information, say so. Do not fabricate answers.\n\n"
    "Context:\n{context}"
)

app = Flask(__name__)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)


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


@app.get("/health")
def health():
    return jsonify({"status": "ok", "model": MODEL_ID, "kb_id": KB_ID, "region": REGION})


@app.post("/chat")
def chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    if not message:
        return jsonify({"error": "message is required"}), HTTPStatus.BAD_REQUEST

    history = list(body.get("history") or [])

    try:
        context = _retrieve_context(message)
    except ClientError as exc:
        return jsonify({"error": f"KB retrieval failed: {exc}"}), HTTPStatus.BAD_GATEWAY

    system_prompt = SYSTEM_TEMPLATE.format(context=context)
    history.append({"role": "user", "content": [{"text": message}]})

    try:
        response = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": system_prompt}],
            messages=history,
        )
    except ClientError as exc:
        return jsonify({"error": f"Bedrock Converse failed: {exc}"}), HTTPStatus.BAD_GATEWAY

    reply = response["output"]["message"]["content"][0]["text"]
    history.append({"role": "assistant", "content": [{"text": reply}]})
    return jsonify({"reply": reply, "history": history, "model": MODEL_ID, "kb_id": KB_ID})


if __name__ == "__main__":
    targets = _connector_targets()
    print(
        f"RAG chatbot starting (model={MODEL_ID}, kb={KB_ID}, region={REGION}, port={PORT})"
        + (f"\nConnector targets: {', '.join(targets)}" if targets else "")
    )
    app.run(host="0.0.0.0", port=PORT)

