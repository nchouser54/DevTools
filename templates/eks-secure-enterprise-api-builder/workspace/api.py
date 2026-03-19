#!/usr/bin/env python3
"""
Secure API starter service for EKS Secure Enterprise API Builder.

Endpoints:
  GET /health
  POST /v1/echo
"""
import os
from http import HTTPStatus

from flask import Flask, jsonify, request

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
LOG_LEVEL = os.environ.get("API_LOG_LEVEL", "info")
PORT = int(os.environ.get("PORT", "8080"))

app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify({"status": "ok", "region": REGION, "logLevel": LOG_LEVEL})


@app.post("/v1/echo")
def echo():
    body = request.get_json(silent=True) or {}
    message = (body.get("message") or "").strip()
    if not message:
        return jsonify({"error": "message is required"}), HTTPStatus.BAD_REQUEST

    return jsonify(
        {
            "reply": f"echo: {message}",
            "region": REGION,
            "logLevel": LOG_LEVEL,
        }
    )


if __name__ == "__main__":
    print(f"Secure API builder service starting (region={REGION}, logLevel={LOG_LEVEL}, port={PORT})")
    app.run(host="0.0.0.0", port=PORT)
