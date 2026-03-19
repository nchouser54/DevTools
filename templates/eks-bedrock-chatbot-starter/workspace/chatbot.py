#!/usr/bin/env python3
"""
Bedrock Converse API — stateless Flask chatbot service.

Endpoints:
    GET  /health    Kubernetes liveness/readiness probe.
    POST /chat      Send a message; receive a reply.

Request body (POST /chat):
    {"message": "your question", "history": [...optional prior turns...]}

Response body:
    {"reply": "...", "history": [...], "model": "..."}

Usage:
    export AWS_REGION=us-gov-west-1
    export BEDROCK_MODEL_ID=replace-with-govcloud-sonnet-4.5-model-id
    python workspace/chatbot.py
"""
import os
from http import HTTPStatus

import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "replace-with-govcloud-sonnet-4.5-model-id")
PORT = int(os.environ.get("PORT", "8080"))

SYSTEM_PROMPT = "You are a helpful assistant. Answer concisely and accurately."

app = Flask(__name__)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)


@app.get("/health")
def health():
    return jsonify({"status": "ok", "model": MODEL_ID, "region": REGION})


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
            system=[{"text": SYSTEM_PROMPT}],
            messages=history,
        )
    except ClientError as exc:
        return jsonify({"error": str(exc)}), HTTPStatus.BAD_GATEWAY

    reply = response["output"]["message"]["content"][0]["text"]
    history.append({"role": "assistant", "content": [{"text": reply}]})
    return jsonify({"reply": reply, "history": history, "model": MODEL_ID})


if __name__ == "__main__":
    print(f"Bedrock chatbot starting (model={MODEL_ID}, region={REGION}, port={PORT})")
    app.run(host="0.0.0.0", port=PORT)

