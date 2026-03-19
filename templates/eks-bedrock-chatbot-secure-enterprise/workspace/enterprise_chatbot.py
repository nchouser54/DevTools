#!/usr/bin/env python3
"""
Enterprise Bedrock chatbot — stateless Flask service with RAG, OTel tracing, and structured logging.

All connector secrets are sourced from environment variables injected by the
External Secrets Operator (ESO). No plaintext credentials should appear in code.

Endpoints:
    GET  /health    Kubernetes liveness/readiness probe.
    POST /chat      Send a message; receive a grounded, traced reply.

Request body (POST /chat):
    {"message": "your question", "history": [...optional prior turns...]}

Response body:
    {"reply": "...", "history": [...], "model": "...", "kb_id": "..."}

Usage:
    export AWS_REGION=us-gov-west-1
    export BEDROCK_MODEL_ID=replace-with-govcloud-sonnet-4.5-model-id
    export BEDROCK_KB_ID=replace-me
    export OTEL_EXPORTER_OTLP_ENDPOINT=http://adot-collector:4317
    export OTEL_SERVICE_NAME=bedrock-chatbot-enterprise
    python workspace/enterprise_chatbot.py
"""
import os
from http import HTTPStatus

import boto3
import structlog
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "replace-with-govcloud-sonnet-4.5-model-id")
KB_ID = os.environ["BEDROCK_KB_ID"]
MAX_RESULTS = int(os.environ.get("RAG_MAX_RESULTS", "5"))
OTEL_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://adot-collector:4317")
SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "bedrock-chatbot-enterprise")
PORT = int(os.environ.get("PORT", "8080"))

# ---------------------------------------------------------------------------
# Structured logging
# ---------------------------------------------------------------------------
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer(),
    ]
)
log = structlog.get_logger()

# ---------------------------------------------------------------------------
# OpenTelemetry setup
# ---------------------------------------------------------------------------
resource = Resource.create({"service.name": SERVICE_NAME})
tracer_provider = TracerProvider(resource=resource)
tracer_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True))
)
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(SERVICE_NAME)

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
kb_client = boto3.client("bedrock-agent-runtime", region_name=REGION)

SYSTEM_TEMPLATE = (
    "You are a helpful enterprise assistant. Use ONLY the provided context to answer. "
    "If context is insufficient, say so. Do not fabricate information.\n\nContext:\n{context}"
)


def _flag(name: str) -> bool:
    return os.environ.get(name, "false").lower() == "true"


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


def _retrieve_context(query: str) -> str:
    with tracer.start_as_current_span("bedrock.retrieve") as span:
        span.set_attribute("kb.id", KB_ID)
        span.set_attribute("kb.max_results", MAX_RESULTS)
        response = kb_client.retrieve(
            knowledgeBaseId=KB_ID,
            retrievalQuery={"text": query},
            retrievalConfiguration={
                "vectorSearchConfiguration": {"numberOfResults": MAX_RESULTS}
            },
        )
    chunks = [r["content"]["text"] for r in response.get("retrievalResults", [])]
    return "\n\n---\n\n".join(chunks) if chunks else "No relevant context found."

# ---------------------------------------------------------------------------
# Flask application
# ---------------------------------------------------------------------------
app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify({
        "status": "ok",
        "model": MODEL_ID,
        "kb_id": KB_ID,
        "region": REGION,
        "service": SERVICE_NAME,
    })


@app.post("/chat")
def chat():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    if not message:
        return jsonify({"error": "message is required"}), HTTPStatus.BAD_REQUEST

    history = list(body.get("history") or [])

    with tracer.start_as_current_span("chatbot.turn") as span:
        span.set_attribute("user.input_length", len(message))

        try:
            context = _retrieve_context(message)
        except ClientError as exc:
            log.error("kb.retrieve_failed", error=str(exc))
            return jsonify({"error": f"KB retrieval failed: {exc}"}), HTTPStatus.BAD_GATEWAY

        system_prompt = SYSTEM_TEMPLATE.format(context=context)
        history.append({"role": "user", "content": [{"text": message}]})

        try:
            with tracer.start_as_current_span("bedrock.converse"):
                response = bedrock.converse(
                    modelId=MODEL_ID,
                    system=[{"text": system_prompt}],
                    messages=history,
                )
        except ClientError as exc:
            log.error("converse.failed", error=str(exc))
            return jsonify({"error": f"Bedrock Converse failed: {exc}"}), HTTPStatus.BAD_GATEWAY

        reply = response["output"]["message"]["content"][0]["text"]
        history.append({"role": "assistant", "content": [{"text": reply}]})
        span.set_attribute("reply.length", len(reply))
        log.info("chatbot.turn", input_tokens=len(message), output_tokens=len(reply))

    return jsonify({"reply": reply, "history": history, "model": MODEL_ID, "kb_id": KB_ID})


if __name__ == "__main__":
    targets = _connector_targets()
    log.info("chatbot.startup", model=MODEL_ID, kb=KB_ID, region=REGION, service=SERVICE_NAME)
    print(
        f"Enterprise chatbot starting (model={MODEL_ID}, kb={KB_ID}, region={REGION}, port={PORT})"
        + (f"\nConnector targets: {', '.join(targets)}" if targets else "")
    )
    app.run(host="0.0.0.0", port=PORT)
